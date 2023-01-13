# DynamoDB table for storing suppressions list
resource "aws_dynamodb_table" "suppressor_dynamodb_table" {
  name             = var.dynamodb_table
  billing_mode     = "PAY_PER_REQUEST"
  hash_key         = "controlId"
  stream_enabled   = true
  stream_view_type = "KEYS_ONLY"

  attribute {
    name = "controlId"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  tags = var.tags
}

# S3 bucket to store Lambda artifacts
module "lambda_artifacts_bucket" {
  #checkov:skip=CKV_AWS_145:Bug in CheckOV
  name        = var.s3_bucket_name
  source      = "github.com/schubergphilis/terraform-aws-mcaf-s3?ref=v0.6.0"
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

# IAM role to be assumed by Lambda Function
module "lambda_security_hub_suppressor_role" {
  source                = "github.com/schubergphilis/terraform-aws-mcaf-role?ref=v0.3.2"
  name                  = var.lambda_suppressor_iam_role_name
  create_policy         = true
  postfix               = false
  principal_identifiers = ["lambda.amazonaws.com"]
  principal_type        = "Service"
  role_policy           = data.aws_iam_policy_document.lambda_security_hub_suppressor.json
  tags                  = var.tags
}

data "aws_iam_policy_document" "lambda_security_hub_suppressor" {
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
    sid = "DynamoDBGetItemAccess"
    actions = [
      "dynamodb:GetItem"
    ]
    resources = [
      "${aws_dynamodb_table.suppressor_dynamodb_table.arn}"
    ]
  }

  statement {
    sid = "DynamoDBStreamsAccess"
    actions = [
      "dynamodb:DescribeStream",
      "dynamodb:GetRecords",
      "dynamodb:GetShardIterator",
      "dynamodb:ListStreams"
    ]
    resources = [
      "${aws_dynamodb_table.suppressor_dynamodb_table.stream_arn}"
    ]
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
resource "aws_iam_role_policy_attachment" "lambda_security_hub_suppressor_role_vpc_policy" {
  count      = var.subnet_ids != null ? 1 : 0
  role       = module.lambda_security_hub_suppressor_role.id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Create a Lambda zip deployment package with code and dependencies
module "lambda_suppressor_deployment_package" {
  source                   = "terraform-aws-modules/lambda/aws"
  version                  = "~> 3.3.0"
  create_function          = false
  recreate_missing_package = false
  runtime                  = "python3.8"
  s3_bucket                = module.lambda_artifacts_bucket.name
  s3_object_storage_class  = "STANDARD"
  source_path              = "${path.module}/files/lambda-artifacts/securityhub-suppressor"
  store_on_s3              = true
}

# Lambda function to suppress Security Hub findings in response to an EventBridge trigger
module "lambda_securityhub_events_suppressor" {
  #checkov:skip=CKV_AWS_272:Code signing not used for now
  providers                    = { aws.lambda = aws }
  source                       = "github.com/schubergphilis/terraform-aws-mcaf-lambda?ref=v0.3.3"
  name                         = var.lambda_events_suppressor_name
  create_allow_all_egress_rule = var.create_allow_all_egress_rule
  create_policy                = false
  create_s3_dummy_object       = false
  description                  = "Lambda to suppress Security Hub findings in response to an EventBridge trigger"
  filename                     = module.lambda_suppressor_deployment_package.local_filename
  handler                      = "securityhub_events.lambda_handler"
  kms_key_arn                  = var.kms_key_arn
  log_retention                = 365
  memory_size                  = 256
  role_arn                     = module.lambda_security_hub_suppressor_role.arn
  runtime                      = "python3.8"
  s3_bucket                    = var.s3_bucket_name
  s3_key                       = module.lambda_suppressor_deployment_package.s3_object.key
  s3_object_version            = module.lambda_suppressor_deployment_package.s3_object.version_id
  subnet_ids                   = var.subnet_ids
  tags                         = var.tags
  timeout                      = 60

  environment = {
    DYNAMODB_TABLE_NAME         = var.dynamodb_table
    LOG_LEVEL                   = var.lambda_log_level
    POWERTOOLS_LOGGER_LOG_EVENT = "false"
    POWERTOOLS_SERVICE_NAME     = "securityhub-suppressor"
  }
}

# Lambda to suppress Security Hub findings in response to DynamoDB stream event
module "lambda_securityhub_streams_suppressor" {
  #checkov:skip=CKV_AWS_272:Code signing not used for now
  providers                    = { aws.lambda = aws }
  source                       = "github.com/schubergphilis/terraform-aws-mcaf-lambda?ref=v0.3.3"
  name                         = var.lambda_streams_suppressor_name
  create_allow_all_egress_rule = var.create_allow_all_egress_rule
  create_policy                = false
  create_s3_dummy_object       = false
  description                  = "Lambda to suppress Security Hub findings in response to DynamoDB stream event"
  filename                     = module.lambda_suppressor_deployment_package.local_filename
  handler                      = "securityhub_streams.lambda_handler"
  kms_key_arn                  = var.kms_key_arn
  log_retention                = 365
  memory_size                  = 256
  role_arn                     = module.lambda_security_hub_suppressor_role.arn
  runtime                      = "python3.8"
  s3_bucket                    = var.s3_bucket_name
  s3_key                       = module.lambda_suppressor_deployment_package.s3_object.key
  s3_object_version            = module.lambda_suppressor_deployment_package.s3_object.version_id
  subnet_ids                   = var.subnet_ids
  tags                         = var.tags
  timeout                      = 60

  environment = {
    DYNAMODB_TABLE_NAME         = var.dynamodb_table
    LOG_LEVEL                   = var.lambda_log_level
    POWERTOOLS_LOGGER_LOG_EVENT = "false"
    POWERTOOLS_SERVICE_NAME     = "securityhub-suppressor"
  }
}

# EventBridge Rule that detect Security Hub events with compliance status as failed
resource "aws_cloudwatch_event_rule" "securityhub_events_suppressor_failed_events" {
  name        = "rule-${var.lambda_events_suppressor_name}"
  description = "EventBridge Rule that detects Security Hub events with compliance status as failed and workflow status as new or notified"

  event_pattern = <<EOF
{
  "source": ["aws.securityhub"],
  "detail-type": ["Security Hub Findings - Imported"],
  "detail": {
    "findings": {
      "Compliance": {
        "Status": ["FAILED"]
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
resource "aws_lambda_permission" "allow_eventbridge_to_invoke_suppressor_lambda" {
  count         = var.jira_integration ? 0 : 1
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_events_suppressor_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.securityhub_events_suppressor_failed_events.arn
}

# Add Security Hub Events Lambda function as a target to the EventBridge rule
resource "aws_cloudwatch_event_target" "lambda_securityhub_events_suppressor" {
  count = var.jira_integration ? 0 : 1
  arn   = module.lambda_securityhub_events_suppressor.arn
  rule  = aws_cloudwatch_event_rule.securityhub_events_suppressor_failed_events.name
}

# Create event source mapping between Security Hub Streams Lambda function and DynamoDB streams
resource "aws_lambda_event_source_mapping" "lambda_securityhub_streams_mapping" {
  event_source_arn  = aws_dynamodb_table.suppressor_dynamodb_table.stream_arn
  function_name     = module.lambda_securityhub_streams_suppressor.name
  starting_position = "LATEST"
}
