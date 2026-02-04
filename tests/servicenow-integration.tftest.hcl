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

override_module {
  target = module.servicenow_integration[0]
  outputs = {
    sqs_queue_arn = "arn:aws:sqs:eu-west-1:123456789012:servicenow-queue"
    sqs_queue_url = "https://sqs.eu-west-1.amazonaws.com/123456789012/servicenow-queue"
  }
}

run "setup_tests" {
  module {
    source = "./tests/setup"
  }
}

run "servicenow_integration_disabled" {
  command = plan

  variables {
    kms_key_arn    = "arn:aws:kms:eu-west-1:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    s3_bucket_name = "securityhub-findings-manager-servicenow"
    rules_filepath = "examples/rules.yaml"

    servicenow_integration = {
      enabled = false
    }
  }

  assert {
    condition     = var.servicenow_integration.enabled == false
    error_message = "Expected ServiceNow integration to be disabled"
  }

  assert {
    condition     = length(module.servicenow_integration) == 0
    error_message = "Expected no ServiceNow module when integration is disabled"
  }
}

run "servicenow_integration_enabled" {
  command = plan

  variables {
    kms_key_arn    = "arn:aws:kms:eu-west-1:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    s3_bucket_name = "securityhub-findings-manager-servicenow"
    rules_filepath = "examples/rules.yaml"

    servicenow_integration = {
      enabled = true
    }
  }

  assert {
    condition     = var.servicenow_integration.enabled == true
    error_message = "Expected ServiceNow integration to be enabled"
  }

  assert {
    condition     = length(module.servicenow_integration) == 1
    error_message = "Expected ServiceNow module to be created"
  }
}

run "servicenow_integration_with_access_keys" {
  command = plan

  variables {
    kms_key_arn    = "arn:aws:kms:eu-west-1:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    s3_bucket_name = "securityhub-findings-manager-servicenow-keys"
    rules_filepath = "examples/rules.yaml"

    servicenow_integration = {
      enabled            = true
      create_access_keys = true
    }
  }

  assert {
    condition     = var.servicenow_integration.enabled == true
    error_message = "Expected ServiceNow integration to be enabled"
  }

  assert {
    condition     = var.servicenow_integration.create_access_keys == true
    error_message = "Expected access keys creation to be enabled"
  }
}

run "servicenow_integration_with_custom_retention" {
  command = plan

  variables {
    kms_key_arn    = "arn:aws:kms:eu-west-1:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    s3_bucket_name = "securityhub-findings-manager-servicenow-retention"
    rules_filepath = "examples/rules.yaml"

    servicenow_integration = {
      enabled                   = true
      cloudwatch_retention_days = 90
    }
  }

  assert {
    condition     = var.servicenow_integration.cloudwatch_retention_days == 90
    error_message = "Expected CloudWatch retention to be 90 days"
  }
}

run "servicenow_integration_with_severity_filter" {
  command = plan

  variables {
    kms_key_arn    = "arn:aws:kms:eu-west-1:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    s3_bucket_name = "securityhub-findings-manager-servicenow-filter"
    rules_filepath = "examples/rules.yaml"

    servicenow_integration = {
      enabled               = true
      severity_label_filter = ["CRITICAL", "HIGH"]
    }
  }

  assert {
    condition     = length(var.servicenow_integration.severity_label_filter) == 2
    error_message = "Expected 2 severity labels in filter"
  }

  assert {
    condition     = contains(var.servicenow_integration.severity_label_filter, "CRITICAL")
    error_message = "Expected CRITICAL to be in severity filter"
  }

  assert {
    condition     = contains(var.servicenow_integration.severity_label_filter, "HIGH")
    error_message = "Expected HIGH to be in severity filter"
  }
}
