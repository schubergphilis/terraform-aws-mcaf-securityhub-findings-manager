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

# It can take a long time before S3 notifications become active
# You may want to deploy an empty set of suppressions before the actual ones or do a trick with yaml comments
module "aws_securityhub_findings_manager" {
  source = "../../"

  kms_key_arn           = aws_kms_key.default.arn
  s3_bucket_name        = "securityhub-findings-manager-artifacts" # Replace with a globally unique bucket name
  suppressions_filepath = "${path.module}/../suppressions.yaml"

  tags = { Terraform = true }
}
