locals {
  # Replace with a globally unique bucket name
  s3_bucket_name = "securityhub-findings-manager"
}

provider "aws" {
  region = "eu-west-1"
}

data "aws_caller_identity" "current" {}

module "kms" {
  source  = "schubergphilis/mcaf-kms/aws"
  version = "~> 0.3.0"

  name = "securityhub-findings-manager"

  policy = templatefile(
    "${path.module}/../kms.json",
    { account_id = data.aws_caller_identity.current.account_id }
  )
}

resource "aws_secretsmanager_secret" "jira_credentials" {
  #checkov:skip=CKV2_AWS_57: automatic rotation of the jira credentials is recommended.
  description = "Security Hub Findings Manager Jira Credentials Secret"
  kms_key_id  = module.kms.arn
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

  kms_key_arn    = module.kms.arn
  s3_bucket_name = local.s3_bucket_name

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

# It can take a long time before S3 notifications become active
# You may want to deploy this resource a few minutes after those above
resource "aws_s3_object" "rules" {
  bucket       = local.s3_bucket_name
  key          = "rules.yaml"
  content_type = "application/x-yaml"
  content      = file("${path.module}/../rules.yaml")
  source_hash  = filemd5("${path.module}/../rules.yaml")

  depends_on = [module.aws_securityhub_findings_manager]
}
