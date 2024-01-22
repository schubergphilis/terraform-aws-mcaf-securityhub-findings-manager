# Security Hub Findings Manager

> Previously called: Security Hub Findings Suppressor |
> Based on: <https://github.com/schubergphilis/aws-security-hub-suppressor>

The Security Hub Findings Manager is a framework designed to automatically suppress findings recorded by the AWS Security Hub service based on a pre-defined and configurable suppression list. This suppression is needed in case some controls or rules are not completely applicable to the resources of a given account. For example, you might want to suppress all DynamoDB Autoscaling configuration findings related to the control `DynamoDB.1`, simply because this feature is not applicable for your workload. Besides the suppression of findings this module is also able to create Jira tickets for all `NEW` findings with a severity higher than a definable threshold.

This logic is intended to be executed in the Audit Account which is part of the AWS Control Tower default account posture and therefore receives events from all child accounts in an organization.

> **Note**
> The Security Hub Findings Manager does not support consolidated control findings. You have to turn this off if you want to use this module.
> If you manage this setting via code, set the control findings generator to `STANDARD_CONTROL`.

## Terraform Runtime Requirements

* The lambda's are built and zipped during runtime, this means that the terraform runners/agents needs to have python 3.8 installed.
* Remark about Terraform Cloud: The `remote` runners from Terraform Cloud have python installed. If you run your own agents make sure that you use a custom TFC agent image with python installed.

## Components

