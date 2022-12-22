# Security Hub Findings Suppressor

> **_Repository containing terraform module to suppress specific events from security hub based on a dynamodb based configuration._**
Based on: <https://github.com/schubergphilis/aws-security-hub-suppressor>

The Security Hub Findings Suppressor is a framework designed to automatically suppress findings recorded by the AWS Security Hub service based on a pre-defined and configurable suppression list. This suppression is needed in case some controls or rules are not completely applicable to the resources of a given account. For example, you might want to suppress all DynamoDB Autoscaling configuration findings related to the control `DynamoDB.1`, simply because this feature is not applicable for your workload. Besides the suppression of findings this module is also able to create Jira tickets for all `NEW` findings with a severity higher than a definable threshold.

This logic is intended to be executed in the Audit Account which is part of the AWS Control Tower default account posture and therefore receives events from all child accounts in an organization.

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

There are two different deployment modes for this module. Both the modes deploy a Lambda function which triggers in response to upserts in DynamoDB table and a EventBridge rule with a pattern which detects the import of a new Security Hub finding. In addition to these, additional resources are deployed depending on the chosen deployment mode.

### With Jira Integration

* This deployment method can be used by setting the value of the variable `jira_integration` to `true` (default value).
* The module deploys two Lambda functions: `Suppressor` and `Jira` along with a Step function which orchestrates these Lambda functions and Step Function as a target to the EventBridge rule.
* If the finding is not suppressed a ticket is created for findings with a normalized severity higher than a definable threshold. The workflow status in Security Hub is updated from `NEW` to `NOTIFIED`.

![Step Function Graph](files/step-function-artifacts/securityhub-suppressor-orchestrator-graph.png)


### With ServiceNow Integration

* This deployment method can be used by setting the value of the variable `servicenow_integration` to `true` (default = false).
* The module will deploy all the needed resources to support integration with ServiceNow, including (but not limited to) : An SQS Queue, EventBridge Rule and the needed IAM users.
* When an event in SecurityHub fires, an event will be created by EventBridge and dropped onto an SQS Queue. 
* ServiceNow will connect with access_key & secret_access_key to the `SCSyncUser` user.

Note : The users will be created by the module, but the access_keys need to be generated in the AWS Console, so that it will not stick in Terraform State. If you want Terraform to create the access keys (and output them), set variable `create_servicenow_access_keys` to `true` (default = false)

![Step Function Graph](files/step-function-artifacts/securityhub-suppressor-orchestrator-graph.png)

### Without Jira & ServiceNow Integration

* This deployment method can be used by setting the value of the variable `jira_integration` and `servicenow_integration` to `false`.
* The module deploys 1 Lambda function: `Suppressor` and configures this Lambda as a target to the EventBridge rule.

## How it works

The Security Hub Findings Suppressor listens to AWS EventBridge event bus and triggers an execution when a `Security Hub Findings - Imported` event happens.

Once the event is delivered, the function `securityhub-events-suppressor` will be triggered and will perform the following steps:

* Parse the event to determine what is the linked product. For example: Firewall Manager, Inspector or Security Hub.
* Check whether this product is properly mapped and configured in the YAML configuration file.
* Extract the AWS resource from the event payload.
* Upon having the resource and its ARN, the logic checks if that resource is listed in the suppression list.
* The suppression list contains a collection of items, one per controlId.

## How to add a new product to the suppression list

* All resources required by The Security Hub Findings Suppressor are deployed by this module. But the module does not update the DynamoDB Table (the `suppression list`). This can be updates using a variety of methods, via GitHub actions is described below:

* In the repository calling this module, create a folder called `sechub-suppressor`, add `requirements.txt`, `put_suppressions.py`, and `suppressions.yml` to this folder. Example files are stored in this module under `files/dynamodb-upserts-artifacts`. An example GitHub action is stored in this folder as well.

* Add a new element to the `suppressions.yml` configuration file containing the product name, key and status. Key and status fields must be JMESPath expressions.
  * Fields:
    * `controlId`: the key field from the event (it is usually a Control Id or a RuleId present in the event)
      * `action`: the status that will be applied in Security Hub
      * `dry_run`: a read-only mode to preview what the logic will be handling
      * `notes`: notes added to the security hub finding. Usually it is a Jira Ticket with the exception approval
      * `rules`: a list of regular expressions to be matched against the resource ARN present in the EventBridge Event

* Commit your changes, push and merge. The pipeline will automatically maintain the set of suppressions and store them in DynamoDB. If all above steps succeed, the finding is suppressed.

# Usage
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
| dynamodb\_table | The DynamoDB table containing the items to be suppressed in Security Hub | `string` | `"securityhub-suppression-list"` | no |
| eventbridge\_suppressor\_iam\_role\_name | The name of the role which will be assumed by EventBridge rules | `string` | `"EventBridgeSecurityHubSuppressorRole"` | no |
| jira\_exclude\_account\_filter | A list of account IDs for which no issue will be created in Jira | `list(string)` | `[]` | no |
| jira\_finding\_severity\_normalized | Finding severity(in normalized form) threshold for jira ticket creation | `number` | `70` | no |
| jira\_integration | Whether to create Jira tickets for Security Hub findings. This requires the variables `jira_project_key` and `jira_secret_arn` to be set | `bool` | `true` | no |
| jira\_issue\_type | The issue type for which the Jira issue will be created | `string` | `"Security Advisory"` | no |
| jira\_project\_key | The project key the Jira issue will be created under | `string` | `null` | no |
| jira\_secret\_arn | Secret arn that stores the secrets for Jira api calls. The Secret should include url, apiuser and apikey | `string` | `null` | no |
| lambda\_events\_suppressor\_name | The Lambda which will supress the Security Hub findings in response to EventBridge Trigger | `string` | `"securityhub-events-suppressor"` | no |
| lambda\_jira\_iam\_role\_name | The name of the role which will be assumed by Jira Lambda function | `string` | `"LambdaJiraSecurityHubRole"` | no |
| lambda\_jira\_name | The Lambda which will create jira ticket and set the Security Hub workflow status to notified | `string` | `"securityhub-jira"` | no |
| lambda\_log\_level | Sets how verbose lambda Logger should be | `string` | `"INFO"` | no |
| lambda\_streams\_suppressor\_name | The Lambda which will supress the Security Hub findings in response to DynamoDB streams | `string` | `"securityhub-streams-suppressor"` | no |
| lambda\_suppressor\_iam\_role\_name | The name of the role which will be assumed by Suppressor Lambda functions | `string` | `"LambdaSecurityHubSuppressorRole"` | no |
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
