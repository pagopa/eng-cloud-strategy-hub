###############################################################################
# Example: Core backup + extra plans (presets and a bespoke plan)
#
# Shows how a team extends the default plan with:
#   - the long-retention preset (regulatory 10-year retention)
#   - the hourly-backup preset (low RPO)
#   - a bespoke plan built directly on the backup-plan sub-module
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

###############################################################################
# Core module
###############################################################################

module "backup" {
  source = "git::https://github.com/pagopa/<repo-name>.git//modules/backup?ref=v1.0.0"

  providers = {
    aws    = aws
    aws.dr = aws.dr
  }

  environment     = "prod"
  solution_prefix = "team-payments-vault"

  selection_tags = {
    "backup-policy" = "enabled"
  }

  cross_region_copy = "CopyToSecondaryRegion"
  dr_region         = "eu-central-1"

  tags = {
    "backup-owner" = "team-payments"
  }
}

###############################################################################
# Preset: long retention for payment trails (10 years)
###############################################################################

module "long_retention" {
  source = "git::https://github.com/pagopa/<repo-name>.git//modules/backup/modules/presets/long-retention?ref=v1.0.0"

  vault_name      = module.backup.vault_name
  backup_role_arn = module.backup.backup_role_arn

  selection_tags = {
    "backup-data-class" = "critical"
  }

  retention_days = 3650
}

###############################################################################
# Preset: hourly backup for low-RPO workloads
###############################################################################

module "hourly" {
  source = "git::https://github.com/pagopa/<repo-name>.git//modules/backup/modules/presets/hourly-backup?ref=v1.0.0"

  vault_name      = module.backup.vault_name
  backup_role_arn = module.backup.backup_role_arn

  selection_tags = {
    "backup-policy" = "hourly"
  }
}

###############################################################################
# Bespoke plan built directly on the backup-plan sub-module
###############################################################################

module "twice_daily" {
  source = "git::https://github.com/pagopa/<repo-name>.git//modules/backup/modules/backup-plan?ref=v1.0.0"

  plan_name    = "team-payments-twice-daily"
  iam_role_arn = module.backup.backup_role_arn

  selection_tags = {
    "backup-policy" = "twice-daily"
  }

  rules = [
    {
      rule_name         = "morning"
      target_vault_name = module.backup.vault_name
      schedule          = "cron(0 6 * * ? *)"
      delete_after      = 35
    },
    {
      rule_name         = "evening"
      target_vault_name = module.backup.vault_name
      schedule          = "cron(0 18 * * ? *)"
      delete_after      = 35
    }
  ]
}