* DynamoDB Table, referenced as `suppression list`
* 3 Lambda Functions:
  * Security Hub Events: triggered by EventBridge on events from SecurityHub.
  * Security Hub Streams: triggered by changes in the DynamoDB suppression table using a DynamoDB Stream.
  * (optional) Security Hub Jira: triggered by EventBridge on events from SecurityHub with a normalized severity higher than a definable threshold (by default `70`)
    * [Normalized](https://docs.aws.amazon.com/securityhub/1.0/APIReference/API_Severity.html) severity levels:
      * 0 - INFORMATIONAL
      * 1–39 - LOW
      * 40–69 - MEDIUM
      * 70–89 - HIGH
      * 90–100 - CRITICAL
* (optional) Step Function, to orchestrate the Suppressor and Jira lambdas.
* YML Configuration File (`suppressor.yaml`) that contains the list of products and the field mapping

## Deployment Modes

There are 3 different deployment modes for this module. All the modes deploy a Lambda function which triggers in response to upserts in DynamoDB table and a EventBridge rule with a pattern which detects the import of a new Security Hub finding. In addition to these, additional resources are deployed depending on the chosen deployment mode.

### (Default) Without Jira & ServiceNow Integration

* The module deploys 1 Lambda function: `Suppressor` and configures this Lambda as a target to the EventBridge rule.

### With Jira Integration

* This deployment method can be used by setting the value of the variable `jira_integration` to `true` (default = false).
* The module deploys two Lambda functions: `Suppressor` and `Jira` along with a Step function which orchestrates these Lambda functions and Step Function as a target to the EventBridge rule.
* If the finding is not suppressed a ticket is created for findings with a normalized severity higher than a definable threshold. The workflow status in Security Hub is updated from `NEW` to `NOTIFIED`.

![Step Function Graph](files/step-function-artifacts/securityhub-suppressor-orchestrator-graph.png)

### With ServiceNow Integration

[Reference design](https://aws.amazon.com/blogs/security/how-to-set-up-two-way-integration-between-aws-security-hub-and-servicenow)

* This deployment method can be used by setting the value of the variable `servicenow_integration` to `true` (default = false).
* The module will deploy all the needed resources to support integration with ServiceNow, including (but not limited to): An SQS Queue, EventBridge Rule and the needed IAM user.
* When an event in SecurityHub fires, an event will be created by EventBridge and dropped onto an SQS Queue.
* ServiceNow will pull the events from the SQS queue with the `SCSyncUser` using `acccess_key` & `secret_access_key`.

Note : The user will be created by the module, but the `acccess_key` & `secret_access_key` need to be generated in the AWS Console, to prevent storing this data in the Terraform state. If you want Terraform to create the `acccess_key` & `secret_access_key` (and output them), set variable `create_servicenow_access_keys` to `true` (default = false)

## How it works

The Security Hub Findings Suppressor listens to AWS EventBridge event bus and triggers an execution when a `Security Hub Findings - Imported` event happens.

Once the event is delivered, the function `securityhub-events-suppressor` will be triggered and will perform the following steps:

* Parse the event to determine what is the linked product. For example: Firewall Manager, Inspector or Security Hub.
* Check whether this product is properly mapped and configured in the YAML configuration file.
* Extract the AWS resource from the event payload.
* Upon having the resource and its ARN, the logic checks if that resource is listed in the suppression list.
* The suppression list contains a collection of items, one per controlId.

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

### Examples

Suppress a finding where the resource is the account, i.e. the 'MFA should be enabled for all IAM users that have a console password' finding:

```yaml
Suppressions:
  "1.13":
    - action: SUPPRESSED
      rules:
        - ^AWS::::Account:[0-9]{12}$
      notes: A note about this suppression
```

Suppress a finding for all resources in a specific account:

```yaml
Suppressions:
  "EC2.17":
    - action: SUPPRESSED
      rules:
        - ^arn:aws:[^:]*:[^:]*:111111111111:.*$
      notes: A note about this suppression
```

Suppress a finding in some accounts (with comments):

```yaml
Suppressions:
  EC2.17:
    - action: SUPPRESSED
      rules:
        - ^arn:aws:ec2:eu-west-1:111111111111:instance/i-[0-9a-z]+$ # can add comments here like
        - ^arn:aws:ec2:eu-west-1:222222222222:instance/i-[0-9a-z]+$ # the friendly IAM alias to more
        - ^arn:aws:ec2:eu-west-1:333333333333:instance/i-[0-9a-z]+$ # easily identify matches resources
      notes: A note about this suppression
```

Suppress finding for specific resources:

```yaml
   EC2.18:
     - action: SUPPRESSED
       rules:
         - ^arn:aws:ec2:eu-west-1:111111111111:security-group/sg-0ae8d23e1d28b1437$
         - ^arn:aws:ec2:eu-west-1:222222222222:security-group/sg-01f1aa5f8407c98b9$
       notes: A note about this suppression
```

> **Note**
> There is also a leading `^` and trailing `$` as the rule is always matched as a regexp. This means that if you do not
> start with a `^` and end with a `$` it will be matched as a substring and you might match more than anticipated.

# Usage

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3.0 |
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
| <a name="module_lambda_artifacts_bucket"></a> [lambda\_artifacts\_bucket](#module\_lambda\_artifacts\_bucket) | schubergphilis/mcaf-s3/aws | ~> 0.11.0 |
| <a name="module_lambda_jira_deployment_package"></a> [lambda\_jira\_deployment\_package](#module\_lambda\_jira\_deployment\_package) | terraform-aws-modules/lambda/aws | ~> 3.3.0 |
| <a name="module_lambda_jira_security_hub"></a> [lambda\_jira\_security\_hub](#module\_lambda\_jira\_security\_hub) | schubergphilis/mcaf-lambda/aws | ~> 1.1.0 |
| <a name="module_lambda_jira_security_hub_role"></a> [lambda\_jira\_security\_hub\_role](#module\_lambda\_jira\_security\_hub\_role) | github.com/schubergphilis/terraform-aws-mcaf-role | v0.3.2 |
| <a name="module_lambda_security_hub_suppressor_role"></a> [lambda\_security\_hub\_suppressor\_role](#module\_lambda\_security\_hub\_suppressor\_role) | github.com/schubergphilis/terraform-aws-mcaf-role | v0.3.2 |
| <a name="module_lambda_securityhub_events_suppressor"></a> [lambda\_securityhub\_events\_suppressor](#module\_lambda\_securityhub\_events\_suppressor) | schubergphilis/mcaf-lambda/aws | ~> 1.1.0 |
| <a name="module_lambda_securityhub_streams_suppressor"></a> [lambda\_securityhub\_streams\_suppressor](#module\_lambda\_securityhub\_streams\_suppressor) | schubergphilis/mcaf-lambda/aws | ~> 1.1.0 |
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
| <a name="input_deletion_protection_enabled"></a> [deletion\_protection\_enabled](#input\_deletion\_protection\_enabled) | The DynamoDB table deletion protection option. | `bool` | `false` | no |
| <a name="input_dynamodb_table"></a> [dynamodb\_table](#input\_dynamodb\_table) | The DynamoDB table containing the items to be suppressed in Security Hub | `string` | `"securityhub-suppression-list"` | no |
| <a name="input_eventbridge_suppressor_iam_role_name"></a> [eventbridge\_suppressor\_iam\_role\_name](#input\_eventbridge\_suppressor\_iam\_role\_name) | The name of the role which will be assumed by EventBridge rules | `string` | `"EventBridgeSecurityHubSuppressorRole"` | no |
| <a name="input_jira_integration"></a> [jira\_integration](#input\_jira\_integration) | Jira integration settings | <pre>object({<br>    enabled                               = optional(bool, false)<br>    credentials_secret_arn                = string<br>    exclude_account_ids                   = optional(list(string), [])<br>    finding_severity_normalized_threshold = optional(number, 70)<br>    issue_type                            = optional(string, "Security Advisory")<br>    project_key                           = string<br><br>    security_group_egress_rules = optional(list(object({<br>      cidr_ipv4                    = optional(string)<br>      cidr_ipv6                    = optional(string)<br>      description                  = string<br>      from_port                    = optional(number, 0)<br>      ip_protocol                  = optional(string, "-1")<br>      prefix_list_id               = optional(string)<br>      referenced_security_group_id = optional(string)<br>      to_port                      = optional(number, 0)<br>    })), [])<br><br>    lambda_settings = optional(object({<br>      name          = optional(string, "securityhub-jira")<br>      iam_role_name = optional(string, "LambdaJiraSecurityHubRole")<br>      log_level     = optional(string, "INFO")<br>      memory_size   = optional(number, 256)<br>      runtime       = optional(string, "python3.8")<br>      timeout       = optional(number, 60)<br>      }), {<br>      name                        = "securityhub-jira"<br>      iam_role_name               = "LambdaJiraSecurityHubRole"<br>      log_level                   = "INFO"<br>      memory_size                 = 256<br>      runtime                     = "python3.8"<br>      timeout                     = 60<br>      security_group_egress_rules = []<br>    })<br>  })</pre> | <pre>{<br>  "credentials_secret_arn": null,<br>  "enabled": false,<br>  "project_key": null<br>}</pre> | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | The ARN of the KMS key used to encrypt the resources | `string` | n/a | yes |
| <a name="input_lambda_events_suppressor"></a> [lambda\_events\_suppressor](#input\_lambda\_events\_suppressor) | Lambda Events Suppressor settings - Supresses the Security Hub findings in response to EventBridge Trigger | <pre>object({<br>    name        = optional(string, "securityhub-events-suppressor")<br>    log_level   = optional(string, "INFO")<br>    memory_size = optional(number, 256)<br>    runtime     = optional(string, "python3.8")<br>    timeout     = optional(number, 120)<br><br>    security_group_egress_rules = optional(list(object({<br>      cidr_ipv4                    = optional(string)<br>      cidr_ipv6                    = optional(string)<br>      description                  = string<br>      from_port                    = optional(number, 0)<br>      ip_protocol                  = optional(string, "-1")<br>      prefix_list_id               = optional(string)<br>      referenced_security_group_id = optional(string)<br>      to_port                      = optional(number, 0)<br>    })), [])<br>  })</pre> | `{}` | no |
| <a name="input_lambda_streams_suppressor"></a> [lambda\_streams\_suppressor](#input\_lambda\_streams\_suppressor) | Lambda Streams Suppressor settings - Supresses the Security Hub findings in response to DynamoDB streams | <pre>object({<br>    name        = optional(string, "securityhub-streams-suppressor")<br>    log_level   = optional(string, "INFO")<br>    memory_size = optional(number, 256)<br>    runtime     = optional(string, "python3.8")<br>    timeout     = optional(number, 120)<br><br>    security_group_egress_rules = optional(list(object({<br>      cidr_ipv4                    = optional(string)<br>      cidr_ipv6                    = optional(string)<br>      description                  = string<br>      from_port                    = optional(number, 0)<br>      ip_protocol                  = optional(string, "-1")<br>      prefix_list_id               = optional(string)<br>      referenced_security_group_id = optional(string)<br>      to_port                      = optional(number, 0)<br>    })), [])<br>  })</pre> | `{}` | no |
| <a name="input_lambda_suppressor_iam_role_name"></a> [lambda\_suppressor\_iam\_role\_name](#input\_lambda\_suppressor\_iam\_role\_name) | The name of the role which will be assumed by both Suppressor Lambda functions | `string` | `"LambdaSecurityHubSuppressorRole"` | no |
| <a name="input_s3_bucket_name"></a> [s3\_bucket\_name](#input\_s3\_bucket\_name) | The name for the S3 bucket which will be created for storing the function's deployment package | `string` | n/a | yes |
| <a name="input_servicenow_integration"></a> [servicenow\_integration](#input\_servicenow\_integration) | ServiceNow integration settings | <pre>object({<br>    enabled                   = optional(bool, false)<br>    create_access_keys        = optional(bool, false)<br>    cloudwatch_retention_days = optional(number, 365)<br>  })</pre> | <pre>{<br>  "enabled": false<br>}</pre> | no |
| <a name="input_step_function_suppressor_iam_role_name"></a> [step\_function\_suppressor\_iam\_role\_name](#input\_step\_function\_suppressor\_iam\_role\_name) | The name of the role which will be assumed by Suppressor Step function | `string` | `"StepFunctionSecurityHubSuppressorRole"` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | The subnet ids where the lambda's needs to run | `list(string)` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A mapping of tags to assign to the resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_dynamodb_arn"></a> [dynamodb\_arn](#output\_dynamodb\_arn) | ARN of the DynamoDB table |
| <a name="output_lambda_jira_security_hub_sg_id"></a> [lambda\_jira\_security\_hub\_sg\_id](#output\_lambda\_jira\_security\_hub\_sg\_id) | This will output the security group id attached to the jira\_security\_hub Lambda. This can be used to tune ingress and egress rules. |
| <a name="output_lambda_securityhub_events_suppressor_sg_id"></a> [lambda\_securityhub\_events\_suppressor\_sg\_id](#output\_lambda\_securityhub\_events\_suppressor\_sg\_id) | This will output the security group id attached to the securityhub\_events\_suppressor Lambda. This can be used to tune ingress and egress rules. |
| <a name="output_lambda_securityhub_streams_suppressor_sg_id"></a> [lambda\_securityhub\_streams\_suppressor\_sg\_id](#output\_lambda\_securityhub\_streams\_suppressor\_sg\_id) | This will output the security group id attached to the securityhub\_streams\_suppressor Lambda. This can be used to tune ingress and egress rules. |
<!-- END_TF_DOCS -->
