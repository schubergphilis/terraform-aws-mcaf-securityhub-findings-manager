resource "aws_cloudwatch_log_group" "servicenow" {
  name              = "/aws/events/servicenow-integration"
  retention_in_days = var.cloudwatch_retention_days
  kms_key_id        = var.kms_key_arn
}

data "aws_iam_policy_document" "servicenow" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = [
      "${aws_cloudwatch_log_group.servicenow.arn}:*",
      "${aws_cloudwatch_log_group.servicenow.arn}:log-stream:*"
    ]

    principals {
      identifiers = ["events.amazonaws.com", "delivery.logs.amazonaws.com"]
      type        = "Service"
    }

    condition {
      test     = "ArnEquals"
      values   = [aws_cloudwatch_event_rule.securityhub.arn]
      variable = "aws:SourceArn"
    }
  }
  statement {
    actions = [
      "kms:Encrypt",
      "kms:GenerateDataKey",
    ]

    resources = [
      "${var.kms_key_arn}"
    ]

    principals {
      identifiers = ["events.amazonaws.com", "delivery.logs.amazonaws.com"]
      type        = "Service"
    }

    condition {
      test     = "ArnEquals"
      values   = [aws_cloudwatch_event_rule.securityhub.arn]
      variable = "aws:SourceArn"
    }
  }

}

resource "aws_cloudwatch_log_resource_policy" "servicenow" {
  policy_document = data.aws_iam_policy_document.servicenow.json
  policy_name     = "log-delivery-servicenow"
}
