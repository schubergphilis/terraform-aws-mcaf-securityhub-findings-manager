variable "dynamodb_deletion_protection" {
  type        = bool
  default     = true
  description = "The DynamoDB table deletion protection option."
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

variable "jira_integration" {
  type = object({
    enabled                               = optional(bool, false)
    credentials_secret_arn                = string
    exclude_account_ids                   = optional(list(string), [])
    finding_severity_normalized_threshold = optional(number, 70)
    issue_type                            = optional(string, "Security Advisory")
    project_key                           = string

    security_group_egress_rules = optional(list(object({
      cidr_ipv4                    = optional(string)
      cidr_ipv6                    = optional(string)
      description                  = string
      from_port                    = optional(number, 0)
      ip_protocol                  = optional(string, "-1")
      prefix_list_id               = optional(string)
      referenced_security_group_id = optional(string)
      to_port                      = optional(number, 0)
    })), [])

    lambda_settings = optional(object({
      name          = optional(string, "securityhub-jira")
      iam_role_name = optional(string, "LambdaJiraSecurityHubRole")
      log_level     = optional(string, "INFO")
      memory_size   = optional(number, 256)
      runtime       = optional(string, "python3.8")
      timeout       = optional(number, 60)
      }), {
      name                        = "securityhub-jira"
      iam_role_name               = "LambdaJiraSecurityHubRole"
      log_level                   = "INFO"
      memory_size                 = 256
      runtime                     = "python3.8"
      timeout                     = 60
      security_group_egress_rules = []
    })
  })
  default = {
    enabled                = false
    credentials_secret_arn = null
    project_key            = null
  }
  description = "Jira integration settings"

  validation {
    condition     = alltrue([for o in var.jira_integration.security_group_egress_rules : (o.cidr_ipv4 != null || o.cidr_ipv6 != null || o.prefix_list_id != null || o.referenced_security_group_id != null)])
    error_message = "Although \"cidr_ipv4\", \"cidr_ipv6\", \"prefix_list_id\", and \"referenced_security_group_id\" are all marked as optional, you must provide one of them in order to configure the destination of the traffic."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "The ARN of the KMS key used to encrypt the resources"
}

variable "lambda_events_suppressor" {
  type = object({
    name        = optional(string, "securityhub-events-suppressor")
    log_level   = optional(string, "INFO")
    memory_size = optional(number, 256)
    runtime     = optional(string, "python3.8")
    timeout     = optional(number, 120)

    security_group_egress_rules = optional(list(object({
      cidr_ipv4                    = optional(string)
      cidr_ipv6                    = optional(string)
      description                  = string
      from_port                    = optional(number, 0)
      ip_protocol                  = optional(string, "-1")
      prefix_list_id               = optional(string)
      referenced_security_group_id = optional(string)
      to_port                      = optional(number, 0)
    })), [])
  })
  default     = {}
  description = "Lambda Events Suppressor settings - Supresses the Security Hub findings in response to EventBridge Trigger"

  validation {
    condition     = alltrue([for o in var.lambda_events_suppressor.security_group_egress_rules : (o.cidr_ipv4 != null || o.cidr_ipv6 != null || o.prefix_list_id != null || o.referenced_security_group_id != null)])
    error_message = "Although \"cidr_ipv4\", \"cidr_ipv6\", \"prefix_list_id\", and \"referenced_security_group_id\" are all marked as optional, you must provide one of them in order to configure the destination of the traffic."
  }
}

variable "lambda_streams_suppressor" {
  type = object({
    name        = optional(string, "securityhub-streams-suppressor")
    log_level   = optional(string, "INFO")
    memory_size = optional(number, 256)
    runtime     = optional(string, "python3.8")
    timeout     = optional(number, 120)

    security_group_egress_rules = optional(list(object({
      cidr_ipv4                    = optional(string)
      cidr_ipv6                    = optional(string)
      description                  = string
      from_port                    = optional(number, 0)
      ip_protocol                  = optional(string, "-1")
      prefix_list_id               = optional(string)
      referenced_security_group_id = optional(string)
      to_port                      = optional(number, 0)
    })), [])
  })
  default     = {}
  description = "Lambda Streams Suppressor settings - Supresses the Security Hub findings in response to DynamoDB streams"

  validation {
    condition     = alltrue([for o in var.lambda_streams_suppressor.security_group_egress_rules : (o.cidr_ipv4 != null || o.cidr_ipv6 != null || o.prefix_list_id != null || o.referenced_security_group_id != null)])
    error_message = "Although \"cidr_ipv4\", \"cidr_ipv6\", \"prefix_list_id\", and \"referenced_security_group_id\" are all marked as optional, you must provide one of them in order to configure the destination of the traffic."
  }
}

variable "lambda_suppressor_iam_role_name" {
  type        = string
  default     = "LambdaSecurityHubSuppressorRole"
  description = "The name of the role which will be assumed by both Suppressor Lambda functions"
}

variable "s3_bucket_name" {
  type        = string
  description = "The name for the S3 bucket which will be created for storing the function's deployment package"
}

variable "servicenow_integration" {
  type = object({
    enabled                   = optional(bool, false)
    create_access_keys        = optional(bool, false)
    cloudwatch_retention_days = optional(number, 365)
    severity_label_filter     = optional(list(string), [])
  })
  default = {
    enabled = false
  }
  description = "ServiceNow integration settings"
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
  default     = {}
  description = "A mapping of tags to assign to the resources"
}
