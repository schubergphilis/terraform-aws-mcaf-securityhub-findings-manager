# Security Hub Findings Manager
Automated scanning and finding consolidation is a cornerstone in evaluating your security posture. 
AWS Security Hub is the native solution to perform this job in AWS. 
As with any scanning and reporting tool, the amount of findings it generates can be overwhelming at first. 
Also, you may find that some findings are not relevant or have less urgency to fix in your specific situation.

The Security Hub Findings Manager is a framework designed to automatically manage findings recorded by the AWS Security Hub service including it's [AWS service integrations](https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-internal-providers.html#internal-integrations-summary) based on a pre-defined and configurable rules list. 
At its core, the Security Hub Findings Manager aims to reduce noise and help you prioritize real security issues.

Currently, it supports:
* Suppressing findings, ensuring you can manage irrelevant or less urgent findings effectively.
* Automated ticket creation in Jira and ServiceNow for non-suppressed findings with a severity higher than a definable threshold.

> [!TIP]
> We recommend deploying this module in the Audit/Security Account of an AWS reference multi-account setup.
> This account receives events from all child accounts in an organization.
> This way, a comprehensive overview of the organization's security posture can be easily maintained.

> [!IMPORTANT] 
> This module relies extensively on the [awsfindingsmanagerlib](https://github.com/schubergphilis/awsfindingsmanagerlib/tree/main).  
> For detailed information about the suppression logic, refer to the library's [documentation](https://awsfindingsmanagerlib.readthedocs.io/en/latest/).

## Components

This is a high-level overview of the constituent components.
For a more complete overview see [Resources](#resources) and [Modules](#modules).

* A rules backend (currently only S3 is supported).
* 3 Lambda Functions:
  * Security Hub Findings Manager Events: triggered by EventBridge events for new Security Hub findings.
  * Security Hub Findings Manager Triggers: triggered by changes in the S3 backend rules list, puts suppression rules on SQS.
  * Security Hub Findings Manager Trigger Worker: triggered by suppression rules on SQS.
* Infrastructure to facilitate the Lambda functions (IAM role, EventBridge integration, S3 Trigger Notifications, SQS queue).
* (optional) Jira integration components.
* (optional) ServiceNow integration components.

## Deployment Modes

There are 3 different deployment modes for this module:

> [!IMPORTANT]
> In case of first time deploy, be mindful that there can be a delay between creating S3 triggers and those being fully functional.
> Re-create the rules object later to have rules run on your findings history in that case.

### (Default) Without Jira & ServiceNow Integration

The module deploys 2 Lambda functions:

* `securityhub-findings-manager-events`, this function is the target for the EventBridge rule `Security Hub Findings - Imported` events.
* `securityhub-findings-manager-trigger`, this function is the target to the S3 PutObject trigger.

### With Jira Integration

* This deployment method can be used by setting the value of the variable `jira_integration` to `true` (default = false).
* The module deploys an additional `Jira` lambda function along with a Step function which orchestrates these Lambda functions and Step Function as a target to the EventBridge rule.
* If the finding is not suppressed a ticket is created for findings with a normalized severity higher than a definable threshold. The workflow status in Security Hub is updated from `NEW` to `NOTIFIED`.
* You can enable auto-closing functionality by setting the value of the variable `jira_integration.autoclose_enabled` to `true` (default = false). If you do so, the function will use the ticket number saved in the finding note and transition the issue using the transition defined in `jira_integration.autoclose_transition_name` with comment defined in `jira_integration.autoclose_comment`. Following findings will be forwarded to the lambda function for automatic ticket closure: 
  * Findings with Workflow Status "RESOLVED"
  * Findings with Workflow Status "NOTIFIED" and one of the following conditions:
    * Record State is "ARCHIVED"
    * Compliance State is "PASSED" or "NOT_AVAILABLE"


Only events from Security Hub with a normalized severity level higher than a definable threshold (by default `70`) trigger the Jira integration.

[Normalized severity levels](https://docs.aws.amazon.com/securityhub/1.0/APIReference/API_Severity.html):

* 0 - INFORMATIONAL
* 1–39 - LOW
* 40–69 - MEDIUM
* 70–89 - HIGH
* 90–100 - CRITICAL

![Step Function Graph](files/step-function-artifacts/securityhub-findings-manager-orchestrator-graph.png)

### With ServiceNow Integration

[Reference design](https://aws.amazon.com/blogs/security/how-to-set-up-two-way-integration-between-aws-security-hub-and-servicenow)

* This deployment method can be used by setting the value of the variable `servicenow_integration` to `true` (default = false).
* The module will deploy all the needed resources to support integration with ServiceNow, including (but not limited to): An SQS Queue, EventBridge Rule and the needed IAM user.
* When an event in Security Hub fires, an event will be created by EventBridge and dropped onto an SQS Queue.
* With the variable `severity_label_filter` it can be configured which findings will be forwarded based on the severity label.
* ServiceNow will pull the events from the SQS queue with the `SCSyncUser` using `acccess_key` & `secret_access_key`.

> [!WARNING]
> The user will be created by the module, but the `acccess_key` & `secret_access_key` need to be generated in the AWS Console, to prevent storing this data in the Terraform state.
> If you want Terraform to create the `acccess_key` & `secret_access_key` (and output them), set variable `create_servicenow_access_keys` to `true` (default = false)

## How to format the `rules.yaml` file?

An example file is stored in this module under `examples/rules.yaml`. For more detailed information check out the Rule Syntax section in the [awsfindingsmanagerlib](https://awsfindingsmanagerlib.readthedocs.io/en/latest/#rule-syntax) documentation.

## Local development on the Python code

Since a lambda layer is used to provide the aws-lambda-powertools if you want to have the same dependencies available locally then install them using `requirements-dev.txt` stored with the source code.


<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3.0 |
| <a name="requirement_archive"></a> [archive](#requirement\_archive) | >= 2.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 4.9 |
| <a name="requirement_external"></a> [external](#requirement\_external) | >= 2.0 |
| <a name="requirement_local"></a> [local](#requirement\_local) | >= 1.0 |
| <a name="requirement_null"></a> [null](#requirement\_null) | >= 2.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 4.9 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_findings_manager_bucket"></a> [findings\_manager\_bucket](#module\_findings\_manager\_bucket) | schubergphilis/mcaf-s3/aws | ~> 0.14.1 |
| <a name="module_findings_manager_events_lambda"></a> [findings\_manager\_events\_lambda](#module\_findings\_manager\_events\_lambda) | schubergphilis/mcaf-lambda/aws | ~> 1.4.1 |
| <a name="module_findings_manager_trigger_lambda"></a> [findings\_manager\_trigger\_lambda](#module\_findings\_manager\_trigger\_lambda) | schubergphilis/mcaf-lambda/aws | ~> 1.4.1 |
| <a name="module_findings_manager_worker_lambda"></a> [findings\_manager\_worker\_lambda](#module\_findings\_manager\_worker\_lambda) | schubergphilis/mcaf-lambda/aws | ~> 1.4.1 |
| <a name="module_jira_eventbridge_iam_role"></a> [jira\_eventbridge\_iam\_role](#module\_jira\_eventbridge\_iam\_role) | schubergphilis/mcaf-role/aws | ~> 0.3.2 |
| <a name="module_jira_lambda"></a> [jira\_lambda](#module\_jira\_lambda) | schubergphilis/mcaf-lambda/aws | ~> 1.4.1 |
| <a name="module_jira_step_function_iam_role"></a> [jira\_step\_function\_iam\_role](#module\_jira\_step\_function\_iam\_role) | schubergphilis/mcaf-role/aws | ~> 0.3.2 |
| <a name="module_servicenow_integration"></a> [servicenow\_integration](#module\_servicenow\_integration) | ./modules/servicenow/ | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_event_rule.securityhub_findings_events](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule) | resource |
| [aws_cloudwatch_event_target.findings_manager_events_lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) | resource |
| [aws_cloudwatch_event_target.jira_orchestrator](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) | resource |
| [aws_cloudwatch_log_group.log_group_jira_orchestrator_sfn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_lambda_event_source_mapping.sqs_to_worker](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_event_source_mapping) | resource |
| [aws_lambda_permission.eventbridge_invoke_findings_manager_events_lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission) | resource |
| [aws_lambda_permission.s3_invoke_findings_manager_trigger_lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission) | resource |
| [aws_s3_bucket_notification.findings_manager_trigger](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_notification) | resource |
| [aws_s3_object.findings_manager_lambdas_deployment_package](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object) | resource |
| [aws_s3_object.jira_lambda_deployment_package](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object) | resource |
| [aws_s3_object.rules](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object) | resource |
| [aws_sfn_state_machine.jira_orchestrator](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sfn_state_machine) | resource |
| [aws_sqs_queue.dlq_for_findings_manager_rule_q](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_sqs_queue.findings_manager_rule_q](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_sqs_queue_policy.findings_manager_rule_sqs_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue_policy) | resource |
| [aws_sqs_queue_redrive_allow_policy.dead_letter_allow_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue_redrive_allow_policy) | resource |
| [aws_sqs_queue_redrive_policy.redrive_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue_redrive_policy) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.findings_manager_lambda_iam_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.findings_manager_rule_sqs_policy_doc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.jira_eventbridge_iam_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.jira_lambda_iam_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.jira_step_function_iam_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | The ARN of the KMS key used to encrypt the resources | `string` | n/a | yes |
| <a name="input_s3_bucket_name"></a> [s3\_bucket\_name](#input\_s3\_bucket\_name) | The name for the S3 bucket which will be created for storing the function's deployment package | `string` | n/a | yes |
| <a name="input_findings_manager_events_lambda"></a> [findings\_manager\_events\_lambda](#input\_findings\_manager\_events\_lambda) | Findings Manager Lambda settings - Manage Security Hub findings in response to EventBridge events | <pre>object({<br/>    name        = optional(string, "securityhub-findings-manager-events")<br/>    log_level   = optional(string, "ERROR")<br/>    memory_size = optional(number, 256)<br/>    timeout     = optional(number, 300)<br/><br/>    security_group_egress_rules = optional(list(object({<br/>      cidr_ipv4                    = optional(string)<br/>      cidr_ipv6                    = optional(string)<br/>      description                  = string<br/>      from_port                    = optional(number, 0)<br/>      ip_protocol                  = optional(string, "-1")<br/>      prefix_list_id               = optional(string)<br/>      referenced_security_group_id = optional(string)<br/>      to_port                      = optional(number, 0)<br/>    })), [])<br/>  })</pre> | `{}` | no |
| <a name="input_findings_manager_trigger_lambda"></a> [findings\_manager\_trigger\_lambda](#input\_findings\_manager\_trigger\_lambda) | Findings Manager Lambda settings - Manage Security Hub findings in response to S3 file upload triggers | <pre>object({<br/>    name        = optional(string, "securityhub-findings-manager-trigger")<br/>    log_level   = optional(string, "ERROR")<br/>    memory_size = optional(number, 256)<br/>    timeout     = optional(number, 300)<br/><br/>    security_group_egress_rules = optional(list(object({<br/>      cidr_ipv4                    = optional(string)<br/>      cidr_ipv6                    = optional(string)<br/>      description                  = string<br/>      from_port                    = optional(number, 0)<br/>      ip_protocol                  = optional(string, "-1")<br/>      prefix_list_id               = optional(string)<br/>      referenced_security_group_id = optional(string)<br/>      to_port                      = optional(number, 0)<br/>    })), [])<br/>  })</pre> | `{}` | no |
| <a name="input_findings_manager_worker_lambda"></a> [findings\_manager\_worker\_lambda](#input\_findings\_manager\_worker\_lambda) | Findings Manager Lambda settings - Manage Security Hub findings in response to SQS trigger | <pre>object({<br/>    name        = optional(string, "securityhub-findings-manager-worker")<br/>    log_level   = optional(string, "ERROR")<br/>    memory_size = optional(number, 256)<br/>    timeout     = optional(number, 900)<br/><br/>    security_group_egress_rules = optional(list(object({<br/>      cidr_ipv4                    = optional(string)<br/>      cidr_ipv6                    = optional(string)<br/>      description                  = string<br/>      from_port                    = optional(number, 0)<br/>      ip_protocol                  = optional(string, "-1")<br/>      prefix_list_id               = optional(string)<br/>      referenced_security_group_id = optional(string)<br/>      to_port                      = optional(number, 0)<br/>    })), [])<br/>  })</pre> | `{}` | no |
| <a name="input_jira_eventbridge_iam_role_name"></a> [jira\_eventbridge\_iam\_role\_name](#input\_jira\_eventbridge\_iam\_role\_name) | The name of the role which will be assumed by EventBridge rules for Jira integration | `string` | `"SecurityHubFindingsManagerJiraEventBridge"` | no |
| <a name="input_jira_integration"></a> [jira\_integration](#input\_jira\_integration) | Findings Manager - Jira integration settings | <pre>object({<br/>    enabled                               = optional(bool, false)<br/>    autoclose_enabled                     = optional(bool, false)<br/>    autoclose_comment                     = optional(string, "Security Hub finding has been resolved. Autoclosing the issue.")<br/>    autoclose_transition_name             = optional(string, "Close Issue")<br/>    credentials_secret_arn                = string<br/>    exclude_account_ids                   = optional(list(string), [])<br/>    finding_severity_normalized_threshold = optional(number, 70)<br/>    issue_custom_fields                   = optional(map(string), {})<br/>    issue_type                            = optional(string, "Security Advisory")<br/>    project_key                           = string<br/><br/>    security_group_egress_rules = optional(list(object({<br/>      cidr_ipv4                    = optional(string)<br/>      cidr_ipv6                    = optional(string)<br/>      description                  = string<br/>      from_port                    = optional(number, 0)<br/>      ip_protocol                  = optional(string, "-1")<br/>      prefix_list_id               = optional(string)<br/>      referenced_security_group_id = optional(string)<br/>      to_port                      = optional(number, 0)<br/>    })), [])<br/><br/>    lambda_settings = optional(object({<br/>      name        = optional(string, "securityhub-findings-manager-jira")<br/>      log_level   = optional(string, "INFO")<br/>      memory_size = optional(number, 256)<br/>      timeout     = optional(number, 60)<br/>      }), {<br/>      name                        = "securityhub-findings-manager-jira"<br/>      iam_role_name               = "SecurityHubFindingsManagerJiraLambda"<br/>      log_level                   = "INFO"<br/>      memory_size                 = 256<br/>      timeout                     = 60<br/>      security_group_egress_rules = []<br/>    })<br/><br/>    step_function_settings = optional(object({<br/>      log_level = optional(string, "ERROR")<br/>      retention = optional(number, 90)<br/>      }), {<br/>      log_level = "ERROR"<br/>      retention = 90<br/>    })<br/><br/>  })</pre> | <pre>{<br/>  "credentials_secret_arn": null,<br/>  "enabled": false,<br/>  "project_key": null<br/>}</pre> | no |
| <a name="input_jira_step_function_iam_role_name"></a> [jira\_step\_function\_iam\_role\_name](#input\_jira\_step\_function\_iam\_role\_name) | The name of the role which will be assumed by AWS Step Function for Jira integration | `string` | `"SecurityHubFindingsManagerJiraStepFunction"` | no |
| <a name="input_lambda_runtime"></a> [lambda\_runtime](#input\_lambda\_runtime) | The version of Python to use for the Lambda functions | `string` | `"python3.12"` | no |
| <a name="input_rules_filepath"></a> [rules\_filepath](#input\_rules\_filepath) | Pathname to the file that stores the manager rules | `string` | `""` | no |
| <a name="input_rules_s3_object_name"></a> [rules\_s3\_object\_name](#input\_rules\_s3\_object\_name) | The S3 object containing the rules to be applied to Security Hub findings manager | `string` | `"rules.yaml"` | no |
| <a name="input_servicenow_integration"></a> [servicenow\_integration](#input\_servicenow\_integration) | ServiceNow integration settings | <pre>object({<br/>    enabled                   = optional(bool, false)<br/>    create_access_keys        = optional(bool, false)<br/>    cloudwatch_retention_days = optional(number, 365)<br/>    severity_label_filter     = optional(list(string), [])<br/>  })</pre> | <pre>{<br/>  "enabled": false<br/>}</pre> | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | The subnet ids where the Lambda functions needs to run | `list(string)` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A mapping of tags to assign to the resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_findings_manager_events_lambda_sg_id"></a> [findings\_manager\_events\_lambda\_sg\_id](#output\_findings\_manager\_events\_lambda\_sg\_id) | This will output the security group id attached to the lambda\_findings\_manager\_events Lambda. This can be used to tune ingress and egress rules. |
| <a name="output_findings_manager_trigger_lambda_sg_id"></a> [findings\_manager\_trigger\_lambda\_sg\_id](#output\_findings\_manager\_trigger\_lambda\_sg\_id) | This will output the security group id attached to the lambda\_findings\_manager\_trigger Lambda. This can be used to tune ingress and egress rules. |
| <a name="output_findings_manager_worker_lambda_sg_id"></a> [findings\_manager\_worker\_lambda\_sg\_id](#output\_findings\_manager\_worker\_lambda\_sg\_id) | This will output the security group id attached to the lambda\_findings\_manager\_worker Lambda. This can be used to tune ingress and egress rules. |
| <a name="output_jira_lambda_sg_id"></a> [jira\_lambda\_sg\_id](#output\_jira\_lambda\_sg\_id) | This will output the security group id attached to the jira\_lambda Lambda. This can be used to tune ingress and egress rules. |
<!-- END_TF_DOCS -->
