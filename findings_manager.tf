# S3 bucket to store Lambda artifacts and the rules list
module "findings_manager_bucket" {
  #checkov:skip=CKV_AWS_145:Bug in CheckOV https://github.com/bridgecrewio/checkov/issues/3847
  #checkov:skip=CKV_AWS_19:Bug in CheckOV https://github.com/bridgecrewio/checkov/issues/3847
  source  = "schubergphilis/mcaf-s3/aws"
  version = "~> 0.14.1"

  name        = var.s3_bucket_name
  kms_key_arn = var.kms_key_arn
  logging     = null
  tags        = var.tags
  versioning  = true

  lifecycle_rule = [
    {
      id      = "default"
      enabled = true

      abort_incomplete_multipart_upload = {
        days_after_initiation = 7
      }

      expiration = {
        expired_object_delete_marker = true
      }

      noncurrent_version_expiration = {
        noncurrent_days = 7
      }
    }
  ]
}

# IAM role to be assumed by Lambda function
module "findings_manager_lambda_iam_role" {
  source  = "schubergphilis/mcaf-role/aws"
  version = "~> 0.4.0"

  name                  = var.findings_manager_lambda_iam_role_name
  create_policy         = true
  principal_identifiers = ["lambda.amazonaws.com"]
  principal_type        = "Service"
  role_policy           = data.aws_iam_policy_document.findings_manager_lambda_iam_role.json
  tags                  = var.tags
}

data "aws_iam_policy_document" "findings_manager_lambda_iam_role" {
  statement {
    sid = "TrustEventsToStoreLogEvent"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
    ]
  }

  statement {
    sid       = "S3GetObjectAccess"
    actions   = ["s3:GetObject"]
    resources = ["${module.findings_manager_bucket.arn}/*"]
  }

  statement {
    sid       = "EC2DescribeRegionsAccess"
    actions   = ["ec2:DescribeRegions"]
    resources = ["*"]
  }

  statement {
    sid = "SecurityHubAccess"
    actions = [
      "securityhub:BatchUpdateFindings",
      "securityhub:GetFindings"
    ]
    resources = [
      "arn:aws:securityhub:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:hub/default"
    ]
  }

  statement {
    sid = "LambdaKMSAccess"
    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:GenerateDataKey*",
      "kms:ReEncrypt*"
    ]
    effect = "Allow"
    resources = [
      var.kms_key_arn
    ]
  }
}

# Lambda VPC Execution role policy attachment
resource "aws_iam_role_policy_attachment" "findings_manager_lambda_iam_role" {
  count = var.subnet_ids != null ? 1 : 0

  role       = module.findings_manager_lambda_iam_role.id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_s3_object" "lambda_package_finding_manager" {
  bucket     = module.findings_manager_bucket.id
  key        = "${var.findings_manager_events_lambda.name}-lambda_function_${var.python_version}.zip"
  kms_key_id = var.kms_key_arn
  source     = "${path.module}/files/pkg/securityhub-findings-manager/lambda_function_${var.python_version}.zip"
  tags       = var.tags
}

################################################################################
# Events Lambda
################################################################################

# Lambda function to manage Security Hub findings in response to an EventBridge event
module "findings_manager_events_lambda" {
  #checkov:skip=CKV_AWS_272:Code signing not used for now
  source  = "schubergphilis/mcaf-lambda/aws"
  version = "~> 1.4.1"

  name                        = var.findings_manager_events_lambda.name
  create_policy               = false
  create_s3_dummy_object      = false
  description                 = "Lambda to manage Security Hub findings in response to an EventBridge event"
  handler                     = "securityhub_events.lambda_handler"
  kms_key_arn                 = var.kms_key_arn
  log_retention               = 365
  memory_size                 = var.findings_manager_events_lambda.memory_size
  role_arn                    = module.findings_manager_lambda_iam_role.arn
  runtime                     = var.findings_manager_events_lambda.runtime
  s3_bucket                   = "${var.s3_bucket_name}-lambda-${data.aws_caller_identity.current.account_id}"
  s3_key                      = aws_s3_object.lambda_package_finding_manager.key
  s3_object_version           = aws_s3_object.lambda_package_finding_manager.version_id
  source_code_hash            = aws_s3_object.lambda_package_finding_manager.checksum_sha256
  security_group_egress_rules = var.findings_manager_events_lambda.security_group_egress_rules
  subnet_ids                  = var.subnet_ids
  tags                        = var.tags
  timeout                     = var.findings_manager_events_lambda.timeout

  environment = {
    S3_BUCKET_NAME              = var.s3_bucket_name
    S3_OBJECT_NAME              = var.rules_s3_object_name
    LOG_LEVEL                   = var.findings_manager_events_lambda.log_level
    POWERTOOLS_LOGGER_LOG_EVENT = "false"
    POWERTOOLS_SERVICE_NAME     = "securityhub-findings-manager-events"
  }
  depends_on = [aws_s3_object.lambda_package_finding_manager]
}

