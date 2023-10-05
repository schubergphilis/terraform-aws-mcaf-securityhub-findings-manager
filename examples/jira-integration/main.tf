provider "aws" {
  region = "eu-west-1"
}

resource "aws_kms_key" "default" {
  #checkov:skip=CKV2_AWS_64: In the example no KMS key policy is defined, we do recommend creating a custom policy.
  enable_key_rotation = true
}

resource "random_pet" "default" {
  length = 8
}

resource "aws_secretsmanager_secret" "jira_credentials" {
  #checkov:skip=CKV2_AWS_57: automatic rotation of the jira credentials is recommended.
  description = "Security Hub Findings Manager Jira Credentials Secret"
  kms_key_id  = aws_kms_key.default
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

module "security_hub_manager" {
  source = "../../"

  kms_key_arn    = aws_kms_key.default
  s3_bucket_name = "securityhub-suppressor-artifacts-${random_pet.default.id}"
  tags           = { Terraform = true }

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
}
