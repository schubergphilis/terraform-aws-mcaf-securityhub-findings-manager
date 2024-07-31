# Data Source to get the access to Account ID in which Terraform is authorized and the region configured on the provider
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}