# EventBridge Rule that detect Security Hub events with compliance status as failed
resource "aws_cloudwatch_event_rule" "securityhub_findings_events" {
  name        = "rule-${var.findings_manager_events_lambda.name}"
  description = "EventBridge Rule that detects Security Hub events with compliance status as failed and workflow status as new or notified"
  tags        = var.tags

  event_pattern = <<EOF
{
  "source": ["aws.securityhub"],
  "detail-type": ["Security Hub Findings - Imported"],
  "detail": {
    "findings": {
      "Compliance": {
        "Status": ["FAILED", "WARNING"]
      },
      "Workflow": {
        "Status": ["NEW", "NOTIFIED"]
      }
    }
  }
}
EOF
}

# Allow Eventbridge to invoke Security Hub Events Lambda function
resource "aws_lambda_permission" "eventbridge_invoke_findings_manager_events_lambda" {
  count = var.jira_integration.enabled ? 0 : 1

  action        = "lambda:InvokeFunction"
  function_name = var.findings_manager_events_lambda.name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.securityhub_findings_events.arn
}

# Add Security Hub Events Lambda function as a target to the EventBridge rule
resource "aws_cloudwatch_event_target" "findings_manager_events_lambda" {
  count = var.jira_integration.enabled ? 0 : 1

  arn  = module.findings_manager_events_lambda.arn
  rule = aws_cloudwatch_event_rule.securityhub_findings_events.name
}

################################################################################
# Trigger Lambda
################################################################################

# Lambda to manage Security Hub findings in response to S3 rules file uploads
module "findings_manager_trigger_lambda" {
  #checkov:skip=CKV_AWS_272:Code signing not used for now
  source  = "schubergphilis/mcaf-lambda/aws"
  version = "~> 1.4.1"

  name                   = var.findings_manager_trigger_lambda.name
  create_policy          = false
  create_s3_dummy_object = false
  description            = "Lambda to manage Security Hub findings in response to S3 rules file uploads"
  # filename                    = module.findings_manager_lambda_deployment_package.local_filename
  handler                     = "securityhub_trigger.lambda_handler"
  kms_key_arn                 = var.kms_key_arn
  log_retention               = 365
  memory_size                 = var.findings_manager_trigger_lambda.memory_size
  role_arn                    = module.findings_manager_lambda_iam_role.arn
  runtime                     = var.findings_manager_trigger_lambda.runtime
  s3_bucket                   = "${var.s3_bucket_name}-lambda-${data.aws_caller_identity.current.account_id}"
  s3_key                      = aws_s3_object.lambda_package_finding_manager.key
  s3_object_version           = aws_s3_object.lambda_package_finding_manager.version_id
  source_code_hash            = aws_s3_object.lambda_package_finding_manager.checksum_sha256
  security_group_egress_rules = var.findings_manager_trigger_lambda.security_group_egress_rules
  subnet_ids                  = var.subnet_ids
  tags                        = var.tags
  timeout                     = var.findings_manager_trigger_lambda.timeout

  environment = {
    S3_BUCKET_NAME              = var.s3_bucket_name
    S3_OBJECT_NAME              = var.rules_s3_object_name
    LOG_LEVEL                   = var.findings_manager_trigger_lambda.log_level
    POWERTOOLS_LOGGER_LOG_EVENT = "false"
    POWERTOOLS_SERVICE_NAME     = "securityhub-findings-manager-trigger"
  }
}

# Allow S3 to invoke S3 Trigger Lambda function
resource "aws_lambda_permission" "s3_invoke_findings_manager_trigger_lambda" {
  action         = "lambda:InvokeFunction"
  function_name  = var.findings_manager_trigger_lambda.name
  principal      = "s3.amazonaws.com"
  source_account = data.aws_caller_identity.current.account_id
  source_arn     = module.findings_manager_bucket.arn
}

# Add Security Hub Trigger Lambda function as a target to rules S3 Object Creation Trigger Events
resource "aws_s3_bucket_notification" "findings_manager_trigger" {
  bucket = module.findings_manager_bucket.name

  lambda_function {
    lambda_function_arn = module.findings_manager_trigger_lambda.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = var.rules_s3_object_name
    filter_suffix       = var.rules_s3_object_name
  }

  depends_on = [aws_lambda_permission.s3_invoke_findings_manager_trigger_lambda]
}

# Upload rules list to S3
resource "aws_s3_object" "rules" {
  count = var.rules_filepath == "" ? 0 : 1

  bucket       = module.findings_manager_bucket.name
  key          = var.rules_s3_object_name
  content_type = "application/x-yaml"
  content      = file(var.rules_filepath)
  source_hash  = filemd5(var.rules_filepath)
  tags         = var.tags

  # Even with this in place, the creation sometimes doesn't get picked up on a first deploy
  depends_on = [aws_s3_bucket_notification.findings_manager_trigger]
}
