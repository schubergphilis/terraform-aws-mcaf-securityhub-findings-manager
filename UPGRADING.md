# Upgrading Notes

This document captures required refactoring on your part when upgrading to a module version that contains breaking changes.

## Upgrading to v6.0.0

The Jira integration has been restructured to support multiple Jira instances. This allows routing Security Hub findings to different Jira projects based on AWS account IDs.

### Variables (v6.0.0)

The `jira_integration` variable structure has been completely redesigned:

**Old structure:**
```hcl
jira_integration = {
  enabled                               = true
  project_key                           = "PROJ"
  include_account_ids                   = ["123456789012"]
  credentials_secretsmanager_arn        = "arn:aws:secretsmanager:..."
  autoclose_enabled                     = true
  autoclose_comment                     = "Closing issue"
  autoclose_transition_name             = "Done"
  finding_severity_normalized_threshold = 70
  include_product_names                 = ["GuardDuty"]
  issue_type                            = "Security Advisory"
  issue_custom_fields                   = {}
  include_intermediate_transition       = "In Progress"
}
```

**New structure:**
```hcl
jira_integration = {
  enabled = true

  # Global settings (apply to ALL instances)
  exclude_account_ids                   = []
  autoclose_enabled                     = true
  autoclose_comment                     = "Closing issue"
  autoclose_transition_name             = "Done"
  finding_severity_normalized_threshold = 70
  include_product_names                 = ["GuardDuty"]

  # Per-instance configurations
  instances = {
    "default" = {
      enabled                         = true
      default_instance                = true  # Catches all accounts
      project_key                     = "PROJ"
      credentials_secretsmanager_arn  = "arn:aws:secretsmanager:..."
      issue_type                      = "Security Advisory"
      issue_custom_fields             = {}
      include_intermediate_transition = "In Progress"
      # Note: include_account_ids is optional when default_instance = true
    }
  }
}
```

**Migration steps:**

1. **Move to global level** (these now apply to all instances):
   - `autoclose_enabled`, `autoclose_comment`, `autoclose_transition_name`
   - `finding_severity_normalized_threshold`, `include_product_names`
   - `exclude_account_ids` (replaces the old filtering logic)

2. **Move to instance level** (wrap in `instances = { "name" = { ... } }`):
   - `project_key` (required)
   - `include_account_ids` (optional, must be mutually exclusive across instances if specified)
   - `credentials_secretsmanager_arn` or `credentials_ssm_secret_arn` (required, one per instance)
   - `issue_type`, `issue_custom_fields`, `include_intermediate_transition` (optional)

3. **New per-instance fields:**
   - `enabled` (optional, default: `true`) - Enable/disable a specific instance
   - `default_instance` (optional, default: `false`) - Use this instance as fallback for unmatched accounts
   - **Note:** If `include_account_ids` is empty or not specified, `default_instance` must be `true`

**Multiple instances example:**
```hcl
jira_integration = {
  enabled           = true
  autoclose_enabled = true

  instances = {
    "team-a" = {
      include_account_ids            = ["111111111111", "222222222222"]
      project_key                    = "TEAMA"
      credentials_secretsmanager_arn = "arn:aws:secretsmanager:...:secret:jira-team-a"
    }

    "team-b" = {
      include_account_ids        = ["333333333333"]
      project_key                = "TEAMB"
      credentials_ssm_secret_arn = "arn:aws:ssm:...:parameter/jira-team-b"
      issue_type                 = "Bug"
    }

    "default" = {
      default_instance               = true
      project_key                    = "DEFAULT"
      credentials_secretsmanager_arn = "arn:aws:secretsmanager:...:secret:jira-default"
      # Note: include_account_ids is optional when default_instance = true
      # This instance catches all accounts not matched by team-a or team-b
    }
  }
}
```

### Validation Rules (v6.0.0)

The following validation rules have been added:

- Each instance must have exactly one credential type (`credentials_secretsmanager_arn` OR `credentials_ssm_secret_arn`)
- If `include_account_ids` is empty, `default_instance` must be set to `true`
- `include_account_ids` must be mutually exclusive across all instances (no account can appear in multiple instances)
- At most one instance can have `default_instance = true`
- When `jira_integration.enabled = true`, at least one instance must be configured with `enabled = true`
- `exclude_account_ids` cannot overlap with any instance's `include_account_ids`

