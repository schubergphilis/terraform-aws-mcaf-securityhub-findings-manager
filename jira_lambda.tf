# IAM role to be assumed by Lambda Function
module "jira_lambda_iam_role" {
  count = var.jira_integration.enabled ? 1 : 0

  source  = "schubergphilis/mcaf-role/aws"
  version = "~> 0.4.0"

  name                  = var.jira_integration.lambda_settings.iam_role_name
  create_policy         = true
  principal_identifiers = ["lambda.amazonaws.com"]
  principal_type        = "Service"
  role_policy           = data.aws_iam_policy_document.jira_lambda_iam_role[0].json
  tags                  = var.tags
}

data "aws_iam_policy_document" "jira_lambda_iam_role" {
  count = var.jira_integration.enabled ? 1 : 0

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
    sid = "SecretManagerAccess"
    actions = [
      "secretsmanager:GetSecretValue"
    ]
    resources = [
      var.jira_integration.credentials_secret_arn
    ]
  }

  statement {
    sid = "SecurityHubAccess"
    actions = [
      "securityhub:BatchUpdateFindings"
    ]
    resources = [
      "arn:aws:securityhub:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:hub/default"
    ]
    condition {
      test     = "ForAnyValue:StringEquals"
      variable = "securityhub:ASFFSyntaxPath/Workflow.Status"
      values = [
        "NOTIFIED"
      ]
    }
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
resource "aws_iam_role_policy_attachment" "jira_lambda_iam_role_vpc_policy_attachment" {
  count = var.jira_integration.enabled && var.subnet_ids != null ? 1 : 0

  role       = module.jira_lambda_iam_role[0].id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Create a Lambda zip deployment package with code and dependencies
module "jira_lambda_deployment_package" {
  count = var.jira_integration.enabled ? 1 : 0

  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 3.3.0"

  create_function          = false
  recreate_missing_package = false
  runtime                  = var.lambda_runtime
  s3_bucket                = module.findings_manager_bucket.name
  s3_object_storage_class  = "STANDARD"
  source_path              = "${path.module}/files/lambda-artifacts/findings-manager-jira"
  store_on_s3              = true
}

# Create a zip archive from the source_path
data "archive_file" "jira_lambda_deployment_package" {
  count = var.jira_integration.enabled ? 1 : 0

  type        = "zip"
  source_dir  = "${path.module}/files/lambda-artifacts/findings-manager-jira"
  output_path = "${path.module}/files/pkg/lambda_${var.jira_integration.lambda_settings.name}_${var.lambda_runtime}.zip"
}

# Upload the zip archive to S3
resource "aws_s3_object" "jira_lambda_deployment_package" {
  count = var.jira_integration.enabled ? 1 : 0

  bucket     = module.findings_manager_bucket.id
  key        = "lambda_${var.jira_integration.lambda_settings.name}_${var.lambda_runtime}.zip"
  kms_key_id = var.kms_key_arn
  source     = archive_file.jira_lambda_deployment_package[0].output_path
  tags       = var.tags
}

# Lambda function to create Jira ticket for Security Hub findings and set the workflow state to NOTIFIED
module "jira_lambda" {
  #checkov:skip=CKV_AWS_272:Code signing not used for now
  count = var.jira_integration.enabled ? 1 : 0

  source  = "schubergphilis/mcaf-lambda/aws"
  version = "~> 1.4.1"

  name                        = var.jira_integration.lambda_settings.name
  create_policy               = false
  create_s3_dummy_object      = false
  description                 = "Lambda to create jira ticket and set the Security Hub workflow status to notified"
  handler                     = "findings_manager_jira.lambda_handler"
  kms_key_arn                 = var.kms_key_arn
  layers                      = ["arn:aws:lambda:${data.aws_region.current.name}:017000801446:layer:AWSLambdaPowertoolsPythonV2:79"]
  log_retention               = 365
  memory_size                 = var.jira_integration.lambda_settings.memory_size
  role_arn                    = module.jira_lambda_iam_role[0].arn
  runtime                     = var.lambda_runtime
  s3_bucket                   = module.findings_manager_bucket.name
  s3_key                      = aws_s3_object.jira_lambda_deployment_package[0].key
  s3_object_version           = aws_s3_object.jira_lambda_deployment_package[0].version_id
  source_code_hash            = aws_s3_object.jira_lambda_deployment_package[0].checksum_sha256
  security_group_egress_rules = var.jira_integration.security_group_egress_rules
  subnet_ids                  = var.subnet_ids
  tags                        = var.tags
  timeout                     = var.jira_integration.lambda_settings.timeout

  environment = {
    EXCLUDE_ACCOUNT_FILTER      = jsonencode(var.jira_integration.exclude_account_ids)
    JIRA_ISSUE_TYPE             = var.jira_integration.issue_type
    JIRA_PROJECT_KEY            = var.jira_integration.project_key
    JIRA_SECRET_ARN             = var.jira_integration.credentials_secret_arn
    LOG_LEVEL                   = var.jira_integration.lambda_settings.log_level
    POWERTOOLS_LOGGER_LOG_EVENT = "false"
    POWERTOOLS_SERVICE_NAME     = "securityhub-findings-manager-jira"
  }
}
