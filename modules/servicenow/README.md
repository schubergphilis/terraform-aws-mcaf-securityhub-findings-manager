# Usage
<!--- BEGIN_TF_DOCS --->
## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| aws | n/a |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| kms\_key\_arn | The ARN of the KMS key used to encrypt the resources | `string` | n/a | yes |
| tags | A mapping of tags to assign to the resources | `map(string)` | n/a | yes |
| cloudwatch\_retention\_days | Time to retain the CloudWatch Logs for the ServiceNow integration | `number` | `14` | no |
| create\_access\_keys | Whether to create an access\_key and secret\_access key for the ServiceNow user | `bool` | `false` | no |

## Outputs

No output.

<!--- END_TF_DOCS --->
