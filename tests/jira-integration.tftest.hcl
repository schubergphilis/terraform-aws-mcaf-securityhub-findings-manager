mock_provider "aws" {
  override_data {
    target = data.aws_region.current
    values = {
      name = "eu-west-1"
    }
  }

  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/fake-role-for-tests"
    }
  }

  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::aws:policy/fake-policy"
    }
  }

  mock_resource "aws_cloudwatch_event_rule" {
    defaults = {
      arn = "arn:aws:events:eu-west-1:123456789012:rule/fake-rule-for-tests"
    }
  }

  mock_resource "aws_sqs_queue" {
    defaults = {
      arn = "arn:aws:sqs:eu-west-1:123456789012:fake-queue"
      url = "https://sqs.eu-west-1.amazonaws.com/123456789012/fake-queue"
    }
  }

  mock_resource "aws_sfn_state_machine" {
    defaults = {
      arn = "arn:aws:states:eu-west-1:123456789012:stateMachine:fake-state-machine"
    }
  }
}

override_module {
  target = module.findings_manager_bucket
  outputs = {
    id   = "securityhub-findings-manager-artifacts"
    name = "securityhub-findings-manager-artifacts"
    arn  = "arn:aws:s3:::securityhub-findings-manager-artifacts"
  }
}

override_module {
  target = module.findings_manager_events_lambda
  outputs = {
    name = "securityhub-findings-manager-events"
    arn  = "arn:aws:lambda:eu-west-1:123456789012:function:securityhub-findings-manager-events"
  }
}

override_module {
  target = module.findings_manager_trigger_lambda
  outputs = {
    name = "securityhub-findings-manager-trigger"
    arn  = "arn:aws:lambda:eu-west-1:123456789012:function:securityhub-findings-manager-trigger"
  }
}

override_module {
  target = module.findings_manager_worker_lambda
  outputs = {
    name = "securityhub-findings-manager-worker"
    arn  = "arn:aws:lambda:eu-west-1:123456789012:function:securityhub-findings-manager-worker"
  }
}

override_module {
  target = module.jira_lambda[0]
  outputs = {
    name = "securityhub-findings-manager-jira"
    arn  = "arn:aws:lambda:eu-west-1:123456789012:function:securityhub-findings-manager-jira"
  }
}

override_module {
  target = module.jira_step_function_iam_role[0]
  outputs = {
    arn = "arn:aws:iam::123456789012:role/SecurityHubFindingsManagerJiraStepFunction"
  }
}

override_module {
  target = module.jira_eventbridge_iam_role[0]
  outputs = {
    arn = "arn:aws:iam::123456789012:role/SecurityHubFindingsManagerJiraEventBridge"
  }
}

run "setup_tests" {
  module {
    source = "./tests/setup"
  }
}

run "jira_integration_disabled" {
  command = plan

  variables {
    kms_key_arn    = "arn:aws:kms:eu-west-1:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    s3_bucket_name = "securityhub-findings-manager-jira"
    rules_filepath = "examples/rules.yaml"

    jira_integration = {
      enabled   = false
      instances = {}
    }
  }

  assert {
    condition     = var.jira_integration.enabled == false
    error_message = "Expected Jira integration to be disabled"
  }

  assert {
    condition     = length(module.jira_lambda) == 0
    error_message = "Expected no Jira lambda when integration is disabled"
  }
}

run "jira_integration_single_instance" {
  command = plan

  variables {
    kms_key_arn    = "arn:aws:kms:eu-west-1:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    s3_bucket_name = "securityhub-findings-manager-jira"
    rules_filepath = "examples/rules.yaml"

    jira_integration = {
      enabled                               = true
      finding_severity_normalized_threshold = 70

      instances = {
        prod = {
          include_account_ids            = ["123456789000"]
          project_key                    = "SEC"
          credentials_secretsmanager_arn = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:jira-creds"
        }
      }

      security_group_egress_rules = [{
        cidr_ipv4   = "0.0.0.0/0"
        description = "Allow all outbound traffic"
      }]
    }
  }

  assert {
    condition     = var.jira_integration.enabled == true
    error_message = "Expected Jira integration to be enabled"
  }

  assert {
    condition     = length(var.jira_integration.instances) == 1
    error_message = "Expected 1 Jira instance to be configured"
  }

  assert {
    condition     = length(module.jira_lambda) == 1
    error_message = "Expected 1 Jira lambda when integration is enabled"
  }

  assert {
    condition     = length(aws_sfn_state_machine.jira_orchestrator) == 1
    error_message = "Expected 1 Step Function state machine for Jira"
  }

  assert {
    condition     = length(aws_cloudwatch_event_target.jira_orchestrator) == 1
    error_message = "Expected 1 EventBridge target for Jira orchestrator"
  }

  assert {
    condition     = length(aws_cloudwatch_event_target.jira_orchestrator_resolved) == 0
    error_message = "Expected no EventBridge target for resolved findings when autoclose is disabled"
  }
}

