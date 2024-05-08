# S3 bucket to store suppressions list
module "suppressions_bucket" {
  #checkov:skip=CKV_AWS_145:Bug in CheckOV https://github.com/bridgecrewio/checkov/issues/3847
  #checkov:skip=CKV_AWS_19:Bug in CheckOV https://github.com/bridgecrewio/checkov/issues/3847
  source  = "schubergphilis/mcaf-s3/aws"
  version = "~> 0.11.0"

  name        = var.suppressions_s3_bucket_name
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

# S3 bucket to store Lambda artifacts
module "lambda_artifacts_bucket" {
  #checkov:skip=CKV_AWS_145:Bug in CheckOV https://github.com/bridgecrewio/checkov/issues/3847
  #checkov:skip=CKV_AWS_19:Bug in CheckOV https://github.com/bridgecrewio/checkov/issues/3847
  source  = "schubergphilis/mcaf-s3/aws"
  version = "~> 0.11.0"

  name        = var.lambda_package_s3_bucket_name
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
    sid = "S3GetObjectAccess"
    actions = [
      "s3:GetObject"
    ]
    resources = [
      "${module.suppressions_bucket.name.arn}/*"
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
  source  = "schubergphilis/mcaf-lambda/aws"
  version = "~> 1.1.0"

  name                        = var.lambda_events_suppressor.name
  create_policy               = false
  create_s3_dummy_object      = false
  description                 = "Lambda to suppress Security Hub findings in response to an EventBridge trigger"
  filename                    = module.lambda_suppressor_deployment_package.local_filename
  handler                     = "securityhub_events.lambda_handler"
  kms_key_arn                 = var.kms_key_arn
  log_retention               = 365
  memory_size                 = var.lambda_events_suppressor.memory_size
  role_arn                    = module.lambda_security_hub_suppressor_role.arn
  runtime                     = var.lambda_events_suppressor.runtime
  s3_bucket                   = var.lambda_package_s3_bucket_name
  s3_key                      = module.lambda_suppressor_deployment_package.s3_object.key
  s3_object_version           = module.lambda_suppressor_deployment_package.s3_object.version_id
  security_group_egress_rules = var.lambda_events_suppressor.security_group_egress_rules
  subnet_ids                  = var.subnet_ids
  tags                        = var.tags
  timeout                     = var.lambda_events_suppressor.timeout

  environment = {
    DYNAMODB_TABLE_NAME         = var.suppressions_s3_bucket_name
    LOG_LEVEL                   = var.lambda_events_suppressor.log_level
    POWERTOOLS_LOGGER_LOG_EVENT = "false"
    POWERTOOLS_SERVICE_NAME     = "securityhub-suppressor"
  }
}

# # Lambda to suppress Security Hub findings in response to DynamoDB stream event
# module "lambda_securityhub_streams_suppressor" {
#   #checkov:skip=CKV_AWS_272:Code signing not used for now
#   source  = "schubergphilis/mcaf-lambda/aws"
#   version = "~> 1.1.0"

#   name                        = var.lambda_s3_events_suppressor.name
#   create_policy               = false
#   create_s3_dummy_object      = false
#   description                 = "Lambda to suppress Security Hub findings in response to DynamoDB stream event"
#   filename                    = module.lambda_suppressor_deployment_package.local_filename
#   handler                     = "securityhub_streams.lambda_handler"
#   kms_key_arn                 = var.kms_key_arn
#   log_retention               = 365
#   memory_size                 = var.lambda_s3_events_suppressor.memory_size
#   role_arn                    = module.lambda_security_hub_suppressor_role.arn
#   runtime                     = var.lambda_s3_events_suppressor.runtime
#   s3_bucket                   = var.lambda_package_s3_bucket_name
#   s3_key                      = module.lambda_suppressor_deployment_package.s3_object.key
#   s3_object_version           = module.lambda_suppressor_deployment_package.s3_object.version_id
#   security_group_egress_rules = var.lambda_s3_events_suppressor.security_group_egress_rules
#   subnet_ids                  = var.subnet_ids
#   tags                        = var.tags
#   timeout                     = var.lambda_s3_events_suppressor.timeout

#   environment = {
#     DYNAMODB_TABLE_NAME         = var.dynamodb_table
#     LOG_LEVEL                   = var.lambda_s3_events_suppressor.log_level
#     POWERTOOLS_LOGGER_LOG_EVENT = "false"
#     POWERTOOLS_SERVICE_NAME     = "securityhub-suppressor"
#   }
# }

# EventBridge Rule that detect Security Hub events with compliance status as failed
resource "aws_cloudwatch_event_rule" "securityhub_events_suppressor_failed_events" {
  name        = "rule-${var.lambda_events_suppressor.name}"
  description = "EventBridge Rule that detects Security Hub events with compliance status as failed and workflow status as new or notified"

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
resource "aws_lambda_permission" "allow_eventbridge_to_invoke_suppressor_lambda" {
  count         = var.jira_integration.enabled ? 0 : 1
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_events_suppressor.name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.securityhub_events_suppressor_failed_events.arn
}

# Add Security Hub Events Lambda function as a target to the EventBridge rule
resource "aws_cloudwatch_event_target" "lambda_securityhub_events_suppressor" {
  count = var.jira_integration.enabled ? 0 : 1
  arn   = module.lambda_securityhub_events_suppressor.arn
  rule  = aws_cloudwatch_event_rule.securityhub_events_suppressor_failed_events.name
}

# # Create event source mapping between Security Hub Streams Lambda function and DynamoDB streams
# resource "aws_lambda_event_source_mapping" "lambda_securityhub_streams_mapping" {
#   event_source_arn  = aws_dynamodb_table.suppressor_dynamodb_table.stream_arn
#   function_name     = module.lambda_securityhub_streams_suppressor.name
#   starting_position = "LATEST"
# }

resource "aws_s3_bucket_notification" "suppressions_bucket" {
  bucket      = var.suppressions_bucket.name
  eventbridge = true
}

resource "aws_cloudwatch_event_rule" "s3_object_event" {
  for_each = var.eventbridge_pattern_rules_s3

  name        = "${replace(each.key, "_", "-")}-to-${local.title}-via-s3"
  description = "Event rule for ${local.title} to receive ${each.key} events from ${each.value.producer_name} via S3"

  event_pattern = jsonencode({
    "source" : ["aws.s3"],
    "detail-type" : ["Object Created"],
    "detail" : {
      "bucket" : {
        "name" : [each.value.bucket]
      }
      "object" : {
        "key" : jsondecode(each.value.key_pattern)
      }
    }
  })

  tags = local.tags
}

resource "aws_cloudwatch_event_target" "s3_object_event" {
  for_each = var.eventbridge_pattern_rules_s3
  arn      = "${module.publisher_lambda.arn}:${aws_lambda_alias.publisher.name}"
  rule     = aws_cloudwatch_event_rule.s3_object_event[each.key].name

  input_transformer {
    input_paths = {
      bucket = "$.detail.bucket.name"
      id     = "$.id"
      key    = "$.detail.object.key"
      source = "$.source"
      time   = "$.time"
    }

    input_template = "{\"bucket\":\"<bucket>\",\"id\":\"<id>\",\"key\":\"<key>\",\"source\":\"<source>\",\"time\":\"<time>\",\"event_type\":\"${each.key}\",\"producer\":\"${each.value.producer_name}\"}"
  }

  retry_policy {
    maximum_event_age_in_seconds = 60
    maximum_retry_attempts       = 0
  }
}

resource "aws_lambda_permission" "s3_object_event" {
  for_each       = aws_cloudwatch_event_rule.s3_object_event
  action         = "lambda:InvokeFunction"
  function_name  = module.publisher_lambda.name
  principal      = "events.amazonaws.com"
  qualifier      = aws_lambda_alias.publisher.name
  source_account = data.aws_caller_identity.current.account_id
  source_arn     = each.value.arn
}
