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

  dynamic "statement" {
    for_each = var.jira_integration.credentials_secretsmanager_arn != null && var.jira_integration.credentials_secretsmanager_arn != "REDACTED" ? {
      "SecretManagerAccess" = {
        actions   = ["secretsmanager:GetSecretValue"]
        resources = [var.jira_integration.credentials_secretsmanager_arn]
      }
      } : var.jira_integration.credentials_ssm_secret_arn != null && var.jira_integration.credentials_ssm_secret_arn != "REDACTED" ? {
      "SSMParameterAccess" = {
        actions   = ["ssm:GetParameter", "ssm:GetParameterHistory"]
        resources = [var.jira_integration.credentials_ssm_secret_arn]
      }
    } : {}

    content {
      sid       = statement.key
      actions   = statement.value.actions
      resources = statement.value.resources
    }
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
      values   = var.jira_integration.autoclose_enabled ? ["NOTIFIED", "RESOLVED"] : ["NOTIFIED"]
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

# Upload the zip archive to S3
resource "aws_s3_object" "jira_lambda_deployment_package" {
  count = var.jira_integration.enabled ? 1 : 0

  bucket      = module.findings_manager_bucket.id
  key         = "lambda_${var.jira_integration.lambda_settings.name}_${var.lambda_runtime}.zip"
  kms_key_id  = var.kms_key_arn
  source      = "${path.module}/files/pkg/lambda_findings-manager-jira_${var.lambda_runtime}.zip"
  source_hash = filemd5("${path.module}/files/pkg/lambda_findings-manager-jira_${var.lambda_runtime}.zip")
  tags        = var.tags
}

# Lambda function to create Jira ticket for Security Hub findings and set the workflow state to NOTIFIED
module "jira_lambda" {
  #checkov:skip=CKV_AWS_272:Code signing not used for now
  count = var.jira_integration.enabled ? 1 : 0

  source  = "schubergphilis/mcaf-lambda/aws"
  version = "~> 1.4.1"

  name                        = var.jira_integration.lambda_settings.name
  create_policy               = true
  create_s3_dummy_object      = false
  description                 = "Lambda to create jira ticket and set the Security Hub workflow status to notified"
  handler                     = "findings_manager_jira.lambda_handler"
  kms_key_arn                 = var.kms_key_arn
  layers                      = ["arn:aws:lambda:${data.aws_region.current.name}:017000801446:layer:AWSLambdaPowertoolsPythonV2:79"]
  log_retention               = 365
  memory_size                 = var.jira_integration.lambda_settings.memory_size
  policy                      = data.aws_iam_policy_document.jira_lambda_iam_role[0].json
  runtime                     = var.lambda_runtime
  s3_bucket                   = var.s3_bucket_name
  s3_key                      = aws_s3_object.jira_lambda_deployment_package[0].key
  s3_object_version           = aws_s3_object.jira_lambda_deployment_package[0].version_id
  security_group_egress_rules = var.jira_integration.security_group_egress_rules
  source_code_hash            = aws_s3_object.jira_lambda_deployment_package[0].checksum_sha256
  subnet_ids                  = var.subnet_ids
  tags                        = var.tags
  timeout                     = var.jira_integration.lambda_settings.timeout

  environment = {
    EXCLUDE_ACCOUNT_FILTER       = jsonencode(var.jira_integration.exclude_account_ids)
    INCLUDE_ACCOUNT_FILTER       = jsonencode(var.jira_integration.include_account_ids)
    JIRA_AUTOCLOSE_COMMENT       = var.jira_integration.autoclose_comment
    JIRA_AUTOCLOSE_TRANSITION    = var.jira_integration.autoclose_transition_name
    JIRA_INTERMEDIATE_TRANSITION = var.jira_integration.include_intermediate_transition != null ? var.jira_integration.include_intermediate_transition : ""
    JIRA_ISSUE_CUSTOM_FIELDS     = jsonencode(var.jira_integration.issue_custom_fields)
    JIRA_ISSUE_TYPE              = var.jira_integration.issue_type
    JIRA_PROJECT_KEY             = var.jira_integration.project_key
    JIRA_SECRET_ARN              = var.jira_integration.credentials_secretsmanager_arn != null ? var.jira_integration.credentials_secretsmanager_arn : var.jira_integration.credentials_ssm_secret_arn
    JIRA_SECRET_TYPE             = var.jira_integration.credentials_secretsmanager_arn != null ? "SECRETSMANAGER" : "SSM"
    LOG_LEVEL                    = var.jira_integration.lambda_settings.log_level
    POWERTOOLS_LOGGER_LOG_EVENT  = "false"
    POWERTOOLS_SERVICE_NAME      = "securityhub-findings-manager-jira"
  }
}