run "jira_integration_multiple_instances" {
  command = plan

  variables {
    kms_key_arn    = "arn:aws:kms:eu-west-1:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    s3_bucket_name = "securityhub-findings-manager-jira-multi"
    rules_filepath = "examples/rules.yaml"

    jira_integration = {
      enabled                               = true
      finding_severity_normalized_threshold = 70

      instances = {
        prod = {
          include_account_ids            = ["123456789000"]
          project_key                    = "SEC"
          credentials_secretsmanager_arn = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:jira-prod-creds"
        }
        dev = {
          include_account_ids            = ["123456789001"]
          project_key                    = "DEV"
          credentials_secretsmanager_arn = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:jira-dev-creds"
        }
      }

      security_group_egress_rules = [{
        cidr_ipv4   = "0.0.0.0/0"
        description = "Allow all outbound traffic"
      }]
    }
  }

  assert {
    condition     = length(var.jira_integration.instances) == 2
    error_message = "Expected 2 Jira instances to be configured"
  }

  assert {
    condition     = length(module.jira_lambda) == 1
    error_message = "Expected 1 shared Jira lambda for all instances"
  }

  assert {
    condition     = length(aws_sfn_state_machine.jira_orchestrator) == 1
    error_message = "Expected 1 Step Function state machine for Jira"
  }
}

run "jira_integration_with_autoclose" {
  command = plan

  variables {
    kms_key_arn    = "arn:aws:kms:eu-west-1:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    s3_bucket_name = "securityhub-findings-manager-jira-autoclose"
    rules_filepath = "examples/rules.yaml"

    jira_integration = {
      enabled                               = true
      autoclose_enabled                     = true
      autoclose_comment                     = "Security Hub finding resolved. Auto-closing ticket."
      autoclose_transition_name             = "Done"
      finding_severity_normalized_threshold = 80

      instances = {
        prod = {
          include_account_ids            = ["123456789000"]
          project_key                    = "SEC"
          credentials_secretsmanager_arn = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:jira-creds"
        }
      }

      security_group_egress_rules = [{
        cidr_ipv4   = "0.0.0.0/0"
        description = "Allow all outbound traffic"
      }]
    }
  }

  assert {
    condition     = var.jira_integration.autoclose_enabled == true
    error_message = "Expected Jira autoclose to be enabled"
  }

  assert {
    condition     = var.jira_integration.finding_severity_normalized_threshold == 80
    error_message = "Expected severity threshold to be 80"
  }

  assert {
    condition     = length(aws_cloudwatch_event_target.jira_orchestrator_resolved) == 1
    error_message = "Expected 1 EventBridge target for resolved findings when autoclose is enabled"
  }

  assert {
    condition     = length(aws_cloudwatch_event_rule.securityhub_findings_resolved_events) == 1
    error_message = "Expected 1 EventBridge rule for resolved findings when autoclose is enabled"
  }
}

run "jira_integration_with_product_filter" {
  command = plan

  variables {
    kms_key_arn    = "arn:aws:kms:eu-west-1:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    s3_bucket_name = "securityhub-findings-manager-jira-filter"
    rules_filepath = "examples/rules.yaml"

    jira_integration = {
      enabled                               = true
      finding_severity_normalized_threshold = 70
      include_product_names                 = ["Security Hub", "GuardDuty"]

      instances = {
        prod = {
          include_account_ids            = ["123456789000"]
          project_key                    = "SEC"
          credentials_secretsmanager_arn = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:jira-creds"
        }
      }

      security_group_egress_rules = [{
        cidr_ipv4   = "0.0.0.0/0"
        description = "Allow all outbound traffic"
      }]
    }
  }

  assert {
    condition     = length(var.jira_integration.include_product_names) == 2
    error_message = "Expected 2 product names to be included in filter"
  }

  assert {
    condition     = contains(var.jira_integration.include_product_names, "Security Hub")
    error_message = "Expected Security Hub to be in product filter"
  }

  assert {
    condition     = contains(var.jira_integration.include_product_names, "GuardDuty")
    error_message = "Expected GuardDuty to be in product filter"
  }
}