### Behaviour (v6.0.0)

**New functionality:**

- **Multiple Jira instances**: Route findings to different Jira projects based on AWS account ID
- **Default instance fallback**: Configure a fallback instance for accounts not explicitly mapped to any instance
- **Per-instance credentials**: Each instance can use different Jira credentials (different Jira servers or projects)
- **Mutually exclusive routing**: Each AWS account is routed to exactly one Jira instance (findings from an account always go to the same instance)

**Global filters:**

The following settings now apply to ALL Jira instances:
- `finding_severity_normalized_threshold` - Minimum severity for creating issues
- `include_product_names` - Filter findings by AWS service (e.g., GuardDuty, Inspector)
- `autoclose_enabled`, `autoclose_comment`, `autoclose_transition_name` - Autoclose behavior

**Security Hub note format:**

The Lambda now writes a new note format to Security Hub findings for backward compatibility:

**Old format:**
```json
{"jiraIssue": "KEY-123"}
```

**New format:**
```json
{
  "jiraIssue": "KEY-123",
  "jiraInstance": "team-a"
}
```

The `jiraInstance` field allows the autoclose functionality to use the correct Jira instance credentials and intermediate transition for the instance that created the ticket. This ensures that tickets are closed in the correct Jira instance even if account-to-instance mappings are reconfigured after ticket creation. For old notes without `jiraInstance`, the system falls back to the default instance if configured. Existing findings with the old note format will continue to work correctly during autoclose operations.

**Note:**

- The Step Function template and helper functions remain unchanged - no regression risk
- Lambda code changes are minimal (~60 lines added/modified) to maintain stability
- Existing Security Hub findings will continue to work with the new Lambda code

## Upgrading to v5.0.0

The following variables have been renamed:

- `jira_integration.credentials_secret_arn` -> `jira_integration.credentials_secretsmanager_arn`

## Upgrading to v4.0.0

We are introducing a new worker Lambda function and an SQS queue, enabling the Lambda to run within the 15-minute timeout, which is especially relevant for larger environments.

The following variable defaults have been modified:

- `findings_manager_events_lambda.log_level` -> default: `ERROR` (previous default: `INFO`). The logging configuration has been updated, and `ERROR` is now more logical as the default level.
- `findings_manager_trigger_lambda.log_level` -> default: `ERROR` (previous default: `INFO`). The logging configuration has been updated, and `ERROR` is now more logical as the default level.
- `findings_manager_trigger_lambda.memory_size` -> default: `256` (previous default: `1024`). With the new setup, the trigger Lambda requires less memory.
- `findings_manager_trigger_lambda.timeout` -> default: `300` (previous default: `900`).  With the new setup, the trigger Lambda completes tasks in less time.

The following variables have been introduced:

- `findings_manager_worker_lambda`

The following output has been introduced:

- `findings_manager_worker_lambda_sg_id`

Note:

- Ensure your KMS key is available for SQS access.

## Upgrading to v3.0.0

### Variables (v3.0.0)

The following variables have been removed:

- `dynamodb_table`
- `dynamodb_deletion_protection`

The following variables have been introduced:

- `rules_filepath`
- `rules_s3_object_name`

The following variables have been renamed:

- `lambda_events_suppressor` -> `findings_manager_events_lambda`
- `lambda_streams_suppressor` -> `findings_manager_trigger_lambda`
- `lambda_suppressor_iam_role_name` -> `findings_manager_lambda_iam_role_name`
- `eventbridge_suppressor_iam_role_name` -> `jira_eventbridge_iam_role_name`
- `step_function_suppressor_iam_role_name` -> `jira_step_function_iam_role_name`

A Lambda function now triggers on S3 Object Creation Trigger Events.
By default it is triggered by putting a new (version of) an object called `rules.yaml` in the bucket created by this module.
This filename can be customized with the `rules_s3_object_name` variable.

You can add the `rules.yaml` file to the bucket in any way you like after deploying this module, for instance with an `aws_s3_object` resource.
This way you can separate management of your infrastructure and security.
If this separation is not necessary in your case you also let this module directly upload the file for you by setting the `rules_filepath` variable to a filepath to your `rules.yaml` file.
In either case, be mindful that there can be a delay between creating S3 triggers and those being fully functional.
Re-create the rules object later to have rules run on your findings history in that case.

