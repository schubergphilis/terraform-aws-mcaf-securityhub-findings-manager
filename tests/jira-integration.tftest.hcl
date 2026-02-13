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

run "jira_disabled" {
  command = plan

  variables {
    kms_key_arn    = "arn:aws:kms:eu-west-1:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    s3_bucket_name = "securityhub-findings-manager-jira"
    rules_filepath = "examples/rules.yaml"

    jira_integration = null
  }

  assert {
    condition     = length(module.jira_lambda) == 0
    error_message = "Jira lambda should not be created when disabled"
  }
}

run "jira_enabled" {
  command = plan

  variables {
    kms_key_arn    = "arn:aws:kms:eu-west-1:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    s3_bucket_name = "securityhub-findings-manager-jira"
    rules_filepath = "examples/rules.yaml"

    jira_integration = {
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
    condition     = length(module.jira_lambda) == 1
    error_message = "Jira lambda should be created when enabled"
  }

  assert {
    condition     = length(aws_sfn_state_machine.jira_orchestrator) == 1
    error_message = "Step Function should be created"
  }

  assert {
    condition     = length(aws_cloudwatch_event_target.jira_orchestrator) == 1
    error_message = "EventBridge target should be created"
  }

  assert {
    condition     = length(aws_cloudwatch_event_target.jira_orchestrator_resolved) == 0
    error_message = "Resolved findings target should not exist when autoclose is disabled"
  }
}

run "jira_multiple_instances" {
  command = plan

  variables {
    kms_key_arn    = "arn:aws:kms:eu-west-1:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    s3_bucket_name = "securityhub-findings-manager-jira-multi"
    rules_filepath = "examples/rules.yaml"

    jira_integration = {
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
    condition     = length(module.jira_lambda) == 1
    error_message = "Jira lambda should be created when enabled"
  }

  assert {
    condition     = length(aws_sfn_state_machine.jira_orchestrator) == 1
    error_message = "Step Function should be created"
  }
}

run "jira_autoclose" {
  command = plan

  variables {
    kms_key_arn    = "arn:aws:kms:eu-west-1:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    s3_bucket_name = "securityhub-findings-manager-jira-autoclose"
    rules_filepath = "examples/rules.yaml"

    jira_integration = {
      autoclose_enabled         = true
      autoclose_comment         = "Auto-closing ticket"
      autoclose_transition_name = "Done"

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
    condition     = length(aws_cloudwatch_event_target.jira_orchestrator_resolved) == 1
    error_message = "Resolved findings target should be created when autoclose is enabled"
  }

  assert {
    condition     = length(aws_cloudwatch_event_rule.securityhub_findings_resolved_events) == 1
    error_message = "Resolved findings rule should be created when autoclose is enabled"
  }
}
