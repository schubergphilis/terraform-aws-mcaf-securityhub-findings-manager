resource "aws_cloudwatch_event_rule" "securityhub" {
  name        = "snow-RuleLifeCycleEvents"
  description = "Send Security Hub imported findings to the AwsServiceManagementConnectorForSecurityHubQueue SQS."
  event_pattern = templatefile("${path.module}/templates/findings_filter.json.tftpl", {
  severity_label_filter = jsonencode(var.severity_label_filter) })
}

resource "aws_cloudwatch_event_target" "securityhub" {
  arn       = aws_sqs_queue.servicenow_queue.arn
  rule      = aws_cloudwatch_event_rule.securityhub.name
  target_id = "SendToSQS"
}

resource "aws_cloudwatch_event_target" "log_group_target" {
  arn  = aws_cloudwatch_log_group.servicenow.arn
  rule = aws_cloudwatch_event_rule.securityhub.name
}
