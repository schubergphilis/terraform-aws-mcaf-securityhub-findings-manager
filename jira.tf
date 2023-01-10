# IAM role to be assumed by Lambda Function
module "lambda_jira_security_hub_role" {
  count                 = var.jira_integration ? 1 : 0
  source                = "github.com/schubergphilis/terraform-aws-mcaf-role?ref=v0.3.2"
  name                  = var.lambda_jira_iam_role_name
  create_policy         = true
  postfix               = false
  principal_identifiers = ["lambda.amazonaws.com"]
  principal_type        = "Service"
  role_policy           = data.aws_iam_policy_document.lambda_jira_security_hub[0].json
  tags                  = var.tags
}

data "aws_iam_policy_document" "lambda_jira_security_hub" {
  count = var.jira_integration ? 1 : 0
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
      var.jira_secret_arn
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
resource "aws_iam_role_policy_attachment" "lambda_jira_security_hub_role_vpc_policy" {
  count      = var.jira_integration && var.subnet_ids != null ? 1 : 0
  role       = module.lambda_jira_security_hub_role[0].id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Create a Lambda zip deployment package with code and dependencies
module "lambda_jira_deployment_package" {
  count                    = var.jira_integration ? 1 : 0
  source                   = "terraform-aws-modules/lambda/aws"
  version                  = "~> 3.3.0"
  create_function          = false
  recreate_missing_package = false
  runtime                  = "python3.8"
  s3_bucket                = module.lambda_artifacts_bucket.name
  s3_object_storage_class  = "STANDARD"
  source_path              = "${path.module}/files/lambda-artifacts/securityhub-jira"
  store_on_s3              = true
}

# Lambda function to create Jira ticket for Security Hub findings and set the workflow state to NOTIFIED
module "lambda_jira_security_hub" {
  #checkov:skip=CKV_AWS_272:Code signing not used for now
  count                        = var.jira_integration ? 1 : 0
  providers                    = { aws.lambda = aws }
  source                       = "github.com/schubergphilis/terraform-aws-mcaf-lambda?ref=v0.3.3"
  name                         = var.lambda_jira_name
  create_allow_all_egress_rule = var.create_allow_all_egress_rule
  create_policy                = false
  create_s3_dummy_object       = false
  description                  = "Lambda to create jira ticket and set the Security Hub workflow status to notified"
  filename                     = module.lambda_jira_deployment_package[0].local_filename
  handler                      = "securityhub_jira.lambda_handler"
  kms_key_arn                  = var.kms_key_arn
  log_retention                = 365
  memory_size                  = 256
  role_arn                     = module.lambda_jira_security_hub_role[0].arn
  runtime                      = "python3.8"
  s3_bucket                    = var.s3_bucket_name
  s3_key                       = module.lambda_jira_deployment_package[0].s3_object.key
  s3_object_version            = module.lambda_jira_deployment_package[0].s3_object.version_id
  subnet_ids                   = var.subnet_ids
  tags                         = var.tags
  timeout                      = 60

  environment = {
    EXCLUDE_ACCOUNT_FILTER      = jsonencode(var.jira_exclude_account_filter)
    JIRA_ISSUE_TYPE             = var.jira_issue_type
    JIRA_PROJECT_KEY            = var.jira_project_key
    JIRA_SECRET_ARN             = var.jira_secret_arn
    LOG_LEVEL                   = var.lambda_log_level
    POWERTOOLS_LOGGER_LOG_EVENT = "false"
    POWERTOOLS_SERVICE_NAME     = "jira-securityhub"
  }
}
