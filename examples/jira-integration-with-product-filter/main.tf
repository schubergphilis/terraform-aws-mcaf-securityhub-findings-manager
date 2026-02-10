provider "aws" {
  region = "eu-west-1"
}

# Example: Create Jira tickets only for Security Hub findings
module "securityhub_findings_manager" {
  source = "../.."

  s3_bucket_name = "my-securityhub-findings-bucket"
  kms_key_arn    = aws_kms_key.findings_manager.arn

  jira_integration = {
    enabled               = true
    include_product_names = ["Security Hub"]

    instances = {
      "default" = {
        default_instance               = true
        project_key                    = "SEC"
        credentials_secretsmanager_arn = aws_secretsmanager_secret.jira_credentials.arn

        issue_custom_fields = {
          "customfield_10001" = "Security Team"
        }
      }
    }
  }
}

# KMS key for encryption
resource "aws_kms_key" "findings_manager" {
  description             = "KMS key for Security Hub Findings Manager"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

# Secret for Jira credentials
resource "aws_secretsmanager_secret" "jira_credentials" {
  name       = "jira-credentials"
  kms_key_id = aws_kms_key.findings_manager.id
}

# Example secret value (populate with your actual credentials)
# aws secretsmanager put-secret-value \
#   --secret-id jira-credentials \
#   --secret-string '{"jira_url":"https://your-domain.atlassian.net","jira_username":"your-email@example.com","jira_api_token":"your-api-token"}'
