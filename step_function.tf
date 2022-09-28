# IAM role to be assumed by Step Function
module "step_function_security_hub_suppressor_role" {
  count                 = var.jira_integration ? 1 : 0
  source                = "github.com/schubergphilis/terraform-aws-mcaf-role?ref=v0.3.2"
  name                  = var.step_function_suppressor_iam_role_name
  create_policy         = true
  postfix               = false
  principal_identifiers = ["states.amazonaws.com"]
  principal_type        = "Service"
  role_policy           = data.aws_iam_policy_document.step_function_security_hub_suppressor[0].json
  tags                  = var.tags
}

data "aws_iam_policy_document" "step_function_security_hub_suppressor" {
  count = var.jira_integration ? 1 : 0
  statement {
    sid = "LambdaInvokeAccess"
    actions = [
      "lambda:InvokeFunction"
    ]
    resources = [
      "${module.lambda_securityhub_events_suppressor.arn}",
      "${module.lambda_jira_security_hub[0].arn}"
    ]
  }
}

# Step Function to orchestrate suppressor lambda functions
resource "aws_sfn_state_machine" "securityhub_suppressor_orchestrator" {
  count    = var.jira_integration ? 1 : 0
  name     = "securityhub-suppressor-orchestrator"
  role_arn = module.step_function_security_hub_suppressor_role[0].arn
  tags     = var.tags

  definition = templatefile("${path.module}/files/step-function-artifacts/securityhub-suppressor-orchestrator.json.tpl", {
    finding_severity_normalized              = var.jira_finding_severity_normalized
    lambda_securityhub_events_suppressor_arn = module.lambda_securityhub_events_suppressor.arn,
    lambda_securityhub_jira_arn              = module.lambda_jira_security_hub[0].arn
  })
}

# IAM role to be assumed by EventBridge
module "eventbridge_security_hub_suppressor_role" {
  count                 = var.jira_integration ? 1 : 0
  source                = "github.com/schubergphilis/terraform-aws-mcaf-role?ref=v0.3.2"
  name                  = var.eventbridge_suppressor_iam_role_name
  create_policy         = true
  postfix               = false
  principal_identifiers = ["events.amazonaws.com"]
  principal_type        = "Service"
  role_policy           = data.aws_iam_policy_document.eventbridge_security_hub_suppressor[0].json
  tags                  = var.tags
}

data "aws_iam_policy_document" "eventbridge_security_hub_suppressor" {
  count = var.jira_integration ? 1 : 0
  statement {
    sid = "StepFunctionExecutionAccess"
    actions = [
      "states:StartExecution"
    ]
    resources = [
    "${aws_sfn_state_machine.securityhub_suppressor_orchestrator[0].arn}"]
  }
}

resource "aws_cloudwatch_event_target" "securityhub_suppressor_orchestrator_step_function" {
  count    = var.jira_integration ? 1 : 0
  arn      = aws_sfn_state_machine.securityhub_suppressor_orchestrator[0].arn
  role_arn = module.eventbridge_security_hub_suppressor_role[0].arn
  rule     = aws_cloudwatch_event_rule.securityhub_events_suppressor_failed_events.name
}
