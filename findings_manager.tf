locals {
  workflow_status_filter = var.jira_integration.autoclose_enabled ? ["NEW", "NOTIFIED", "RESOLVED"] : ["NEW", "NOTIFIED"]
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
    sid = "SecurityHubAccessList"
    actions = [
      "securityhub:ListFindingAggregators"
    ]
    resources = ["*"]
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

  statement {
    sid = "LambdaSQSAllow"
    actions = [
      "sqs:SendMessage",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes"
    ]
    effect    = "Allow"
    resources = [aws_sqs_queue.findings_manager_rule_q.arn]
  }

}

# Push the Lambda code zip deployment package to s3
resource "aws_s3_object" "findings_manager_lambdas_deployment_package" {
  bucket      = module.findings_manager_bucket.id
  key         = "lambda_securityhub-findings-manager_${var.lambda_runtime}.zip"
  kms_key_id  = var.kms_key_arn
  source      = "${path.module}/files/pkg/lambda_securityhub-findings-manager_${var.lambda_runtime}.zip"
  source_hash = filemd5("${path.module}/files/pkg/lambda_securityhub-findings-manager_${var.lambda_runtime}.zip")
  tags        = var.tags
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
  create_policy               = true
  create_s3_dummy_object      = false
  description                 = "Lambda to manage Security Hub findings in response to an EventBridge event"
  handler                     = "securityhub_events.lambda_handler"
  kms_key_arn                 = var.kms_key_arn
  layers                      = ["arn:aws:lambda:${data.aws_region.current.name}:017000801446:layer:AWSLambdaPowertoolsPythonV2:79"]
  log_retention               = 365
  memory_size                 = var.findings_manager_events_lambda.memory_size
  policy                      = data.aws_iam_policy_document.findings_manager_lambda_iam_role.json
  runtime                     = var.lambda_runtime
  s3_bucket                   = var.s3_bucket_name
  s3_key                      = aws_s3_object.findings_manager_lambdas_deployment_package.key
  s3_object_version           = aws_s3_object.findings_manager_lambdas_deployment_package.version_id
  security_group_egress_rules = var.findings_manager_events_lambda.security_group_egress_rules
  source_code_hash            = aws_s3_object.findings_manager_lambdas_deployment_package.checksum_sha256
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
}

