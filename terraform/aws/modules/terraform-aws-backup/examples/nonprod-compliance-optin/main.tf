###############################################################################
# Example: Non-production that opts into COMPLIANCE Vault Lock
#
# Decision §7.2 keeps pre-production flexible (GOVERNANCE by default), but a team
# can opt into COMPLIANCE mode — e.g. a UAT account that holds realistic data.
#
# WARNING: COMPLIANCE mode is irreversible after the cooling-off window. Once
# locked, recovery points cannot be deleted before retention expires by anyone,
# including root. Use only when the team accepts non-deletable backups.
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.30.0, < 6.0.0"
    }
  }

  backend "s3" {
    # Configure your backend here
  }
}

provider "aws" {
  region = "eu-south-1"
}

provider "aws" {
  alias  = "dr"
  region = "eu-central-1"
}

module "backup" {
  source = "git::https://github.com/pagopa/<repo-name>.git//modules/backup?ref=v1.0.0"

  providers = {
    aws    = aws
    aws.dr = aws.dr
  }

  environment     = "nonprod"
  solution_prefix = "team-identity-uat-vault"

  selection_tags = {
    "backup-policy" = "enabled"
  }

  # Opt into COMPLIANCE in this pre-prod account.
  vault_lock_mode = "COMPLIANCE"

  # COMPLIANCE requires retention >= min retention; raise both above the
  # nonprod defaults (retention 14, min lock 7).
  retention_days                = 35
  vault_lock_min_retention_days = 35

  # In COMPLIANCE mode this sets the grace period before the lock date: for 7
  # days the vault lock can still be changed or removed before it becomes immutable.
  vault_lock_changeable_for_days = 7

  tags = {
    "backup-owner" = "team-identity"
    "Environment"  = "uat"
  }
}