### Outputs (v3.0.0)

The following output has been removed:

- `dynamodb_arn`

The following output has been renamed:

- `lambda_jira_security_hub_sg_id` -> `jira_lambda_sg_id`
- `lambda_securityhub_events_suppressor_sg_id` -> `findings_manager_events_lambda_sg_id`
- `lambda_securityhub_streams_suppressor_sg_id` -> `findings_manager_trigger_lambda_sg_id`

### Behaviour (v3.0.0)

New functionality:

- Managing consolidated control findings is now supported
- Managing based on tags is now supported

See the README, section `## How to format the rules.yaml file?` for more information on the keys you need to use to control this.

The `rules.yaml` file needs to be written in a different syntax. The script below can be used to easily convert your current `suppressions.yml` file to the new format.

```python
import yaml

suppressions = yaml.safe_load(open('suppressions.yml'))['Suppressions']

rules = {
    'Rules': [
        {
            'note': content['notes'],
            'action': content['action'],
            'match_on': {
                'rule_or_control_id': rule_or_control_id,
                'resource_id_regexps': content['rules']
            }
        }
        for rule_or_control_id, contents in suppressions.items()
        for content in contents
    ]
}

print(yaml.dump(rules, indent=2))
```

If you do not want to rename your file from `suppressions.yml` to `rules.yaml` you can override the name using the `rules_s3_object_name` variable.

## Upgrading to v2.0.0

### Variables (v2.0.0)

The following variable has been replaced:

- `create_allow_all_egress_rule` -> `jira_integration.security_group_egress_rules`, `lambda_streams_suppressor.security_group_egress_rules`, `lambda_events_suppressor.security_group_egress_rules`

Instead of only being able to allow all egress or block all egress and having to rely on resources outside this module to create specific egress rules this is now supported natively by the module.

The following variable defaults have been modified:

- `servicenow_integration.cloudwatch_retention_days` -> default: `365` (previous hardcoded: `14`). In order to comply with AWS Security Hub control CloudWatch.16.

### Behaviour (v2.0.0)

The need to provide a `providers = { aws = aws }` argument has been removed, but is still allowed. E.g. when deploying this module in the audit account typically `providers = { aws = aws.audit }` is passed.

## Upgrading to v1.0.0

### Behaviour (v1.0.0)

- Timeouts of the suppressor lambdas have been increased to 120 seconds. The current timeout of 60 seconds is not always enough to process 100 records of findings.
- The `create_servicenow_access_keys` variable, now called `servicenow_integration.create_access_keys` was not used in the code and therefore the default behaviour was that access keys would be created. This issue has been resolved.
- The `create_allow_all_egress_rule` variable has been set to `false`.
- The `tags` variable is now optional.

### Variables (v1.0.0)

The following variables have been replaced by a new variable `jira_integration`:

- `jira_exclude_account_filter` -> `jira_integration.exclude_account_ids`
- `jira_finding_severity_normalized` -> `jira_integration.finding_severity_normalized_threshold`
- `jira_integration` -> `jira_integration.enabled`
- `jira_issue_type` -> `jira_integration.issue_type`
- `jira_project_key` -> `jira_integration.project_key`
- `jira_secret_arn` -> `jira_integration.credentials_secret_arn`
- `lambda_jira_name` -> `jira_integration.lambda_settings.name`
- `lambda_jira_iam_role_name` -> `jira_integration.lambda_settings.iam_role_name`
- Additionally you are now able to specify the `log_level`, `memory_size,` and `timeout` of the lambda.

The following variables have been replaced by a new variable `servicenow_integration`:

- `servicenow_integration` -> `servicenow_integration.enabled`
- `create_servicenow_access_keys` -> `servicenow_integration.create_access_keys`

The following variables have been replaced by a new variable `lambda_events_suppressor`:

- `lambda_events_suppressor_name` -> `lambda_events_suppressor.name`
- Additionally you are now able to specify the `log_level`, `memory_size,` and `timeout` of the lambda.

The following variables have been replaced by a new variable `lambda_streams_suppressor`:

- `lambda_streams_suppressor_name` -> `lambda_streams_suppressor.name`
- Additionally you are now able to specify the `log_level`, `memory_size,` and `timeout` of the lambda.
