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

run "setup_tests" {
  module {
    source = "./tests/setup"
  }
}

run "basic" {
  command = plan

  variables {
    kms_key_arn    = "arn:aws:kms:eu-west-1:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    s3_bucket_name = "securityhub-findings-manager-artifacts"
    rules_filepath = "examples/rules.yaml"
  }

  assert {
    condition     = module.findings_manager_bucket.name == "securityhub-findings-manager-artifacts"
    error_message = "Expected S3 bucket name to match"
  }

  assert {
    condition     = module.findings_manager_events_lambda.name == "securityhub-findings-manager-events"
    error_message = "Expected events lambda name to match default"
  }

  assert {
    condition     = module.findings_manager_trigger_lambda.name == "securityhub-findings-manager-trigger"
    error_message = "Expected trigger lambda name to match default"
  }

  assert {
    condition     = module.findings_manager_worker_lambda.name == "securityhub-findings-manager-worker"
    error_message = "Expected worker lambda name to match default"
  }

  assert {
    condition     = aws_cloudwatch_event_rule.securityhub_findings_events.name != ""
    error_message = "Expected EventBridge rule to be created"
  }

  assert {
    condition     = length(aws_cloudwatch_event_rule.securityhub_findings_resolved_events) == 0
    error_message = "Expected no resolved events rule when Jira integration is disabled"
  }

  assert {
    condition     = aws_sqs_queue.findings_manager_rule_q.name == "SecurityHubFindingsManagerRuleQueue"
    error_message = "Expected SQS queue to be created with correct name"
  }

  assert {
    condition     = aws_sqs_queue.dlq_for_findings_manager_rule_q.name != ""
    error_message = "Expected DLQ to be created"
  }
}

run "custom_lambda_settings" {
  command = plan

  variables {
    kms_key_arn    = "arn:aws:kms:eu-west-1:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    s3_bucket_name = "securityhub-findings-manager-custom"
    rules_filepath = "examples/rules.yaml"

    findings_manager_events_lambda = {
      name        = "custom-events-lambda"
      log_level   = "INFO"
      memory_size = 512
      timeout     = 600
    }

    findings_manager_trigger_lambda = {
      name        = "custom-trigger-lambda"
      log_level   = "DEBUG"
      memory_size = 1024
      timeout     = 120
    }

    findings_manager_worker_lambda = {
      name        = "custom-worker-lambda"
      log_level   = "WARNING"
      memory_size = 512
      timeout     = 300
    }
  }

  assert {
    condition     = var.findings_manager_events_lambda.name == "custom-events-lambda"
    error_message = "Expected events lambda name variable to be set"
  }

  assert {
    condition     = var.findings_manager_events_lambda.log_level == "INFO"
    error_message = "Expected events lambda log level to be INFO"
  }

  assert {
    condition     = var.findings_manager_trigger_lambda.name == "custom-trigger-lambda"
    error_message = "Expected trigger lambda name variable to be set"
  }

  assert {
    condition     = var.findings_manager_worker_lambda.name == "custom-worker-lambda"
    error_message = "Expected worker lambda name variable to be set"
  }
}

run "with_subnet_ids" {
  command = plan

  variables {
    kms_key_arn    = "arn:aws:kms:eu-west-1:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    s3_bucket_name = "securityhub-findings-manager-vpc"
    rules_filepath = "examples/rules.yaml"
    subnet_ids     = ["subnet-12345", "subnet-67890"]
  }

  assert {
    condition     = length(var.subnet_ids) == 2
    error_message = "Expected 2 subnet IDs to be configured"
  }
}
