provider "aws" {
  region = "eu-west-1"
}

data "aws_caller_identity" "current" {}

data "aws_kms_key" "by_alias" {
  key_id = "alias/audit"
}

resource "aws_secretsmanager_secret" "jira_credentials" {
  #checkov:skip=CKV2_AWS_57: automatic rotation of the jira credentials is recommended.
  description = "Security Hub Findings Manager Jira Credentials Secret"
  kms_key_id  = data.aws_kms_key.by_alias.arn
  name        = "lambda/jira_credentials_secret"
}

// tfsec:ignore:GEN003
resource "aws_secretsmanager_secret_version" "jira_credentials" {
  secret_id = aws_secretsmanager_secret.jira_credentials.id
  secret_string = jsonencode({
    "url"     = "https://jira.mycompany.com"
    "apiuser" = "username"
    "apikey"  = "apikey"
  })
}

module "aws_securityhub_findings_manager" {
  source = "../../"

  kms_key_arn                 = data.aws_kms_key.by_alias.arn
  artifact_s3_bucket_name     = "securityhub-findings-manager-artifacts-${data.aws_caller_identity.current.account_id}"
  suppressions_s3_bucket_name = "securityhub-findings-manager-suppressions-${data.aws_caller_identity.current.account_id}"

  jira_integration = {
    enabled                = true
    credentials_secret_arn = aws_secretsmanager_secret.jira_credentials.arn
    project_key            = "PROJECT"

    security_group_egress_rules = [{
      cidr_ipv4   = "1.1.1.1/32"
      description = "Allow access from lambda_jira_security_hub to Jira"
      from_port   = 443
      ip_protocol = "tcp"
      to_port     = 443
    }]
  }

  tags = { Terraform = true }
}

resource "aws_s3_object" "index" {
  bucket       = "securityhub-findings-manager-suppressions-${data.aws_caller_identity.current.account_id}"
  key          = "suppressions.yaml"
  content_type = "application/x-yaml"
  content      = file("${path.module}/../suppressions.yaml")
  etag         = md5("${path.module}/../suppressions.yaml")

  depends_on = [module.aws_securityhub_findings_manager]
}
