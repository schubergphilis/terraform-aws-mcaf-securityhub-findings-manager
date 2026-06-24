locals {
  account_id     = data.aws_caller_identity.current.account_id
  account_region = var.region != null ? var.region : data.aws_region.current.region

  # Use a AWS provided layer to include Powertools to simplify the redistribution process.
  # Also see https://docs.powertools.aws.dev/lambda/python/latest/#lambda-layer.
  # See https://docs.aws.amazon.com/powertools/python/latest/getting-started/install/ for the available layer versions.
  powertools_layer_arn = "arn:aws:lambda:${local.account_region}:017000801446:layer:AWSLambdaPowertoolsPythonV3-${replace(var.lambda_runtime, ".", "")}-x86_64:27"
}

# Data Source to get the access to Account ID in which Terraform is authorized and the region configured on the provider
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
