resource "aws_iam_user" "sync-user" {
  name = "SCSyncUser"
}

resource "aws_iam_user" "end-user" {
  name = "SCEndUser"
}

resource "aws_iam_access_key" "sync-user" {
  count = var.create_access_keys ? 1 : 0
  user  = aws_iam_user.sync-user.name
}

resource "aws_iam_access_key" "end-user" {
  count = var.create_access_keys ? 1 : 0
  user  = aws_iam_user.end-user.name
}


//Create custom policies
resource "aws_iam_policy" "ConfigBiDirectionalPolicy" {
  name        = "ConfigBiDirectionalPolicy"
  description = "Ensures bidirectional communication"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "cloudformation:RegisterType",
          "cloudformation:DescribeTypeRegistration",
          "cloudformation:DeregisterType",
          "config:PutResourceConfig"
        ]
        Effect   = "Allow"
        Resource = "*"
        Sid      = "ConfigBiDirectionalPolicySID"
      }
    ]
  })
}

resource "aws_iam_policy" "SecurityHubPolicy" {
  name        = "SecurityHubPolicy"
  description = "SecurityHubPolicy"
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
        Resource = "${aws_sqs_queue.servicenow-queue.arn}"
        Sid      = "SecurityHubPolicySID"
      }
    ]
  })
}

resource "aws_iam_policy" "SSMActionPolicy" {
  name        = "SSMActionPolicy"
  description = "SSMActionPolicy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "securityhub:BatchUpdateFindings"
        ]
        Effect   = "Allow"
        Resource = "*"
        Sid      = "SSMActionPolicy"
      }
    ]
  })
}

resource "aws_iam_policy" "SSMExecutionPolicy" {
  name        = "SSMExecutionPolicy"
  description = "SSMExecutionPolicy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ssm:DescribeAutomationExecutions",
          "ssm:DescribeDocument",
          "ssm:StartAutomationExecution"
        ]
        Effect   = "Allow"
        Resource = "*"
        Sid      = "SSMExecutionPolicy"
      }
    ]
  })
}


//Link custom policies
resource "aws_iam_user_policy_attachment" "ConfigBiDirectionalPolicy" {
  user       = aws_iam_user.sync-user.name
  policy_arn = aws_iam_policy.ConfigBiDirectionalPolicy.arn
}

resource "aws_iam_user_policy_attachment" "SecurityHubPolicy" {
  user       = aws_iam_user.sync-user.name
  policy_arn = aws_iam_policy.SecurityHubPolicy.arn
}

resource "aws_iam_user_policy_attachment" "SSMActionPolicy" {
  user       = aws_iam_user.sync-user.name
  policy_arn = aws_iam_policy.SSMActionPolicy.arn
}

resource "aws_iam_user_policy_attachment" "SSMExecutionPolicy" {
  user       = aws_iam_user.end-user.name
  policy_arn = aws_iam_policy.SSMExecutionPolicy.arn
}

//Link managed policies
resource "aws_iam_user_policy_attachment" "managed-policies" {
  for_each   = data.aws_iam_policy.ManagedPolicies
  user       = aws_iam_user.sync-user.name
  policy_arn = each.value.arn
}

resource "aws_iam_user_policy_attachment" "managed-policies-end-user" {
  for_each   = data.aws_iam_policy.ManagedPolicies
  user       = aws_iam_user.end-user.name
  policy_arn = each.value.arn
}
