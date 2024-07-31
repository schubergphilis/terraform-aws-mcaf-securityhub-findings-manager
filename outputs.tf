output "jira_lambda_sg_id" {
  value       = length(module.jira_lambda) > 0 ? module.jira_lambda[*].security_group_id : null
  description = "This will output the security group id attached to the jira_lambda Lambda. This can be used to tune ingress and egress rules."
}

output "findings_manager_events_lambda_sg_id" {
  value       = module.findings_manager_events_lambda.security_group_id
  description = "This will output the security group id attached to the lambda_findings_manager_events Lambda. This can be used to tune ingress and egress rules."
}

output "findings_manager_trigger_lambda_sg_id" {
  value       = module.findings_manager_trigger_lambda.security_group_id
  description = "This will output the security group id attached to the lambda_findings_manager_trigger Lambda. This can be used to tune ingress and egress rules."
}
