locals {
  s3_bucket_name = "securityhub-findings-manager-${random_string.suffix.result}"

  # Jira credentials for multiple teams
  jira_credentials = {
    team_a = {
      url     = "https://jira-team-a.mycompany.com"
      apiuser = "team-a-username"
      apikey  = "team-a-apikey"
    }
    team_b = {
      url     = "https://jira-team-b.mycompany.com"
      apiuser = "team-b-username"
      apikey  = "team-b-apikey"
    }
  }
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
# Example: Multiple Jira instances routing findings based on AWS account IDs
################################################################################

resource "aws_secretsmanager_secret" "jira_credentials" {
  for_each = local.jira_credentials

  #checkov:skip=CKV2_AWS_57: automatic rotation of the jira credentials is recommended.
  description = "Security Hub Findings Manager Jira Credentials Secret - ${each.key}"
  kms_key_id  = module.kms.arn
  name        = "lambda/securityhub_findings_manager/jira_credentials_${each.key}"
}

resource "aws_secretsmanager_secret_version" "jira_credentials" {
  for_each = local.jira_credentials

  secret_id = aws_secretsmanager_secret.jira_credentials[each.key].id
  secret_string = jsonencode({
    "url"     = each.value.url
    "apiuser" = each.value.apiuser
    "apikey"  = each.value.apikey
  })
}

module "aws_securityhub_findings_manager_multi_instance" {
  source = "../../"

  kms_key_arn    = module.kms.arn
  s3_bucket_name = local.s3_bucket_name
  rules_filepath = "${path.module}/../rules.yaml"

  jira_integration = {
    autoclose_enabled = true

    # Multiple instance configurations
    instances = {
      # Team A instance - handles specific production accounts & is the default for accounts not explicitly included in other instances.
      "team-a" = {
        credentials_secretsmanager_arn = aws_secretsmanager_secret.jira_credentials["team_a"].arn
        default_instance               = true                             # Default instance for accounts not explicitly included in other instances
        include_account_ids            = ["111111111111", "222222222222"] # Team A production accounts
        project_key                    = "TEAMA"
      }

      # Team B instance - handles other specific accounts
      "team-b" = {
        credentials_secretsmanager_arn = aws_secretsmanager_secret.jira_credentials["team_b"].arn
        include_account_ids            = ["333333333333"]
        project_key                    = "TEAMB"
      }
    }
  }

  tags = { Terraform = true }
}
