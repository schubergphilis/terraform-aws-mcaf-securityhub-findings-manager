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
    enabled = true

    # Global settings (apply to ALL instances)
    autoclose_enabled                     = true
    autoclose_comment                     = "Security Hub finding has been resolved. Autoclosing the issue."
    autoclose_transition_name             = "Done"
    finding_severity_normalized_threshold = 70
    include_product_names                 = []

    # Multiple instance configurations
    instances = {
      # Team A instance - handles specific production accounts
      "team-a" = {
        enabled                        = true
        include_account_ids            = ["111111111111", "222222222222"] # Team A production accounts
        project_key                    = "TEAMA"
        credentials_secretsmanager_arn = aws_secretsmanager_secret.jira_credentials_team_a.arn
        issue_type                     = "Security Advisory"
        issue_custom_fields = {
          "customfield_10001" = "Team A"
        }
      }

      # Team B instance - handles other specific accounts using SSM credentials
      "team-b" = {
        enabled                    = true
        include_account_ids        = ["333333333333"]
        project_key                = "TEAMB"
        credentials_ssm_secret_arn = aws_ssm_parameter.jira_credentials_team_b.arn
        issue_type                 = "Bug"
        issue_custom_fields = {
          "customfield_10002" = "Team B"
        }
        include_intermediate_transition = "In Progress"
      }

      # Default instance - catches all other accounts not matched above
      "default" = {
        enabled                        = true
        default_instance               = true
        project_key                    = "DEFAULT"
        credentials_secretsmanager_arn = aws_secretsmanager_secret.jira_credentials_team_a.arn
        issue_type                     = "Task"
        # Note: include_account_ids is optional when default_instance = true
        # This instance will handle any accounts not in team-a or team-b
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
