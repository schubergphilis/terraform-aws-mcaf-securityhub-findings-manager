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

module "security_hub_manager" {
  source = "../../"

  kms_key_arn    = aws_kms_key.default
  s3_bucket_name = "securityhub-suppressor-artifacts-${random_pet.default.id}"
  tags           = { Terraform = true }

  servicenow_integration = {
    enabled = true
  }
}
