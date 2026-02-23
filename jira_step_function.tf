locals {
  sfn_jira_orchestrator_name = "securityhub-findings-manager-orchestrator"

  # Compute aggregate filters from all enabled instances
  enabled_instances = local.jira_integration_enabled ? {
    for k, v in var.jira_integration.instances : k => v if v.enabled != false
  } : {}

  # Union of all include_product_names from all enabled instances.
  # If ANY instance has an empty list (accept all products), the aggregate must be empty
  # so the Step Function doesn't filter out products that instance should receive.
  aggregate_include_product_names = local.jira_integration_enabled ? (
    anytrue([for instance in values(local.enabled_instances) : length(instance.include_product_names) == 0])
    ? []
    : distinct(flatten([for instance in values(local.enabled_instances) : instance.include_product_names]))
  ) : []

  # Minimum threshold across all enabled instances (most permissive)
  aggregate_finding_severity_threshold = local.jira_integration_enabled && length(local.enabled_instances) > 0 ? min([
    for instance in values(local.enabled_instances) :
    instance.finding_severity_normalized_threshold
  ]...) : 70
}

# IAM role to be assumed by Step Function
module "jira_step_function_iam_role" {
  count = local.jira_integration_enabled ? 1 : 0

  source  = "schubergphilis/mcaf-role/aws"
  version = "~> 0.3.2"

  name                  = var.jira_step_function_iam_role_name
  create_policy         = true
  principal_identifiers = ["states.amazonaws.com"]
  principal_type        = "Service"
  role_policy           = data.aws_iam_policy_document.jira_step_function_iam_role[0].json
  tags                  = var.tags
}

data "aws_iam_policy_document" "jira_step_function_iam_role" {
  count = local.jira_integration_enabled ? 1 : 0

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

  statement {
    sid = "CloudWatchLogDeliveryResourcePolicyAccess"
    actions = [
      "logs:CreateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:DescribeLogGroups",
      "logs:DescribeResourcePolicies",
      "logs:GetLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutResourcePolicy",
      "logs:UpdateLogDelivery"
    ]
    resources = [
      "*"
    ]
  }

  statement {
    sid = "TrustEventsToStoreLogEvent"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
    ]
  }
}

resource "aws_cloudwatch_log_group" "log_group_jira_orchestrator_sfn" {
  #checkov:skip=CKV_AWS_338:Ensure CloudWatch log groups retains logs for at least 1 year
  count = local.jira_integration_enabled ? 1 : 0

  name              = "/aws/sfn/${local.sfn_jira_orchestrator_name}"
  retention_in_days = var.jira_integration.step_function_settings.retention
  kms_key_id        = var.kms_key_arn
}

# Step Function to orchestrate findings manager lambda functions
resource "aws_sfn_state_machine" "jira_orchestrator" {
  #checkov:skip=CKV_AWS_284:x-ray is not enabled due to the simplicity of this state machine and the costs involved with enabling this feature.
  #checkov:skip=CKV_AWS_285:logging configuration is only supported for SFN type 'EXPRESS'.
  count = local.jira_integration_enabled ? 1 : 0

  name     = local.sfn_jira_orchestrator_name
  role_arn = module.jira_step_function_iam_role[0].arn
  tags     = var.tags

  definition = templatefile("${path.module}/files/step-function-artifacts/${local.sfn_jira_orchestrator_name}.json.tpl", {
    finding_severity_normalized       = local.aggregate_finding_severity_threshold
    findings_manager_events_lambda    = module.findings_manager_events_lambda.arn
    jira_autoclose_enabled            = var.jira_integration.autoclose_enabled
    jira_autoclose_suppressed_enabled = var.jira_integration.autoclose_suppressed_findings
    jira_lambda                       = module.jira_lambda[0].arn
    include_product_names             = local.aggregate_include_product_names
  })

  logging_configuration {
    include_execution_data = true
    level                  = var.jira_integration.step_function_settings.log_level
    log_destination        = "${aws_cloudwatch_log_group.log_group_jira_orchestrator_sfn[0].arn}:*"
  }
}

# IAM role to be assumed by EventBridge
module "jira_eventbridge_iam_role" {
  count = local.jira_integration_enabled ? 1 : 0

  source  = "schubergphilis/mcaf-role/aws"
  version = "~> 0.3.2"

  name                  = var.jira_eventbridge_iam_role_name
  create_policy         = true
  principal_identifiers = ["events.amazonaws.com"]
  principal_type        = "Service"
  role_policy           = data.aws_iam_policy_document.jira_eventbridge_iam_role[0].json
  tags                  = var.tags
}

data "aws_iam_policy_document" "jira_eventbridge_iam_role" {
  count = local.jira_integration_enabled ? 1 : 0

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
  count = local.jira_integration_enabled ? 1 : 0

  arn      = aws_sfn_state_machine.jira_orchestrator[0].arn
  role_arn = module.jira_eventbridge_iam_role[0].arn
  rule     = aws_cloudwatch_event_rule.securityhub_findings_events.name
}

resource "aws_cloudwatch_event_target" "jira_orchestrator_resolved" {
  count = local.jira_integration_enabled && try(var.jira_integration.autoclose_enabled, false) ? 1 : 0

  arn      = aws_sfn_state_machine.jira_orchestrator[0].arn
  role_arn = module.jira_eventbridge_iam_role[0].arn
  rule     = aws_cloudwatch_event_rule.securityhub_findings_resolved_events[0].name
}
