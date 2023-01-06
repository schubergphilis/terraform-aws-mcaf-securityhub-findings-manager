locals {
  ManagedPolicies = [
    "arn:aws:iam::aws:policy/service-role/AWSConfigRoleForOrganizations",
    "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess",
    "arn:aws:iam::aws:policy/AWSConfigUserAccess",
    "arn:aws:iam::aws:policy/AWSServiceCatalogAdminReadOnlyAccess"
  ]
}
