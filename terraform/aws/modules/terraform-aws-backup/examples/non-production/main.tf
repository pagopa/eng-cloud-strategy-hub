###############################################################################
# Example: Non-Production Account (dev / uat)
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

# DR provider still required by module signature, even if cross-region copy is off
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
  solution_prefix = "team-payments-dev-vault"

  selection_tags = {
    "backup-policy" = "enabled"
  }

  # Shorter retention for dev
  retention_days = 7

  # No cross-region copy in dev (default for nonprod)
  cross_region_copy = "DoNotCopyToOtherRegions"

  tags = {
    "backup-owner" = "team-payments"
    "Environment"  = "dev"
    "Product"      = "pagoPA-payments"
  }
}

###############################################################################
# Alerting (optional in dev) — separate module, email only
###############################################################################

module "backup_alerting" {
  source = "git::https://github.com/pagopa/<repo-name>.git//modules/backup-alerting?ref=v1.0.0"

  solution_prefix = "team-payments-dev"

  kms_key_ids     = [module.backup.kms_key_id]
  email_endpoints = ["team-payments-dev@pagopa.it"]

  tags = {
    "backup-owner" = "team-payments"
    "Environment"  = "dev"
  }
}
