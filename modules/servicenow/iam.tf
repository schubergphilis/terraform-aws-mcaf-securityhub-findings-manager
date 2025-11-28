module "sync-user" {
  #checkov:skip=CKV_AWS_273:We really need a user for this setup
  source  = "schubergphilis/mcaf-user/aws"
  version = "1.0.0"

  create_iam_access_key = var.create_access_keys
  create_policy         = true
  kms_key_id            = var.kms_key_arn
  name                  = "SCSyncUser"
  policy                = aws_iam_policy.sqs_sechub.policy
  region                = var.region
  tags                  = var.tags

  policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSConfigRoleForOrganizations",
    "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess",
    "arn:aws:iam::aws:policy/AWSConfigUserAccess",
    "arn:aws:iam::aws:policy/AWSServiceCatalogAdminReadOnlyAccess"
  ]
}

//Create custom policies
resource "aws_iam_policy" "sqs_sechub" {
  name        = "sqs_sechub"
  description = "sqs_sechub"
  policy      = data.aws_iam_policy_document.sqs_sechub.json
}

data "aws_iam_policy_document" "sqs_sechub" {
  statement {
    sid = "SqsMessages"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:DeleteMessageBatch"
    ]
    resources = [aws_sqs_queue.servicenow_queue.arn]
  }

  statement {
    sid = "SecurityHubAccess"
    actions = [
      "securityhub:BatchUpdateFindings",
      "securityhub:GetFindings"
    ]
    resources = ["arn:aws:securityhub:${local.region}:${data.aws_caller_identity.current.account_id}:hub/default"]
  }
}
