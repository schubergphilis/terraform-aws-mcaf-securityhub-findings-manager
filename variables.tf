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
    # Global settings for all jira instances
    autoclose_comment             = optional(string, "Security Hub finding has been resolved. Autoclosing the issue.")
    autoclose_enabled             = optional(bool, false)
    autoclose_suppressed_findings = optional(bool, false)
    exclude_account_ids           = optional(list(string), [])

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
      log_level   = optional(string, "ERROR")
      memory_size = optional(number, 256)
      timeout     = optional(number, 60)
    }), {})

    step_function_settings = optional(object({
      log_level = optional(string, "ERROR")
      retention = optional(number, 90)
    }), {})

    # Per-instance configurations
    instances = optional(map(object({
      enabled                               = optional(bool, true)
      credentials_secretsmanager_arn        = optional(string)
      credentials_ssm_secret_arn            = optional(string)
      default_instance                      = optional(bool, false)
      include_account_ids                   = optional(list(string), [])
      include_intermediate_transition       = optional(string)
      issue_custom_fields                   = optional(map(string), {})
      issue_type                            = optional(string, "Security Advisory")
      project_key                           = string
      autoclose_transition_name             = optional(string, "Close Issue")
      finding_severity_normalized_threshold = optional(number, 70)
      include_product_names                 = optional(list(string), [])
    })), {})
  })
  default     = null
  description = "Findings Manager - Jira integration settings"

  validation {
    condition     = var.jira_integration == null || alltrue([for o in var.jira_integration.security_group_egress_rules : (o.cidr_ipv4 != null || o.cidr_ipv6 != null || o.prefix_list_id != null || o.referenced_security_group_id != null)])
    error_message = "Although \"cidr_ipv4\", \"cidr_ipv6\", \"prefix_list_id\", and \"referenced_security_group_id\" are all marked as optional, you must provide one of them in order to configure the destination of the traffic."
  }

  validation {
    condition = var.jira_integration == null || alltrue([
      for instance_name, instance in var.jira_integration.instances : (
        !instance.enabled ||
        (instance.credentials_secretsmanager_arn != null && instance.credentials_ssm_secret_arn == null) ||
        (instance.credentials_secretsmanager_arn == null && instance.credentials_ssm_secret_arn != null)
      )
    ])
    error_message = "Each enabled Jira instance must provide either 'credentials_secretsmanager_arn' or 'credentials_ssm_secret_arn', but not both."
  }

  validation {
    condition = var.jira_integration == null || alltrue([
      for instance_name, instance in var.jira_integration.instances : (
        !instance.enabled ||
        length(instance.include_account_ids) > 0 ||
        instance.default_instance
      )
    ])
    error_message = "For each enabled Jira instance if 'include_account_ids' is empty, 'default_instance' must be set to true."
  }

  validation {
    condition = var.jira_integration == null || length(var.jira_integration.instances) == 0 || (
      length(flatten([for instance in var.jira_integration.instances : instance.include_account_ids if instance.enabled && length(instance.include_account_ids) > 0])) ==
      length(distinct(flatten([for instance in var.jira_integration.instances : instance.include_account_ids if instance.enabled && length(instance.include_account_ids) > 0])))
    )
    error_message = "For each enabled Jira instance the 'include_account_ids' must be mutually exclusive. Each account ID can only appear in one enabled instance."
  }

  validation {
    condition = var.jira_integration == null || length([
      for instance_name, instance in var.jira_integration.instances : instance_name
      if instance.enabled && instance.default_instance
    ]) <= 1
    error_message = "At most one enabled Jira instance can have 'default_instance' set to true."
  }

  validation {
    condition = var.jira_integration == null || length(setintersection(
      var.jira_integration.exclude_account_ids,
      flatten([for instance in var.jira_integration.instances : instance.include_account_ids if instance.enabled && length(instance.include_account_ids) > 0])
    )) == 0
    error_message = "For each enabled Jira instance the 'exclude_account_ids' cannot overlap with any enabled instance's 'include_account_ids'."
  }

  validation {
    condition = var.jira_integration == null || (
      !try(var.jira_integration.autoclose_suppressed_findings, false) ||
      try(var.jira_integration.autoclose_enabled, false)
    )
    error_message = "When 'autoclose_suppressed_findings' is set to true, 'autoclose_enabled' must also be set to true."
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
