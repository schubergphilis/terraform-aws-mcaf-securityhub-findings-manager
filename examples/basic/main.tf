provider "aws" {
  region = "eu-west-1"
}

data "aws_caller_identity" "current" {}

data "aws_kms_key" "by_alias" {
  key_id = "alias/audit"
}

module "aws_securityhub_findings_manager" {
  source = "../../"

  kms_key_arn                 = data.aws_kms_key.by_alias.arn
  artifact_s3_bucket_name     = "securityhub-findings-manager-artifacts-${data.aws_caller_identity.current.account_id}"
  suppressions_s3_bucket_name = "securityhub-findings-manager-suppressions-${data.aws_caller_identity.current.account_id}"

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
