locals {
  # Replace with a globally unique bucket name
  s3_bucket_name = "securityhub-findings-manager"
}

data "aws_caller_identity" "current" {}

provider "aws" {
  region = "eu-west-1"
}

module "kms" {
  source  = "schubergphilis/mcaf-kms/aws"
  version = "~> 0.3.0"

  name = "securityhub-findings-manager"

  policy = templatefile(
    "${path.module}/../kms.json",
    { account_id = data.aws_caller_identity.current.account_id }
  )
}

################################################################################
# Example: Multiple Jira instances routing findings based on AWS account IDs
################################################################################

# Secrets for Team A
resource "aws_secretsmanager_secret" "jira_credentials_team_a" {
  #checkov:skip=CKV2_AWS_57: automatic rotation of the jira credentials is recommended.
  description = "Security Hub Findings Manager Jira Credentials Secret - Team A"
  kms_key_id  = module.kms.arn
  name        = "lambda/securityhub_findings_manager/jira_credentials_team_a"
}

resource "aws_secretsmanager_secret_version" "jira_credentials_team_a" {
  secret_id = aws_secretsmanager_secret.jira_credentials_team_a.id
  secret_string = jsonencode({
    "url"     = "https://jira-team-a.mycompany.com"
    "apiuser" = "team-a-username"
    "apikey"  = "team-a-apikey"
  })
}

# Secrets for Team B (using SSM)
resource "aws_ssm_parameter" "jira_credentials_team_b" {
  name = "lambda/securityhub_findings_manager/jira_credentials_team_b"
  type = "SecureString"

  value = jsonencode({
    "url"     = "https://jira-team-b.mycompany.com"
    "apiuser" = "team-b-username"
    "apikey"  = "team-b-apikey"
  })

  lifecycle {
    ignore_changes = [
      value
    ]
  }
}

module "aws_securityhub_findings_manager_multi_instance" {
  source = "../../"

  kms_key_arn    = module.kms.arn
  s3_bucket_name = local.s3_bucket_name
  rules_filepath = "${path.module}/../rules.yaml"

  jira_integration = {
    enabled           = true
    autoclose_enabled = true


    # Multiple instance configurations
    instances = {
      # Team A instance - handles specific production accounts & is the default for accounts not explicitly included in other instances.
      "team-a" = {
        enabled                        = true
        credentials_secretsmanager_arn = aws_secretsmanager_secret.jira_credentials_team_a.arn
        default_instance               = true                             # Default instance for accounts not explicitly included in other instances
        include_account_ids            = ["111111111111", "222222222222"] # Team A production accounts
        project_key                    = "TEAMA"
      }

      # Team B instance - handles other specific accounts using SSM credentials
      "team-b" = {
        enabled                    = true
        credentials_ssm_secret_arn = aws_ssm_parameter.jira_credentials_team_b.arn
        include_account_ids        = ["333333333333"]
        issue_type                 = "Bug"
        project_key                = "TEAMB"
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
