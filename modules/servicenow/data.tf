locals {
  ManagedPoliciesToGet = {
    AWSConfigRoleForOrganizations        = "arn:aws:iam::aws:policy/service-role/AWSConfigRoleForOrganizations",
    AmazonSSMReadOnlyAccess              = "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess",
    AWSConfigUserAccess                  = "arn:aws:iam::aws:policy/AWSConfigUserAccess",
    AWSServiceCatalogAdminReadOnlyAccess = "arn:aws:iam::aws:policy/AWSServiceCatalogAdminReadOnlyAccess"
  }
}

data "aws_iam_policy" "ManagedPolicies" {
  for_each = local.ManagedPoliciesToGet
  arn      = each.value
}
