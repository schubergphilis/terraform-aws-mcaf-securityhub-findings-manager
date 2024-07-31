variable "rules_filepath" {
  type        = string
  default     = ""
  description = "Pathname to the file that stores the manager rules"
}

variable "rules_s3_object_name" {
  type        = string
  default     = "rules.yaml"
  description = "The S3 object containing the rules to be applied to Security Hub findings"
}

variable "jira_eventbridge_findings_manager_iam_role_name" {
  type        = string
  default     = "JiraEventBridgeFindingsManagerRole"
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
      name          = optional(string, "findings-manager-jira")
      iam_role_name = optional(string, "LambdaFindingsManagerJiraRole")
      log_level     = optional(string, "INFO")
      memory_size   = optional(number, 256)
      runtime       = optional(string, "python3.8")
      timeout       = optional(number, 60)
      }), {
      name                        = "findings-manager-jira"
      iam_role_name               = "LambdaFindingsManagerJiraRole"
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

variable "lambda_findings_manager_events" {
  type = object({
    name        = optional(string, "findings-manager-events")
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
    condition     = alltrue([for o in var.lambda_findings_manager_events.security_group_egress_rules : (o.cidr_ipv4 != null || o.cidr_ipv6 != null || o.prefix_list_id != null || o.referenced_security_group_id != null)])
    error_message = "Although \"cidr_ipv4\", \"cidr_ipv6\", \"prefix_list_id\", and \"referenced_security_group_id\" are all marked as optional, you must provide one of them in order to configure the destination of the traffic."
  }
}

variable "lambda_findings_manager_trigger" {
  type = object({
    name        = optional(string, "findings-manager-trigger")
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
    condition     = alltrue([for o in var.lambda_findings_manager_trigger.security_group_egress_rules : (o.cidr_ipv4 != null || o.cidr_ipv6 != null || o.prefix_list_id != null || o.referenced_security_group_id != null)])
    error_message = "Although \"cidr_ipv4\", \"cidr_ipv6\", \"prefix_list_id\", and \"referenced_security_group_id\" are all marked as optional, you must provide one of them in order to configure the destination of the traffic."
  }
}

variable "lambda_findings_manager_iam_role_name" {
  type        = string
  default     = "LambdaFindingsManagerRole"
  description = "The name of the role which will be assumed by both Findings Manager Lambda functions"
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

variable "jira_step_function_findings_manager_iam_role_name" {
  type        = string
  default     = "JiraStepFunctionFindingsManagerRole"
  description = "The name of the role which will be assumed by AWS Step Function for Jira integration"
}

variable "subnet_ids" {
  type        = list(string)
  default     = null
  description = "The subnet ids where the Lambda functions needs to run"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "A mapping of tags to assign to the resources"
}
