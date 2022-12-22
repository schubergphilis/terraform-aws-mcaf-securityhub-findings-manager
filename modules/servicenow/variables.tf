variable "cloudwatch_retention_days" {
  type        = number
  default     = 14
  description = "Time to retain the CloudWatch Logs for the ServiceNow integration"
}

variable "create_access_keys" {
  type        = bool
  default     = false
  description = "Whether to create an access_key and secret_access key for both ServiceNow users"
}

variable "kms_key_arn" {
  type        = string
  description = "The ARN of the KMS key used to encrypt the resources"
}
