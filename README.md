# Security Hub Findings Manager

> Previously called: Security Hub Findings Suppressor |
> Based on: <https://github.com/schubergphilis/aws-security-hub-suppressor>

Security Hub Findings Manager is a framework designed to suppress AWS Security Hub findings via a configurable suppression list.

This suppression is useful when controls or rules are not applicable in an account. For example, you might want to suppress all DynamoDB Autoscaling configuration findings related to the control `DynamoDB.1` simply because this feature is not applicable for your workload. In addition to suppressing findings, this module can also create Jira issues for all `NEW` findings that match a defined severity threshold.

This module is intended to be run against the Audit account in a Control Tower installation, which by default receives events from all child accounts in the organization.

## Terraform runtime requirements

Important to note:

* The lambdas are built and zipped during runtime, this means that Terraform needs access to Python 3.8
* Note when using Terraform Cloud: remote agents already have Python installed but the [hashicorp/tfc-agent](https://hub.docker.com/r/hashicorp/tfc-agent) image used for self-hosted agents does not. If using self-hosted agents, you will need to build your own image that includes Python 3.8.

## Components

* DynamoDB Table, referenced as `suppression list`
* 3 Lambda Functions:
  * Security Hub Events: triggered by EventBridge on events from SecurityHub.
  * Security Hub Streams: triggered by changes in the DynamoDB suppression table using a DynamoDB Stream.
  * (optional) Security Hub Jira: triggered by EventBridge on events from SecurityHub with a normalized severity higher than a definable threshold (by default `70`)
    * [Normalized](https://docs.aws.amazon.com/securityhub/1.0/APIReference/API_Severity.html) severity levels:
      * 0 - `INFORMATIONAL`
      * 1–39 - `LOW`
      * 40–69 - `MEDIUM`
      * 70–89 - `HIGH`
      * 90–100 - `CRITICAL`
* (optional) Step Function, to orchestrate the Suppressor and Jira lambdas.
* YML Configuration File (`suppressor.yaml`) that contains the list of products and the field mapping

## Deployment Modes

Each mode deploys a Lambda function that is triggered by upserts to the DynamoDB table and an EventBridge rule which detects new Security Hub findings. In addition to these, additional resources are deployed depending on the chosen deployment mode.

### (Default) Without Jira & ServiceNow Integration

* The module deploys one Lambda function: `Suppressor`, and configures it as a target to the EventBridge rule watching for new Security Hub findings

### With Jira Integration

* The module deploys an additional Lambda function: `Jira`, along with a Step function which orchestrates these Lambda functions and Step Function as a target to the EventBridge rule
* An issue is created in Jira if a new finding matches the configured severity level and does not match a suppression rule; the Security Hub workflow status will also be changed from `NEW` to `NOTIFIED`.

This functionality can be enabled by setting `var.jira_integration` to `true`.

![Step Function Graph](files/step-function-artifacts/securityhub-suppressor-orchestrator-graph.png)

### With ServiceNow Integration

[Reference design](https://aws.amazon.com/blogs/security/how-to-set-up-two-way-integration-between-aws-security-hub-and-servicenow)

* The module will deploy additional resources to support ServiceNow integration including (but not limited to): SQS queue, EventBridge rule and the necessary IAM user
* When an event in SecurityHub fires, an event will be created by EventBridge and dropped onto an SQS queue.
* ServiceNow will pull the events from the SQS queue with the `SCSyncUser` using `access_key` & `secret_access_key`.

This functionality can be enabled by setting `var.servicenow_integration` to `true`.

> **Note**
> The user will be created by the module, but the `access_key` & `secret_access_key` need to be generated in the AWS Console, to prevent storing this data in the Terraform state. If you want Terraform to create the `access_key` & `secret_access_key` (and output them), set `var.create_servicenow_access_keys` to `true`.

## How it works

The Security Hub Findings Manager listens to the AWS EventBridge event bus and triggers an execution when the ["Security Hub Findings - Imported event](https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-cwe-event-formats.html#securityhub-cwe-event-formats-findings-imported) occurs.

Once the event is delivered, the `securityhub-events-suppressor` function will perform the following:

1. Parse the event to determine what is the linked product. For example: Firewall Manager, Inspector or Security Hub.
1. Check whether this product is properly mapped and configured in the YAML configuration file.
1. Extract the AWS resource from the event payload.
1. Upon having the resource and its ARN, the logic checks if that resource is listed in the suppression list.
1. The suppression list contains a collection of items, one per controlId.

## How to add a new product to the suppression list

* All resources required by The Security Hub Findings Manager are deployed by this module. But the module does not update the DynamoDB Table (the `suppression list`). This can be updates using a variety of methods, via GitHub actions is described below:

* In the repository calling this module, create a folder called `sechub-suppressor`, add `requirements.txt`, `put_suppressions.py`, and `suppressions.yml` to this folder. Example files are stored in this module under `files/dynamodb-upserts-artifacts`. An example GitHub action is stored in this folder as well.

* Add a new element to the `suppressions.yml` configuration file containing the product name, key and status. Key and status fields must be JMESPath expressions.
  * Fields:
    * `controlId`: the key field from the event (it is usually a Control Id or a RuleId present in the event)
      * `action`: the status that will be applied in Security Hub
      * `dry_run`: a read-only mode to preview what the logic will be handling
      * `notes`: notes added to the security hub finding. Usually it is a Jira Ticket with the exception approval
      * `rules`: a list of regular expressions to be matched against the resource ARN present in the EventBridge Event

* Commit your changes, push and merge. The pipeline will automatically maintain the set of suppressions and store them in DynamoDB. If all above steps succeed, the finding is suppressed.

## Examples

Suppress a finding in all accounts:

```yaml
Suppressions:
  "1.13":
    - action: SUPPRESSED
      rules:
        - ^AWS::::Account:[0-9]{12}$
      notes: A note about this suppression
```

Suppress a finding in some accounts (with comments):

```yaml
Suppressions:
  EC2.17:
    - action: SUPPRESSED
      rules:
        - ^arn:aws:ec2:eu-west-1:111111111111:instance/i-[0-9a-z]$ # can add comments here like
        - ^arn:aws:ec2:eu-west-1:222222222222:instance/i-[0-9a-z]$ # the friendly IAM alias to more
        - ^arn:aws:ec2:eu-west-1:333333333333:instance/i-[0-9a-z]$ # easily identify matches resources
      notes: A note about this suppression
```

Suppress finding for specific resources:

```yaml
   EC2.18:
     - action: SUPPRESSED
       rules:
         - arn:aws:ec2:eu-west-1:111111111111:security-group/sg-0ae8d23e1d28b1437
         - arn:aws:ec2:eu-west-1:222222222222:security-group/sg-01f1aa5f8407c98b9
       notes: A note about this suppression
```

> **Note**
> There is no leading `^` or trailing `$` as we don't use a regex for specific resources.

## Usage

<!--- BEGIN_TF_DOCS --->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 0.14 |
| aws | >= 4.9 |
| local | >= 1.0 |
| null | >= 2.0 |

## Providers

| Name | Version |
|------|---------|
| aws | >= 4.9 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| kms\_key\_arn | The ARN of the KMS key used to encrypt the resources | `string` | n/a | yes |
| s3\_bucket\_name | The name for the S3 bucket which will be created for storing the function's deployment package | `string` | n/a | yes |
| tags | A mapping of tags to assign to the resources | `map(string)` | n/a | yes |
| create\_allow\_all\_egress\_rule | Whether to create a default any/any egress sg rule for lambda | `bool` | `true` | no |
| create\_servicenow\_access\_keys | Whether Terraform needs to create and output the access keys for the ServiceNow integration | `bool` | `false` | no |
| dynamodb\_table | The DynamoDB table containing the items to be suppressed in Security Hub | `string` | `"securityhub-suppression-list"` | no |
| eventbridge\_suppressor\_iam\_role\_name | The name of the role which will be assumed by EventBridge rules | `string` | `"EventBridgeSecurityHubSuppressorRole"` | no |
| jira\_exclude\_account\_filter | A list of account IDs for which no issue will be created in Jira | `list(string)` | `[]` | no |
| jira\_finding\_severity\_normalized | Finding severity(in normalized form) threshold for jira ticket creation | `number` | `70` | no |
| jira\_integration | Whether to create Jira tickets for Security Hub findings. This requires the variables `jira_project_key` and `jira_secret_arn` to be set | `bool` | `false` | no |
| jira\_issue\_type | The issue type for which the Jira issue will be created | `string` | `"Security Advisory"` | no |
| jira\_project\_key | The project key the Jira issue will be created under | `string` | `null` | no |
| jira\_secret\_arn | Secret arn that stores the secrets for Jira api calls. The Secret should include url, apiuser and apikey | `string` | `null` | no |
| lambda\_events\_suppressor\_name | The Lambda which will supress the Security Hub findings in response to EventBridge Trigger | `string` | `"securityhub-events-suppressor"` | no |
| lambda\_jira\_iam\_role\_name | The name of the role which will be assumed by Jira Lambda function | `string` | `"LambdaJiraSecurityHubRole"` | no |
| lambda\_jira\_name | The Lambda which will create jira ticket and set the Security Hub workflow status to notified | `string` | `"securityhub-jira"` | no |
| lambda\_log\_level | Sets how verbose lambda Logger should be | `string` | `"INFO"` | no |
| lambda\_streams\_suppressor\_name | The Lambda which will supress the Security Hub findings in response to DynamoDB streams | `string` | `"securityhub-streams-suppressor"` | no |
| lambda\_suppressor\_iam\_role\_name | The name of the role which will be assumed by Suppressor Lambda functions | `string` | `"LambdaSecurityHubSuppressorRole"` | no |
| servicenow\_integration | Whether to enable the ServiceNow integration | `bool` | `false` | no |
| step\_function\_suppressor\_iam\_role\_name | The name of the role which will be assumed by Suppressor Step function | `string` | `"StepFunctionSecurityHubSuppressorRole"` | no |
| subnet\_ids | The subnet ids where the lambda's needs to run | `list(string)` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| dynamodb\_arn | ARN of the DynamoDB table |
| lambda\_jira\_security\_hub\_sg\_id | This will output the security group id attached to the jira\_security\_hub Lambda. This can be used to tune ingress and egress rules. |
| lambda\_securityhub\_events\_suppressor\_sg\_id | This will output the security group id attached to the securityhub\_events\_suppressor Lambda. This can be used to tune ingress and egress rules. |
| lambda\_securityhub\_streams\_suppressor\_sg\_id | This will output the security group id attached to the securityhub\_streams\_suppressor Lambda. This can be used to tune ingress and egress rules. |

<!--- END_TF_DOCS --->

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 0.14 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 4.9 |
| <a name="requirement_local"></a> [local](#requirement\_local) | >= 1.0 |
| <a name="requirement_null"></a> [null](#requirement\_null) | >= 2.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 4.9 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_eventbridge_security_hub_suppressor_role"></a> [eventbridge\_security\_hub\_suppressor\_role](#module\_eventbridge\_security\_hub\_suppressor\_role) | github.com/schubergphilis/terraform-aws-mcaf-role | v0.3.2 |
| <a name="module_lambda_artifacts_bucket"></a> [lambda\_artifacts\_bucket](#module\_lambda\_artifacts\_bucket) | github.com/schubergphilis/terraform-aws-mcaf-s3 | v0.6.0 |
| <a name="module_lambda_jira_deployment_package"></a> [lambda\_jira\_deployment\_package](#module\_lambda\_jira\_deployment\_package) | terraform-aws-modules/lambda/aws | ~> 3.3.0 |
| <a name="module_lambda_jira_security_hub"></a> [lambda\_jira\_security\_hub](#module\_lambda\_jira\_security\_hub) | github.com/schubergphilis/terraform-aws-mcaf-lambda | v0.3.3 |
| <a name="module_lambda_jira_security_hub_role"></a> [lambda\_jira\_security\_hub\_role](#module\_lambda\_jira\_security\_hub\_role) | github.com/schubergphilis/terraform-aws-mcaf-role | v0.3.2 |
| <a name="module_lambda_security_hub_suppressor_role"></a> [lambda\_security\_hub\_suppressor\_role](#module\_lambda\_security\_hub\_suppressor\_role) | github.com/schubergphilis/terraform-aws-mcaf-role | v0.3.2 |
| <a name="module_lambda_securityhub_events_suppressor"></a> [lambda\_securityhub\_events\_suppressor](#module\_lambda\_securityhub\_events\_suppressor) | github.com/schubergphilis/terraform-aws-mcaf-lambda | v0.3.3 |
| <a name="module_lambda_securityhub_streams_suppressor"></a> [lambda\_securityhub\_streams\_suppressor](#module\_lambda\_securityhub\_streams\_suppressor) | github.com/schubergphilis/terraform-aws-mcaf-lambda | v0.3.3 |
| <a name="module_lambda_suppressor_deployment_package"></a> [lambda\_suppressor\_deployment\_package](#module\_lambda\_suppressor\_deployment\_package) | terraform-aws-modules/lambda/aws | ~> 3.3.0 |
| <a name="module_servicenow_integration"></a> [servicenow\_integration](#module\_servicenow\_integration) | ./modules/servicenow/ | n/a |
| <a name="module_step_function_security_hub_suppressor_role"></a> [step\_function\_security\_hub\_suppressor\_role](#module\_step\_function\_security\_hub\_suppressor\_role) | github.com/schubergphilis/terraform-aws-mcaf-role | v0.3.2 |

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_event_rule.securityhub_events_suppressor_failed_events](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule) | resource |
| [aws_cloudwatch_event_target.lambda_securityhub_events_suppressor](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) | resource |
| [aws_cloudwatch_event_target.securityhub_suppressor_orchestrator_step_function](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) | resource |
| [aws_dynamodb_table.suppressor_dynamodb_table](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table) | resource |
| [aws_iam_role_policy_attachment.lambda_jira_security_hub_role_vpc_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.lambda_security_hub_suppressor_role_vpc_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_lambda_event_source_mapping.lambda_securityhub_streams_mapping](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_event_source_mapping) | resource |
| [aws_lambda_permission.allow_eventbridge_to_invoke_suppressor_lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission) | resource |
| [aws_sfn_state_machine.securityhub_suppressor_orchestrator](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sfn_state_machine) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.eventbridge_security_hub_suppressor](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.lambda_jira_security_hub](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.lambda_security_hub_suppressor](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.step_function_security_hub_suppressor](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | The ARN of the KMS key used to encrypt the resources | `string` | n/a | yes |
| <a name="input_s3_bucket_name"></a> [s3\_bucket\_name](#input\_s3\_bucket\_name) | The name for the S3 bucket which will be created for storing the function's deployment package | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | A mapping of tags to assign to the resources | `map(string)` | n/a | yes |
| <a name="input_create_allow_all_egress_rule"></a> [create\_allow\_all\_egress\_rule](#input\_create\_allow\_all\_egress\_rule) | Whether to create a default any/any egress sg rule for lambda | `bool` | `true` | no |
| <a name="input_create_servicenow_access_keys"></a> [create\_servicenow\_access\_keys](#input\_create\_servicenow\_access\_keys) | Whether Terraform needs to create and output the access keys for the ServiceNow integration | `bool` | `false` | no |
| <a name="input_dynamodb_table"></a> [dynamodb\_table](#input\_dynamodb\_table) | The DynamoDB table containing the items to be suppressed in Security Hub | `string` | `"securityhub-suppression-list"` | no |
| <a name="input_eventbridge_suppressor_iam_role_name"></a> [eventbridge\_suppressor\_iam\_role\_name](#input\_eventbridge\_suppressor\_iam\_role\_name) | The name of the role which will be assumed by EventBridge rules | `string` | `"EventBridgeSecurityHubSuppressorRole"` | no |
| <a name="input_jira_exclude_account_filter"></a> [jira\_exclude\_account\_filter](#input\_jira\_exclude\_account\_filter) | A list of account IDs for which no issue will be created in Jira | `list(string)` | `[]` | no |
| <a name="input_jira_finding_severity_normalized"></a> [jira\_finding\_severity\_normalized](#input\_jira\_finding\_severity\_normalized) | Finding severity(in normalized form) threshold for jira ticket creation | `number` | `70` | no |
| <a name="input_jira_integration"></a> [jira\_integration](#input\_jira\_integration) | Whether to create Jira tickets for Security Hub findings. This requires the variables `jira_project_key` and `jira_secret_arn` to be set | `bool` | `false` | no |
| <a name="input_jira_issue_type"></a> [jira\_issue\_type](#input\_jira\_issue\_type) | The issue type for which the Jira issue will be created | `string` | `"Security Advisory"` | no |
| <a name="input_jira_project_key"></a> [jira\_project\_key](#input\_jira\_project\_key) | The project key the Jira issue will be created under | `string` | `null` | no |
| <a name="input_jira_secret_arn"></a> [jira\_secret\_arn](#input\_jira\_secret\_arn) | Secret arn that stores the secrets for Jira api calls. The Secret should include url, apiuser and apikey | `string` | `null` | no |
| <a name="input_lambda_events_suppressor_name"></a> [lambda\_events\_suppressor\_name](#input\_lambda\_events\_suppressor\_name) | The Lambda which will supress the Security Hub findings in response to EventBridge Trigger | `string` | `"securityhub-events-suppressor"` | no |
| <a name="input_lambda_jira_iam_role_name"></a> [lambda\_jira\_iam\_role\_name](#input\_lambda\_jira\_iam\_role\_name) | The name of the role which will be assumed by Jira Lambda function | `string` | `"LambdaJiraSecurityHubRole"` | no |
| <a name="input_lambda_jira_name"></a> [lambda\_jira\_name](#input\_lambda\_jira\_name) | The Lambda which will create jira ticket and set the Security Hub workflow status to notified | `string` | `"securityhub-jira"` | no |
| <a name="input_lambda_log_level"></a> [lambda\_log\_level](#input\_lambda\_log\_level) | Sets how verbose lambda Logger should be | `string` | `"INFO"` | no |
| <a name="input_lambda_streams_suppressor_name"></a> [lambda\_streams\_suppressor\_name](#input\_lambda\_streams\_suppressor\_name) | The Lambda which will supress the Security Hub findings in response to DynamoDB streams | `string` | `"securityhub-streams-suppressor"` | no |
| <a name="input_lambda_suppressor_iam_role_name"></a> [lambda\_suppressor\_iam\_role\_name](#input\_lambda\_suppressor\_iam\_role\_name) | The name of the role which will be assumed by Suppressor Lambda functions | `string` | `"LambdaSecurityHubSuppressorRole"` | no |
| <a name="input_servicenow_integration"></a> [servicenow\_integration](#input\_servicenow\_integration) | Whether to enable the ServiceNow integration | `bool` | `false` | no |
| <a name="input_step_function_suppressor_iam_role_name"></a> [step\_function\_suppressor\_iam\_role\_name](#input\_step\_function\_suppressor\_iam\_role\_name) | The name of the role which will be assumed by Suppressor Step function | `string` | `"StepFunctionSecurityHubSuppressorRole"` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | The subnet ids where the lambda's needs to run | `list(string)` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_dynamodb_arn"></a> [dynamodb\_arn](#output\_dynamodb\_arn) | ARN of the DynamoDB table |
| <a name="output_lambda_jira_security_hub_sg_id"></a> [lambda\_jira\_security\_hub\_sg\_id](#output\_lambda\_jira\_security\_hub\_sg\_id) | This will output the security group id attached to the jira\_security\_hub Lambda. This can be used to tune ingress and egress rules. |
| <a name="output_lambda_securityhub_events_suppressor_sg_id"></a> [lambda\_securityhub\_events\_suppressor\_sg\_id](#output\_lambda\_securityhub\_events\_suppressor\_sg\_id) | This will output the security group id attached to the securityhub\_events\_suppressor Lambda. This can be used to tune ingress and egress rules. |
| <a name="output_lambda_securityhub_streams_suppressor_sg_id"></a> [lambda\_securityhub\_streams\_suppressor\_sg\_id](#output\_lambda\_securityhub\_streams\_suppressor\_sg\_id) | This will output the security group id attached to the securityhub\_streams\_suppressor Lambda. This can be used to tune ingress and egress rules. |
<!-- END_TF_DOCS -->
