variable "findings_manager_events_lambda" {
  type = object({
    name        = optional(string, "securityhub-findings-manager-events")
    log_level   = optional(string, "ERROR")
    memory_size = optional(number, 256)
    timeout     = optional(number, 300)

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

variable "findings_manager_trigger_lambda" {
  type = object({
    name        = optional(string, "securityhub-findings-manager-trigger")
    log_level   = optional(string, "ERROR")
    memory_size = optional(number, 256)
    timeout     = optional(number, 300)

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

variable "findings_manager_worker_lambda" {
  type = object({
    name        = optional(string, "securityhub-findings-manager-worker")
    log_level   = optional(string, "ERROR")
    memory_size = optional(number, 256)
    timeout     = optional(number, 900)

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
  description = "Findings Manager Lambda settings - Manage Security Hub findings in response to SQS trigger"

  validation {
    condition     = alltrue([for o in var.findings_manager_worker_lambda.security_group_egress_rules : (o.cidr_ipv4 != null || o.cidr_ipv6 != null || o.prefix_list_id != null || o.referenced_security_group_id != null)])
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
    autoclose_enabled                     = optional(bool, false)
    autoclose_comment                     = optional(string, "Security Hub finding has been resolved. Autoclosing the issue.")
    autoclose_transition_name             = optional(string, "Close Issue")
    credentials_secretsmanager_arn        = optional(string)
    credentials_ssm_secret_arn            = optional(string)
    exclude_account_ids                   = optional(list(string), [])
    finding_severity_normalized_threshold = optional(number, 70)
    issue_custom_fields                   = optional(map(string), {})
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
      name        = optional(string, "securityhub-findings-manager-jira")
      log_level   = optional(string, "INFO")
      memory_size = optional(number, 256)
      timeout     = optional(number, 60)
      }), {
      name                        = "securityhub-findings-manager-jira"
      iam_role_name               = "SecurityHubFindingsManagerJiraLambda"
      log_level                   = "INFO"
      memory_size                 = 256
      timeout                     = 60
      security_group_egress_rules = []
    })

    step_function_settings = optional(object({
      log_level = optional(string, "ERROR")
      retention = optional(number, 90)
      }), {
      log_level = "ERROR"
      retention = 90
    })

  })
  default = {
    enabled     = false
    project_key = null
  }
  description = "Findings Manager - Jira integration settings"

  validation {
    condition     = alltrue([for o in var.jira_integration.security_group_egress_rules : (o.cidr_ipv4 != null || o.cidr_ipv6 != null || o.prefix_list_id != null || o.referenced_security_group_id != null)])
    error_message = "Although \"cidr_ipv4\", \"cidr_ipv6\", \"prefix_list_id\", and \"referenced_security_group_id\" are all marked as optional, you must provide one of them in order to configure the destination of the traffic."
  }

  validation {
    condition     = var.jira_integration.enabled == false || (var.jira_integration.credentials_secretsmanager_arn != null && var.jira_integration.credentials_ssm_secret_arn == null) || (var.jira_integration.credentials_secretsmanager_arn == null && var.jira_integration.credentials_ssm_secret_arn != null)
    error_message = "You must provide either 'credentials_secretsmanager_arn' or 'credentials_ssm_secret_arn' for jira credentials, but not both."
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

# Modify the build-lambda.yaml GitHub action if you modify the allowed versions to ensure a proper zip is created.
variable "lambda_runtime" {
  type        = string
  default     = "python3.12"
  description = "The version of Python to use for the Lambda functions"
  validation {
    condition     = contains(["python3.11", "python3.12"], var.lambda_runtime)
    error_message = "The runtime must be one of the following: python3.11, python3.12."
  }
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
