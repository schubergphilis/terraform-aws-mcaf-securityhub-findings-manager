resource "aws_sqs_queue" "servicenow_queue" {
  name              = "AwsServiceManagementConnectorForSecurityHubQueue"
  kms_master_key_id = var.kms_key_arn
}

resource "aws_sqs_queue_policy" "servicenow" {
  policy    = data.aws_iam_policy_document.servicenow_sqs_policy.json
  queue_url = aws_sqs_queue.servicenow_queue.id
}

data "aws_iam_policy_document" "servicenow_sqs_policy" {
  statement {
    actions = [
      "SQS:SendMessage"
    ]

    resources = [aws_sqs_queue.servicenow_queue.arn]

    principals {
      identifiers = ["events.amazonaws.com"]
      type        = "Service"
    }

    condition {
      test     = "ArnEquals"
      values   = [aws_cloudwatch_event_rule.securityhub.arn]
      variable = "aws:SourceArn"
    }
  }
}
