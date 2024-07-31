output "lambda_jira_securityhub_sg_id" {
  value       = length(module.lambda_jira_securityhub) > 0 ? module.lambda_jira_securityhub[*].security_group_id : null
  description = "This will output the security group id attached to the jira_securityhub Lambda. This can be used to tune ingress and egress rules."
}

output "lambda_findings_manager_events_sg_id" {
  value       = module.lambda_findings_manager_event.security_group_id
  description = "This will output the security group id attached to the lambda_findings_manager_events Lambda. This can be used to tune ingress and egress rules."
}

output "lambda_findings_manager_trigger_sg_id" {
  value       = module.lambda_findings_manager_trigger.security_group_id
  description = "This will output the security group id attached to the lambda_findings_manager_trigger Lambda. This can be used to tune ingress and egress rules."
}
