provider "aws" {
  region = "eu-west-1"
}

data "aws_caller_identity" "current" {}

resource "aws_kms_key" "default" {
  enable_key_rotation = true

  # Policy to make this example just work, too open for a real app
  policy = templatefile(
    "${path.module}/kms.json",
    { account_id = data.aws_caller_identity.current.account_id }
  )
}

locals {
  # Replace with a globally unique bucket name
  s3_bucket_name = "securityhub-findings-manager"
}

module "aws_securityhub_findings_manager" {
  source = "../../"

  kms_key_arn    = aws_kms_key.default.arn
  s3_bucket_name = local.s3_bucket_name

  servicenow_integration = {
    enabled = true
  }

  tags = { Terraform = true }
}

# It can take a long time before S3 notifications become active
# You may want to deploy this resource a few minutes after those above
resource "aws_s3_object" "suppressions" {
  bucket       = local.s3_bucket_name
  key          = "suppressions.yaml"
  content_type = "application/x-yaml"
  content      = file("${path.module}/../suppressions.yaml")
  source_hash  = filemd5("${path.module}/../suppressions.yaml")

  depends_on = [module.aws_securityhub_findings_manager]
}
