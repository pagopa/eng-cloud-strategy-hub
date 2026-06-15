###############################################################################
# Example: Production Account — Core Backup + Alerting + Extended Plans
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
# Core Backup Module
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

  # Override retention for this team (default is 35 days)
  retention_days     = 365
  cold_storage_after = 90

  # Add an extra weekly rule to the default plan without creating a separate
  # backup-plan module or a second selection.
  default_plan_additional_rules = [
    {
      rule_name          = "weekly-compliance-copy"
      schedule           = "cron(0 5 ? * SUN *)"
      cold_storage_after = 30
      delete_after       = 120
      copy_delete_after  = 180
      recovery_point_tags = {
        "backup-frequency" = "weekly"
      }
    }
  ]

  # Cross-region copy to Frankfurt
  cross_region_copy = "CopyToSecondaryRegion"
  dr_region         = "eu-central-1"

  # Enable restore testing
  enable_restore_testing   = true
  restore_testing_schedule = "cron(0 3 ? * SAT *)"

  tags = {
    "backup-owner"      = "team-payments"
    "backup-data-class" = "critical"
    "Product"           = "pagoPA-payments"
  }
}

###############################################################################
# Alerting Module (separate lifecycle)
###############################################################################

module "backup_alerting" {
  source = "git::https://github.com/pagopa/<repo-name>.git//modules/backup-alerting?ref=v1.0.0"

  solution_prefix = "team-payments"

  # Monitor the backup CMK for accidental deletion
  kms_key_ids = [module.backup.kms_key_id]

  # Email alerts
  email_endpoints = ["team-payments-oncall@pagopa.it"]

  tags = {
    "backup-owner" = "team-payments"
    "Environment"  = "prod"
  }
}

###############################################################################
# Optional: Long-retention plan for payment trails (10-year retention)
###############################################################################

module "backup_long_retention" {
  source = "git::https://github.com/pagopa/<repo-name>.git//modules/backup/modules/presets/long-retention?ref=v1.0.0"

  vault_name      = module.backup.vault_name
  backup_role_arn = module.backup.backup_role_arn

  selection_tags = {
    "backup-data-class" = "critical"
  }

  retention_days     = 3650
  cold_storage_after = 90

  tags = {
    "backup-owner" = "team-payments"
    "Product"      = "pagoPA-payments"
  }
}

###############################################################################
# Optional: Hourly preset for low-RPO workloads (separate selection)
###############################################################################

module "backup_hourly" {
  source = "git::https://github.com/pagopa/<repo-name>.git//modules/backup/modules/presets/hourly-backup?ref=v1.0.0"

  vault_name      = module.backup.vault_name
  backup_role_arn = module.backup.backup_role_arn

  selection_tags = {
    "backup-tier" = "critical-rpo"
  }

  retention_days = 7

  tags = {
    "backup-owner" = "team-payments"
    "Product"      = "pagoPA-payments"
  }
}

###############################################################################
# Optional: Bespoke plan via backup-plan (separate selection + custom schedule)
###############################################################################

module "backup_twice_daily" {
  source = "git::https://github.com/pagopa/<repo-name>.git//modules/backup/modules/backup-plan?ref=v1.0.0"

  plan_name    = "team-payments-twice-daily"
  iam_role_arn = module.backup.backup_role_arn

  selection_tags = {
    "backup-policy" = "twice-daily"
  }

  tags = {
    "backup-owner" = "team-payments"
    "Product"      = "pagoPA-payments"
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

###############################################################################
# Outputs
###############################################################################

output "vault_arn" {
  value = module.backup.vault_arn
}

output "sns_topic_arn" {
  value = module.backup_alerting.sns_topic_arn
}

output "backup_long_retention_plan_id" {
  value = module.backup_long_retention.plan_id
}

output "backup_hourly_plan_id" {
  value = module.backup_hourly.plan_id
}

output "backup_twice_daily_plan_id" {
  value = module.backup_twice_daily.plan_id
}
