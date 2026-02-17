locals {
  s3_bucket_name = "securityhub-findings-manager-${random_string.suffix.result}"
}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

provider "aws" {}

data "aws_caller_identity" "current" {}

module "kms" {
  source  = "schubergphilis/mcaf-kms/aws"
  version = "~> 0.3.0"

  name   = "securityhub-findings-manager"
  policy = templatefile("${path.module}/../kms.json", { account_id = data.aws_caller_identity.current.account_id })
}

################################################################################
# Example of Jira integration with Findings Manager using Credentials from Secrets Manager
################################################################################

resource "aws_secretsmanager_secret" "jira_credentials" {
  #checkov:skip=CKV2_AWS_57: automatic rotation of the jira credentials is recommended.
  description = "Security Hub Findings Manager Jira Credentials Secret"
  kms_key_id  = module.kms.arn
  name        = "lambda/securityhub_findings_manager/jira_credentials_secret"
}

resource "aws_secretsmanager_secret_version" "jira_credentials" {
  secret_id = aws_secretsmanager_secret.jira_credentials.id
  secret_string = jsonencode({
    "url"     = "https://jira.mycompany.com"
    "apiuser" = "username"
    "apikey"  = "apikey"
  })
}

module "aws_securityhub_findings_manager_with_secretsmanager_credentials" {
  source = "../../"

  kms_key_arn    = module.kms.arn
  s3_bucket_name = local.s3_bucket_name
  rules_filepath = "${path.module}/../rules.yaml"

  jira_integration = {
    instances = {
      "default" = {
        default_instance               = true
        project_key                    = "PROJECT"
        credentials_secretsmanager_arn = aws_secretsmanager_secret.jira_credentials.arn
      }
    }

    security_group_egress_rules = [{
      cidr_ipv4   = "1.1.1.1/32"
      description = "Allow access from lambda_jira_securityhub to Jira"
      from_port   = 443
      ip_protocol = "tcp"
      to_port     = 443
    }]
  }

  tags = { Terraform = true }
}

################################################################################
# Example of Jira integration with Findings Manager using Credentials from SSM Parameter Store
################################################################################

resource "aws_ssm_parameter" "jira_credentials" {
  name = "lambda/securityhub_findings_manager/jira_credentials_secret"
  type = "SecureString"

  value = jsonencode({
    "url"     = "https://jira.mycompany.com"
    "apiuser" = "username"
    "apikey"  = "apikey"
  })

  lifecycle {
    ignore_changes = [
      value
    ]
  }
}

module "aws_securityhub_findings_manager_with_ssm_credentials" {
  source = "../../"

  kms_key_arn    = module.kms.arn
  s3_bucket_name = local.s3_bucket_name
  rules_filepath = "${path.module}/../rules.yaml"

  jira_integration = {
    enabled = true

    instances = {
      "default" = {
        default_instance           = true
        project_key                = "PROJECT"
        credentials_ssm_secret_arn = aws_ssm_parameter.jira_credentials.arn
      }
    }

    security_group_egress_rules = [{
      cidr_ipv4   = "1.1.1.1/32"
      description = "Allow access from lambda_jira_securityhub to Jira"
      from_port   = 443
      ip_protocol = "tcp"
      to_port     = 443
    }]
  }

  tags = { Terraform = true }
}
