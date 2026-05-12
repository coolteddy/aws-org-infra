# ------------------------------------------------------------------------------
# AWS RAM — Organization Integration
#
# This enables AWS Resource Access Manager to understand accounts and OUs in this
# AWS Organization. It does not create any resource shares and it does not share
# the Transit Gateway with everyone.
#
# Actual shares are owned by the account that owns the resource. For example,
# aws-shared-services-infra will later create the TGW RAM share and explicitly
# name sandbox and temporary management as principals.
# ------------------------------------------------------------------------------

resource "aws_ram_sharing_with_organization" "this" {}