# EventBridge Rule that detect Security Hub events
resource "aws_cloudwatch_event_rule" "securityhub_findings_events" {
  name        = "rule-${var.findings_manager_events_lambda.name}"
  description = "EventBridge rule for detecting Security Hub findings events, triggering the findings manager events lambda."
  tags        = var.tags

  event_pattern = <<EOF
{
  "source": ["aws.securityhub"],
  "detail-type": ["Security Hub Findings - Imported"],
  "detail": {
    "findings": {
      "Workflow": {
        "Status": ${jsonencode(local.workflow_status_filter)}
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

  name                        = var.findings_manager_trigger_lambda.name
  create_policy               = true
  create_s3_dummy_object      = false
  description                 = "Lambda to manage Security Hub findings in response to S3 rules file uploads"
  handler                     = "securityhub_trigger.lambda_handler"
  kms_key_arn                 = var.kms_key_arn
  layers                      = ["arn:aws:lambda:${data.aws_region.current.name}:017000801446:layer:AWSLambdaPowertoolsPythonV2:79"]
  log_retention               = 365
  memory_size                 = var.findings_manager_trigger_lambda.memory_size
  policy                      = data.aws_iam_policy_document.findings_manager_lambda_iam_role.json
  runtime                     = var.lambda_runtime
  s3_bucket                   = var.s3_bucket_name
  s3_key                      = aws_s3_object.findings_manager_lambdas_deployment_package.key
  s3_object_version           = aws_s3_object.findings_manager_lambdas_deployment_package.version_id
  security_group_egress_rules = var.findings_manager_trigger_lambda.security_group_egress_rules
  source_code_hash            = aws_s3_object.findings_manager_lambdas_deployment_package.checksum_sha256
  subnet_ids                  = var.subnet_ids
  tags                        = var.tags
  timeout                     = var.findings_manager_trigger_lambda.timeout

  environment = {
    S3_BUCKET_NAME              = var.s3_bucket_name
    S3_OBJECT_NAME              = var.rules_s3_object_name
    LOG_LEVEL                   = var.findings_manager_trigger_lambda.log_level
    SQS_QUEUE_NAME              = aws_sqs_queue.findings_manager_rule_q.name
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

################################################################################
# Worker Lambda
################################################################################

# Lambda to manage Security Hub findings in response to S3 rules file uploads
module "findings_manager_worker_lambda" {
  #checkov:skip=CKV_AWS_272:Code signing not used for now
  source  = "schubergphilis/mcaf-lambda/aws"
  version = "~> 1.4.1"

  name                        = var.findings_manager_worker_lambda.name
  create_policy               = true
  create_s3_dummy_object      = false
  description                 = "Lambda to manage Security Hub findings in response to rules on SQS"
  handler                     = "securityhub_trigger_worker.lambda_handler"
  kms_key_arn                 = var.kms_key_arn
  layers                      = ["arn:aws:lambda:${data.aws_region.current.name}:017000801446:layer:AWSLambdaPowertoolsPythonV2:79"]
  log_retention               = 365
  memory_size                 = var.findings_manager_worker_lambda.memory_size
  policy                      = data.aws_iam_policy_document.findings_manager_lambda_iam_role.json
  runtime                     = var.lambda_runtime
  s3_bucket                   = var.s3_bucket_name
  s3_key                      = aws_s3_object.findings_manager_lambdas_deployment_package.key
  s3_object_version           = aws_s3_object.findings_manager_lambdas_deployment_package.version_id
  security_group_egress_rules = var.findings_manager_worker_lambda.security_group_egress_rules
  source_code_hash            = aws_s3_object.findings_manager_lambdas_deployment_package.checksum_sha256
  subnet_ids                  = var.subnet_ids
  tags                        = var.tags
  timeout                     = var.findings_manager_worker_lambda.timeout

  environment = {
    LOG_LEVEL                   = var.findings_manager_worker_lambda.log_level
    POWERTOOLS_LOGGER_LOG_EVENT = "false"
    POWERTOOLS_SERVICE_NAME     = "securityhub-findings-manager-worker"
  }
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

# SQS queue to distribute the rules to the lambda worker
resource "aws_sqs_queue" "findings_manager_rule_q" {
  name                       = "SecurityHubFindingsManagerRuleQueue"
  kms_master_key_id          = var.kms_key_arn
  visibility_timeout_seconds = var.findings_manager_worker_lambda.timeout
  # Queue visibility timeout needs to >= Function timeout
}

resource "aws_sqs_queue_policy" "findings_manager_rule_sqs_policy" {
  policy    = data.aws_iam_policy_document.findings_manager_rule_sqs_policy_doc.json
  queue_url = aws_sqs_queue.findings_manager_rule_q.id
}

resource "aws_sqs_queue" "dlq_for_findings_manager_rule_q" {
  name              = "DlqForSecurityHubFindingsManagerRuleQueue"
  kms_master_key_id = var.kms_key_arn
}

resource "aws_sqs_queue_redrive_policy" "redrive_policy" {
  queue_url = aws_sqs_queue.findings_manager_rule_q.id
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq_for_findings_manager_rule_q.arn
    maxReceiveCount     = 10
  })
}

resource "aws_sqs_queue_redrive_allow_policy" "dead_letter_allow_policy" {
  queue_url = aws_sqs_queue.dlq_for_findings_manager_rule_q.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue",
    sourceQueueArns   = [aws_sqs_queue.findings_manager_rule_q.arn]
  })
}

data "aws_iam_policy_document" "findings_manager_rule_sqs_policy_doc" {
  statement {
    actions = [
      "SQS:SendMessage"
    ]
    resources = [aws_sqs_queue.findings_manager_rule_q.arn]
    principals {
      identifiers = ["lambda.amazonaws.com"]
      type        = "Service"
    }
    condition {
      test     = "ArnEquals"
      values   = [module.findings_manager_trigger_lambda.name]
      variable = "aws:SourceArn"
    }
  }
}

# The SQS queue with rules triggers the worker lambda
resource "aws_lambda_event_source_mapping" "sqs_to_worker" {
  event_source_arn = aws_sqs_queue.findings_manager_rule_q.arn
  function_name    = module.findings_manager_worker_lambda.name
  # assumes a rule processing time of 30 sec average (which is high)
  batch_size                         = var.findings_manager_worker_lambda.timeout / 30
  maximum_batching_window_in_seconds = 60
  scaling_config {
    maximum_concurrency = 4 #  to prevent Security Hub API rate limits
  }
  enabled = true
}
