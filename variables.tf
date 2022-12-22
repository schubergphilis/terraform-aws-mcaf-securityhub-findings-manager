variable "create_allow_all_egress_rule" {
  type        = bool
  default     = true
  description = "Whether to create a default any/any egress sg rule for lambda"
}

variable "create_servicenow_access_keys" {
  type        = bool
  default     = false
  description = "Whether Terraform needs to create and output the access keys for the ServiceNow integration"
}

variable "dynamodb_table" {
  type        = string
  default     = "securityhub-suppression-list"
  description = "The DynamoDB table containing the items to be suppressed in Security Hub"
}

variable "eventbridge_suppressor_iam_role_name" {
  type        = string
  default     = "EventBridgeSecurityHubSuppressorRole"
  description = "The name of the role which will be assumed by EventBridge rules"
}

variable "jira_exclude_account_filter" {
  type        = list(string)
  default     = []
  description = "A list of account IDs for which no issue will be created in Jira"
}

variable "jira_finding_severity_normalized" {
  type        = number
  default     = 70
  description = "Finding severity(in normalized form) threshold for jira ticket creation"
}

variable "jira_integration" {
  type        = bool
  default     = true
  description = "Whether to create Jira tickets for Security Hub findings. This requires the variables `jira_project_key` and `jira_secret_arn` to be set"
}

variable "jira_issue_type" {
  type        = string
  default     = "Security Advisory"
  description = "The issue type for which the Jira issue will be created"
}

variable "jira_project_key" {
  type        = string
  default     = null
  description = "The project key the Jira issue will be created under"
}

variable "jira_secret_arn" {
  type        = string
  default     = null
  description = "Secret arn that stores the secrets for Jira api calls. The Secret should include url, apiuser and apikey"
}

variable "kms_key_arn" {
  type        = string
  description = "The ARN of the KMS key used to encrypt the resources"
}

variable "lambda_events_suppressor_name" {
  type        = string
  default     = "securityhub-events-suppressor"
  description = "The Lambda which will supress the Security Hub findings in response to EventBridge Trigger"
}

variable "lambda_jira_iam_role_name" {
  type        = string
  default     = "LambdaJiraSecurityHubRole"
  description = "The name of the role which will be assumed by Jira Lambda function"
}

variable "lambda_jira_name" {
  type        = string
  default     = "securityhub-jira"
  description = "The Lambda which will create jira ticket and set the Security Hub workflow status to notified"
}

variable "lambda_log_level" {
  type        = string
  default     = "INFO"
  description = "Sets how verbose lambda Logger should be"
}

variable "lambda_streams_suppressor_name" {
  type        = string
  default     = "securityhub-streams-suppressor"
  description = "The Lambda which will supress the Security Hub findings in response to DynamoDB streams"
}

variable "lambda_suppressor_iam_role_name" {
  type        = string
  default     = "LambdaSecurityHubSuppressorRole"
  description = "The name of the role which will be assumed by Suppressor Lambda functions"
}

variable "s3_bucket_name" {
  type        = string
  description = "The name for the S3 bucket which will be created for storing the function's deployment package"
}

variable "servicenow_integration" {
  type        = bool
  default     = false
  description = "Whether to enable the ServiceNow integration"
}

variable "step_function_suppressor_iam_role_name" {
  type        = string
  default     = "StepFunctionSecurityHubSuppressorRole"
  description = "The name of the role which will be assumed by Suppressor Step function"
}

variable "subnet_ids" {
  type        = list(string)
  default     = null
  description = "The subnet ids where the lambda's needs to run"
}

variable "tags" {
  type        = map(string)
  description = "A mapping of tags to assign to the resources"
}
