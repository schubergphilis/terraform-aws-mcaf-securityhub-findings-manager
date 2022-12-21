resource "aws_sqs_queue" "servicenow-queue" {
  name = "AwsServiceManagementConnectorForSecurityHubQueue"
}

resource "aws_sqs_queue_policy" "servicenow" {
  queue_url = aws_sqs_queue.servicenow-queue.id

  policy = <<POLICY
  {
  "Version": "2008-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "events.amazonaws.com"
      },
      "Action": "SQS:SendMessage",
      "Resource": "${aws_sqs_queue.servicenow-queue.arn}",
      "Condition": {
        "ArnEquals": {
          "aws:SourceArn": "${aws_cloudwatch_event_rule.securityhub.arn}"
        }
      }
    }
  ]
}
  POLICY
}

