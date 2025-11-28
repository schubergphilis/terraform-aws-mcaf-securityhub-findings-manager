variable "cloudwatch_retention_days" {
  type        = number
  default     = 365
  description = "Time to retain the CloudWatch Logs for the ServiceNow integration"
}

variable "create_access_keys" {
  type        = bool
  default     = false
  description = "Whether to create an access_key and secret_access key for the ServiceNow user"
}

variable "severity_label_filter" {
  type        = list(string)
  default     = []
  description = "Only forward findings to ServiceNow with severity labels from this list (by default all severity labels are forwarded)"
}

variable "kms_key_arn" {
  type        = string
  description = "The ARN of the KMS key used to encrypt the resources"
}

variable "region" {
  type        = string
  default     = null
  description = "The AWS region where resources will be created; if omitted the default provider region is used"
}

variable "tags" {
  type        = map(string)
  description = "A mapping of tags to assign to the resources"
}
