# S3 bucket to store Lambda artifacts and the rules list
module "findings_manager_bucket" {
  #checkov:skip=CKV_AWS_145:Bug in CheckOV https://github.com/bridgecrewio/checkov/issues/3847
  #checkov:skip=CKV_AWS_19:Bug in CheckOV https://github.com/bridgecrewio/checkov/issues/3847
  source  = "schubergphilis/mcaf-s3/aws"
  version = "~> 0.11.0"

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
module "lambda_findings_manager_role" {
  source  = "schubergphilis/mcaf-role/aws"
  version = "~> 0.3.2"

  name                  = var.lambda_findings_manager_iam_role_name
  create_policy         = true
  postfix               = false
  principal_identifiers = ["lambda.amazonaws.com"]
  principal_type        = "Service"
  role_policy           = data.aws_iam_policy_document.lambda_findings_manager.json
  tags                  = var.tags
}

data "aws_iam_policy_document" "lambda_findings_manager" {
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
resource "aws_iam_role_policy_attachment" "lambda_findings_manager_role_vpc_policy" {
  count      = var.subnet_ids != null ? 1 : 0
  role       = module.lambda_findings_manager_role.id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Create a Lambda zip deployment package with code and dependencies
module "lambda_findings_manager_deployment_package" {
  source                   = "terraform-aws-modules/lambda/aws"
  version                  = "~> 3.3.0"
  create_function          = false
  recreate_missing_package = false
  runtime                  = "python3.8"
  s3_bucket                = module.findings_manager_bucket.name
  s3_object_storage_class  = "STANDARD"
  source_path              = "${path.module}/files/lambda-artifacts/securityhub-findings-manager"
  store_on_s3              = true
}

# Lambda function to manage Security Hub findings in response to an EventBridge event
module "lambda_findings_manager_events" {
  #checkov:skip=CKV_AWS_272:Code signing not used for now
  source  = "schubergphilis/mcaf-lambda/aws"
  version = "~> 1.1.0"

  name                        = var.lambda_findings_manager_events.name
  create_policy               = false
  create_s3_dummy_object      = false
  description                 = "Lambda to manage Security Hub findings in response to an EventBridge event"
  filename                    = module.lambda_findings_manager_deployment_package.local_filename
  handler                     = "securityhub_events.lambda_handler"
  kms_key_arn                 = var.kms_key_arn
  log_retention               = 365
  memory_size                 = var.lambda_findings_manager_events.memory_size
  role_arn                    = module.lambda_findings_manager_role.arn
  runtime                     = var.lambda_findings_manager_events.runtime
  s3_bucket                   = var.s3_bucket_name
  s3_key                      = module.lambda_findings_manager_deployment_package.s3_object.key
  s3_object_version           = module.lambda_findings_manager_deployment_package.s3_object.version_id
  security_group_egress_rules = var.lambda_findings_manager_events.security_group_egress_rules
  subnet_ids                  = var.subnet_ids
  tags                        = var.tags
  timeout                     = var.lambda_findings_manager_events.timeout

  environment = {
    S3_BUCKET_NAME              = var.s3_bucket_name
    S3_OBJECT_NAME              = var.rules_s3_object_name
    LOG_LEVEL                   = var.lambda_findings_manager_events.log_level
    POWERTOOLS_LOGGER_LOG_EVENT = "false"
    POWERTOOLS_SERVICE_NAME     = "securityhub-findings-manager-events"
  }
}

# Lambda to manage Security Hub findings in response to S3 rules file uploads
module "lambda_findings_manager_trigger" {
  #checkov:skip=CKV_AWS_272:Code signing not used for now
  source  = "schubergphilis/mcaf-lambda/aws"
  version = "~> 1.1.0"

  name                        = var.lambda_findings_manager_trigger.name
  create_policy               = false
  create_s3_dummy_object      = false
  description                 = "Lambda to manage Security Hub findings in response to S3 rules file uploads"
  filename                    = module.lambda_findings_manager_deployment_package.local_filename
  handler                     = "securityhub_trigger.lambda_handler"
  kms_key_arn                 = var.kms_key_arn
  log_retention               = 365
  memory_size                 = var.lambda_findings_manager_trigger.memory_size
  role_arn                    = module.lambda_findings_manager_role.arn
  runtime                     = var.lambda_findings_manager_trigger.runtime
  s3_bucket                   = var.s3_bucket_name
  s3_key                      = module.lambda_findings_manager_deployment_package.s3_object.key
  s3_object_version           = module.lambda_findings_manager_deployment_package.s3_object.version_id
  security_group_egress_rules = var.lambda_findings_manager_trigger.security_group_egress_rules
  subnet_ids                  = var.subnet_ids
  tags                        = var.tags
  timeout                     = var.lambda_findings_manager_trigger.timeout

  environment = {
    S3_BUCKET_NAME              = var.s3_bucket_name
    S3_OBJECT_NAME              = var.rules_s3_object_name
    LOG_LEVEL                   = var.lambda_findings_manager_trigger.log_level
    POWERTOOLS_LOGGER_LOG_EVENT = "false"
    POWERTOOLS_SERVICE_NAME     = "securityhub-findings-manager-trigger"
  }
}

# EventBridge Rule that detect Security Hub events with compliance status as failed
resource "aws_cloudwatch_event_rule" "securityhub_findings_events" {
  name        = "rule-${var.lambda_findings_manager_events.name}"
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
resource "aws_lambda_permission" "allow_eventbridge_to_invoke_findings_manager_lambda" {
  count         = var.jira_integration.enabled ? 0 : 1
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_findings_manager_events.name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.securityhub_findings_events.arn
}

# Add Security Hub Events Lambda function as a target to the EventBridge rule
resource "aws_cloudwatch_event_target" "lambda_findings_manager_events" {
  count = var.jira_integration.enabled ? 0 : 1
  arn   = module.lambda_findings_manager_events.arn
  rule  = aws_cloudwatch_event_rule.securityhub_findings_events.name
}

# Allow S3 to invoke S3 Trigger Lambda function
resource "aws_lambda_permission" "allow_s3_to_invoke_trigger_lambda" {
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_findings_manager_trigger.name
  principal     = "s3.amazonaws.com"
  source_arn    = module.findings_manager_bucket.arn
}

# Add Security Hub Trigger Lambda function as a target to rules S3 Object Creation Trigger Events
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = module.findings_manager_bucket.name

  lambda_function {
    lambda_function_arn = module.lambda_findings_manager_trigger.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = var.rules_s3_object_name
    filter_suffix       = var.rules_s3_object_name
  }

  depends_on = [aws_lambda_permission.allow_s3_to_invoke_trigger_lambda]
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

  depends_on = [aws_s3_bucket_notification.bucket_notification]
}
