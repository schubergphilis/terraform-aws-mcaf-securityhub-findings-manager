provider "aws" {
  region = "eu-west-1"
}

resource "aws_kms_key" "default" {
  #checkov:skip=CKV2_AWS_64: In the example no KMS key policy is defined, we do recommend creating a custom policy.
  enable_key_rotation = true
}

resource "random_string" "random" {
  length  = 16
  upper   = false
  special = false
}

module "aws_securityhub_findings_manager" {
  source = "../../"

  kms_key_arn                 = aws_kms_key.default.arn
  artifact_s3_bucket_name     = "securityhub-findings-manager-artifacts-${random_string.random.result}"
  suppressions_s3_bucket_name = "securityhub-findings-manager-suppressions-${random_string.random.result}"

  servicenow_integration = {
    enabled = true
  }

  tags = { Terraform = true }
}

resource "aws_s3_object" "suppressions" {
  bucket       = "securityhub-findings-manager-suppressions-${random_string.random.result}"
  key          = "suppressions.yaml"
  content_type = "application/x-yaml"
  content      = file("${path.module}/../suppressions.yaml")
  source_hash  = filemd5("${path.module}/../suppressions.yaml")

  depends_on = [module.aws_securityhub_findings_manager]
}
