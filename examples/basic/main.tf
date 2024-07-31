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

# It can take a long time before S3 notifications become active
# You may want to deploy an empty set of suppressions before the actual ones or do a trick with yaml comments
module "aws_securityhub_findings_manager" {
  source = "../../"

  kms_key_arn           = module.kms.arn
  s3_bucket_name        = "securityhub-findings-manager-artifacts" # Replace with a globally unique bucket name
  suppressions_filepath = "${path.module}/../suppressions.yaml"

  tags = { Terraform = true }
}
