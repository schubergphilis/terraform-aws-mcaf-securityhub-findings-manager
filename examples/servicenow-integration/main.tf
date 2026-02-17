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

  name = "securityhub-findings-manager"

  policy = templatefile(
    "${path.module}/../kms.json",
    { account_id = data.aws_caller_identity.current.account_id }
  )
}

module "aws_securityhub_findings_manager" {
  source = "../../"

  kms_key_arn    = module.kms.arn
  s3_bucket_name = local.s3_bucket_name

  servicenow_integration = {
    enabled = true
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
