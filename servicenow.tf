module "servicenow_integration" {
  count              = var.servicenow_integration ? 1 : 0
  source             = "./modules/servicenow/"
  create_access_keys = var.create_servicenow_access_keys
  kms_key_arn        = var.kms_key_arn
}
