# Read the existing organisation — cannot create a new one, it already exists.
# This data source gives us the Root ID needed to attach OUs and SCPs.
data "aws_organizations_organization" "this" {}

# ------------------------------------------------------------------------------
# Organisational Units
#
# Inheritance: Root → OU → Child OU → Account
# SCPs attached to an OU apply to everything inside it automatically.
#
# Creation order matters — Workloads must exist before Tenant-A
# can reference it as a parent. Terraform resolves this automatically
# because Tenant-A references workloads.id (an implicit dependency).
# ------------------------------------------------------------------------------

resource "aws_organizations_organizational_unit" "security" {
  name      = "Security"
  parent_id = data.aws_organizations_organization.this.roots[0].id
}

resource "aws_organizations_organizational_unit" "shared" {
  name      = "Shared"
  parent_id = data.aws_organizations_organization.this.roots[0].id
}

resource "aws_organizations_organizational_unit" "workloads" {
  name      = "Workloads"
  parent_id = data.aws_organizations_organization.this.roots[0].id
}

# Child of Workloads — one OU per tenant keeps accounts isolated.
# Future tenants follow the same pattern: add a new OU here, then
# add account requests in 3-aft/account-requests/.
resource "aws_organizations_organizational_unit" "tenant_a" {
  name      = "Tenant-A"
  parent_id = aws_organizations_organizational_unit.workloads.id
}
