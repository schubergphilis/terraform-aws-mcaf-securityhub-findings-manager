# Upgrading Notes

This document captures required refactoring on your part when upgrading to a module version that contains breaking changes.

## Upgrading to v3.0.0

### Variables

The following variables have been removed:
- `dynamodb_deletion_protection` & `dynamodb_table`

The suppressions.yaml file can now directly be pushed to an S3 bucket either by using the `suppressions_filepath` and `suppressions_s3_object_name` variable or by pusing the file via an custom `aws_s3_object` resource or via any other way. The suppressor lambda now triggers on S3 Object Creation Trigger Events.

The following variable has been renamed:
- `lambda_streams_suppressor` -> `lambda_trigger_suppressor`

### Outputs
The following output has been removed:
- `dynamodb_arn`

The following output has been renamed:
- `lambda_securityhub_streams_suppressor_sg_id` -> `lambda_securityhub_trigger_suppressor_sg_id`

### Behaviour

New functionality:
- Suppressing consolidated control findings is now supported
- Suppressing based on tags is now supported

See the README, section `## How to format the suppressions.yaml file?` for more information on the keys you need to use to control this.

The suppression.yaml file needs to be written in a different syntax. The script below can be used to easily convert your current suppressions.yaml file to the new format. 

```python
import yaml

suppressions = yaml.safe_load(open('suppressions.yaml', 'r'))

output = {
    'Rules': [{
            'note': suppression['notes'],
            'action': suppression['action'],
            'match_on': {
                'control_id': control_id,
                'resource_id': suppression['rules']
            }
        }
        for control_id, controls in suppressions['Suppressions'].items()
        for suppression in controls]
}

print(yaml.dump(output, indent=2))
```

## Upgrading to v2.0.0

### Variables

The following variable has been replaced:

- `create_allow_all_egress_rule` -> `jira_integration.security_group_egress_rules`, `lambda_streams_suppressor.security_group_egress_rules`, `lambda_events_suppressor.security_group_egress_rules`

Instead of only being able to allow all egress or block all egress and having to rely on resources outside this module to create specific egress rules this is now supported natively by the module.

The following variable defaults have been modified:

- `servicenow_integration.cloudwatch_retention_days` -> default: `365` (previous hardcoded: `14`). In order to comply with AWS Security Hub control CloudWatch.16.

### Behaviour

The need to provide a `providers = { aws = aws }` argument has been removed, but is still allowed. E.g. when deploying this module in the audit account typically `providers = { aws = aws.audit }` is passed.

## Upgrading to v1.0.0

### Behaviour

- Timeouts of the suppressor lambdas have been increased to 120 seconds. The current timeout of 60 seconds is not always enough to process 100 records of findings.
- The `create_servicenow_access_keys` variable, now called `servicenow_integration.create_access_keys` was not used in the code and therefore the default behaviour was that access keys would be created. This issue has been resolved.
- The `create_allow_all_egress_rule` variable has been set to `false`.
- The `tags` variable is now optional.

### Variables

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
