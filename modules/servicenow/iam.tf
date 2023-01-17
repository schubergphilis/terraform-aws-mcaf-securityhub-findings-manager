module "sync-user" {
  #checkov:skip=CKV_AWS_273:We really need a user for this setup
  name          = "SCSyncUser"
  source        = "github.com/schubergphilis/terraform-aws-mcaf-user?ref=v0.1.13"
  create_policy = true
  policy        = aws_iam_policy.sqs_policy.policy
  policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSConfigRoleForOrganizations",
    "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess",
    "arn:aws:iam::aws:policy/AWSConfigUserAccess",
    "arn:aws:iam::aws:policy/AWSServiceCatalogAdminReadOnlyAccess"
  ]
  kms_key_id = var.kms_key_arn
  tags       = var.tags
}

//Create custom policies
resource "aws_iam_policy" "sqs_policy" {
  name        = "sqs_policy"
  description = "sqs_policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:DeleteMessageBatch"
        ]
        Effect   = "Allow"
        Resource = aws_sqs_queue.servicenow_queue.arn
        Sid      = "sqs_policy"
      }
    ]
  })
}

