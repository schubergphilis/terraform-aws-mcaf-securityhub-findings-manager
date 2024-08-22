variable "findings_manager_events_lambda" {
  type = object({
    name        = optional(string, "securityhub-findings-manager-events")
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
  description = "Findings Manager Lambda settings - Manage Security Hub findings in response to EventBridge events"

  validation {
    condition     = alltrue([for o in var.findings_manager_events_lambda.security_group_egress_rules : (o.cidr_ipv4 != null || o.cidr_ipv6 != null || o.prefix_list_id != null || o.referenced_security_group_id != null)])
    error_message = "Although \"cidr_ipv4\", \"cidr_ipv6\", \"prefix_list_id\", and \"referenced_security_group_id\" are all marked as optional, you must provide one of them in order to configure the destination of the traffic."
  }
}

variable "findings_manager_lambda_iam_role_name" {
  type        = string
  default     = "SecurityHubFindingsManagerLambda"
  description = "The name of the role which will be assumed by both Findings Manager Lambda functions"
}

variable "findings_manager_trigger_lambda" {
  type = object({
    name        = optional(string, "securityhub-findings-manager-trigger")
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
  description = "Findings Manager Lambda settings - Manage Security Hub findings in response to S3 file upload triggers"

  validation {
    condition     = alltrue([for o in var.findings_manager_trigger_lambda.security_group_egress_rules : (o.cidr_ipv4 != null || o.cidr_ipv6 != null || o.prefix_list_id != null || o.referenced_security_group_id != null)])
    error_message = "Although \"cidr_ipv4\", \"cidr_ipv6\", \"prefix_list_id\", and \"referenced_security_group_id\" are all marked as optional, you must provide one of them in order to configure the destination of the traffic."
  }
}

variable "jira_eventbridge_iam_role_name" {
  type        = string
  default     = "SecurityHubFindingsManagerJiraEventBridge"
  description = "The name of the role which will be assumed by EventBridge rules for Jira integration"
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
      name          = optional(string, "securityhub-findings-manager-jira")
      iam_role_name = optional(string, "SecurityHubFindingsManagerJiraLambda")
      log_level     = optional(string, "INFO")
      memory_size   = optional(number, 256)
      runtime       = optional(string, "python3.8")
      timeout       = optional(number, 60)
      }), {
      name                        = "securityhub-findings-manager-jira"
      iam_role_name               = "SecurityHubFindingsManagerJiraLambda"
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
  description = "Findings Manager - Jira integration settings"

  validation {
    condition     = alltrue([for o in var.jira_integration.security_group_egress_rules : (o.cidr_ipv4 != null || o.cidr_ipv6 != null || o.prefix_list_id != null || o.referenced_security_group_id != null)])
    error_message = "Although \"cidr_ipv4\", \"cidr_ipv6\", \"prefix_list_id\", and \"referenced_security_group_id\" are all marked as optional, you must provide one of them in order to configure the destination of the traffic."
  }
}

variable "jira_step_function_iam_role_name" {
  type        = string
  default     = "SecurityHubFindingsManagerJiraStepFunction"
  description = "The name of the role which will be assumed by AWS Step Function for Jira integration"
}

variable "kms_key_arn" {
  type        = string
  description = "The ARN of the KMS key used to encrypt the resources"
}

variable "rules_filepath" {
  type        = string
  default     = ""
  description = "Pathname to the file that stores the manager rules"
}

variable "rules_s3_object_name" {
  type        = string
  default     = "rules.yaml"
  description = "The S3 object containing the rules to be applied to Security Hub findings manager"
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

variable "subnet_ids" {
  type        = list(string)
  default     = null
  description = "The subnet ids where the Lambda functions needs to run"
}

variable "s3_bucket_name" {
  type        = string
  description = "The name for the S3 bucket which will be created for storing the function's deployment package"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "A mapping of tags to assign to the resources"
}

variable "python_version" {
  type        = string
  default     = "3.12"
  description = "The version of Python to use for the Lambda function"
  validation {
    condition = contains(["3.8", "3.9", "3.10", "3.11", "3.12"], var.python_version)
    error_message = "The python_version must be one of: 3.8, 3.9, 3.10, 3.11, 3.12."
  }
}