# Security Hub Findings Manager

> Previously called: Security Hub Findings Suppressor |
> Based on: <https://github.com/schubergphilis/aws-security-hub-suppressor>

Security Hub Findings Manager is a framework designed to suppress AWS Security Hub using a configurable suppression list.

This suppression is useful when controls or rules are not applicable in an account. For example, you might want to suppress all DynamoDB Autoscaling configuration findings related to the control `DynamoDB.1` simply because this feature is not applicable for your workload. Besides the suppressing the findings, this module is also able to create Jira tickets for all `NEW` findings with a severity higher than the defined threshold.

This module is intended to be run against the Audit account in a Control Tower installtion, which by default receives events from all child accounts in the organisation.

## Terraform runtime requirements

Important to note:

* The lambdas are built and zipped during runtime, this means that Terraform needs access to Python 3.8
* Re Terraform Cloud: The "remote" runners from do have Python installed; if you are using self-hosted agents, you'll need to create your own image based that includes Python

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

## Deployment moded

Each mode deploys a Lambda function that is triggered by upserts to the DynamoDB table and an EventBridge rule which detects new Security Hub findings. In addition to these, additional resources are deployed depending on the chosen deployment mode.

### (Default) without Jira & ServiceNow integration

* The module deploys one Lambda function: `Suppressor`, and configures it as a target to the EventBridge rule watching for new Security Hub findings

### With Jira integration

* The module deploys an additional Lambda function: `Jira`, along with a Step function which orchestrates these Lambda functions and Step Function as a target to the EventBridge rule
* If the finding is not suppressed and matches the configured severity level, an issue is created in Jira; the Security Hub workflow status will also be changed from `NEW` to `NOTIFIED`

![Step Function Graph](files/step-function-artifacts/securityhub-suppressor-orchestrator-graph.png)

### With ServiceNow integration

[Reference design](https://aws.amazon.com/blogs/security/how-to-set-up-two-way-integration-between-aws-security-hub-and-servicenow)

* The module will deploy additional resources to support ServiceNow integration including (but not limited to): SQS queue, EventBridge rule and the necessary IAM user
* When an event in SecurityHub fires, an event will be created by EventBridge and dropped onto an SQS queue.
* ServiceNow will pull the events from the SQS queue with the `SCSyncUser` using `acccess_key` & `secret_access_key`.

> **Note**
> The user will be created by the module, but the `acccess_key` & `secret_access_key` need to be generated in the AWS Console, to prevent storing this data in the Terraform state. If you want Terraform to create the `acccess_key` & `secret_access_key` (and output them), set variable `create_servicenow_access_keys` to `true` (default = false)

## How it works

The Security Hub Findings Manager listens to the AWS EventBridge event bus and triggers an execution when the `Security Hub Findings - Imported` event occurs.

Once the event is delivered, the `securityhub-events-suppressor` function will be triggered and will perform the following:

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
