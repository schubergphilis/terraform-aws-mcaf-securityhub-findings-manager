locals {
  ManagedPolicies = [
    "arn:aws:iam::aws:policy/service-role/AWSConfigRoleForOrganizations",
    "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess",
    "arn:aws:iam::aws:policy/AWSConfigUserAccess",
    "arn:aws:iam::aws:policy/AWSServiceCatalogAdminReadOnlyAccess"
  ]
}

# data "aws_iam_policy" "ManagedPolicies" {
#   for_each = local.ManagedPolicies
#   arn      = each.value
# }
