resource "aws_cloudwatch_event_rule" "securityhub" {
  name        = "snow-RuleLifeCycleEvents"
  description = "Send Security Hub imported findings to the AwsServiceManagementConnectorForSecurityHubQueue SQS."

  event_pattern = <<EOF
{
  "detail-type": ["Security Hub Findings - Imported"],
  "source": ["aws.securityhub"]
}
EOF
}

resource "aws_cloudwatch_event_target" "securityhub" {
  rule      = aws_cloudwatch_event_rule.securityhub.name
  target_id = "SendToSQS"
  arn       = aws_sqs_queue.servicenow-queue.arn
}

resource "aws_cloudwatch_event_target" "example" {
  rule = aws_cloudwatch_event_rule.securityhub.name
  arn  = aws_cloudwatch_log_group.servicenow.arn
}
