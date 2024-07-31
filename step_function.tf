# IAM role to be assumed by Step Function
module "jira_step_function_iam_role" {
  count = var.jira_integration.enabled ? 1 : 0

  source  = "schubergphilis/mcaf-role/aws"
  version = "~> 0.3.2"

  name                  = var.jira_step_function_iam_role_name
  create_policy         = true
  postfix               = false
  principal_identifiers = ["states.amazonaws.com"]
  principal_type        = "Service"
  role_policy           = data.aws_iam_policy_document.jira_step_function_iam_role[0].json
  tags                  = var.tags
}

data "aws_iam_policy_document" "jira_step_function_iam_role" {
  count = var.jira_integration.enabled ? 1 : 0

  statement {
    sid = "LambdaInvokeAccess"
    actions = [
      "lambda:InvokeFunction"
    ]
    resources = [
      module.findings_manager_events_lambda.arn,
      module.jira_lambda[0].arn
    ]
  }
}

# Step Function to orchestrate findings manager lambda functions
resource "aws_sfn_state_machine" "jira_orchestrator" {
  #checkov:skip=CKV_AWS_284:x-ray is not enabled due to the simplicity of this state machine and the costs involved with enabling this feature.
  #checkov:skip=CKV_AWS_285:logging configuration is only supported for SFN type 'EXPRESS'.
  count = var.jira_integration.enabled ? 1 : 0

  name     = "securityhub-findings-manager-orchestrator"
  role_arn = module.jira_step_function_iam_role[0].arn
  tags     = var.tags

  definition = templatefile("${path.module}/files/step-function-artifacts/securityhub-findings-manager-orchestrator.json.tpl", {
    finding_severity_normalized    = var.jira_integration.finding_severity_normalized_threshold
    findings_manager_events_lambda = module.findings_manager_events_lambda.arn,
    jira_lambda                    = module.jira_lambda[0].arn
  })
}

# IAM role to be assumed by EventBridge
module "jira_eventbridge_iam_role" {
  count = var.jira_integration.enabled ? 1 : 0

  source  = "schubergphilis/mcaf-role/aws"
  version = "~> 0.3.2"

  name                  = var.jira_eventbridge_iam_role_name
  create_policy         = true
  postfix               = false
  principal_identifiers = ["events.amazonaws.com"]
  principal_type        = "Service"
  role_policy           = data.aws_iam_policy_document.jira_eventbridge_iam_role[0].json
  tags                  = var.tags
}

data "aws_iam_policy_document" "jira_eventbridge_iam_role" {
  count = var.jira_integration.enabled ? 1 : 0

  statement {
    sid = "StepFunctionExecutionAccess"
    actions = [
      "states:StartExecution"
    ]
    resources = [
      aws_sfn_state_machine.jira_orchestrator[0].arn
    ]
  }
}

resource "aws_cloudwatch_event_target" "jira_orchestrator" {
  count = var.jira_integration.enabled ? 1 : 0

  arn      = aws_sfn_state_machine.jira_orchestrator[0].arn
  role_arn = module.jira_eventbridge_iam_role[0].arn
  rule     = aws_cloudwatch_event_rule.securityhub_findings_events.name
}
