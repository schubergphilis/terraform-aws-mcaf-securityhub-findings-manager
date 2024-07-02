provider "aws" {
  region = "eu-west-1"
}

data "aws_caller_identity" "current" {}

resource "aws_kms_key" "default" {
  #checkov:skip=CKV2_AWS_64: In the example no KMS key policy is defined, we do recommend creating a custom policy.
  enable_key_rotation = true
  policy = <<EOF
{
  "Version" : "2012-10-17",
  "Id" : "key-default-1",
  "Statement" : [ {
      "Sid" : "Enable IAM User Permissions",
      "Effect" : "Allow",
      "Principal" : {
        "AWS" : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      },
      "Action" : "kms:*",
      "Resource" : "*"
    },
    {
      "Effect": "Allow",
      "Principal": { "Service": "logs.${var.region}.amazonaws.com" },
      "Action": [ 
        "kms:Encrypt*",
        "kms:Decrypt*",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:Describe*"
      ],
      "Resource": "*"
    }  
  ]
}
EOF
}

resource "random_string" "random" {
  length  = 16
  upper   = false
  special = false
}

module "security_hub_manager" {
  source = "../../"

  kms_key_arn    = aws_kms_key.default.arn
  s3_bucket_name = "securityhub-suppressor-artifacts-${random_string.random.result}"
  tags           = { Terraform = true }
}
