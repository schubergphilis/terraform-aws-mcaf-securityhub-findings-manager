module "servicenow_integration" {
  count       = var.servicenow_integration ? 1 : 0
  source      = "./modules/servicenow/"
  kms_key_arn = var.kms_key_arn
}
