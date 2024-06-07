output "lambda_jira_security_hub_sg_id" {
  value       = length(module.lambda_jira_security_hub) > 0 ? module.lambda_jira_security_hub[*].security_group_id : null
  description = "This will output the security group id attached to the jira_security_hub Lambda. This can be used to tune ingress and egress rules."
}

output "lambda_securityhub_events_suppressor_sg_id" {
  value       = module.lambda_securityhub_events_suppressor.security_group_id
  description = "This will output the security group id attached to the securityhub_events_suppressor Lambda. This can be used to tune ingress and egress rules."
}

output "lambda_securityhub_trigger_suppressor_sg_id" {
  value       = module.lambda_securityhub_trigger_suppressor.security_group_id
  description = "This will output the security group id attached to the securityhub_trigger_suppressor Lambda. This can be used to tune ingress and egress rules."
}
