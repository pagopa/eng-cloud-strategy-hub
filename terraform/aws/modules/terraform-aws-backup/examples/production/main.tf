###############################################################################
# Example: Production Account — Core Backup + Alerting
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
# Outputs
###############################################################################

output "vault_arn" {
  value = module.backup.vault_arn
}

output "sns_topic_arn" {
  value = module.backup_alerting.sns_topic_arn
}
