###############################################################################
# Example: Continuous backup (PITR) scoped to supported services only
#
# Point-in-Time Recovery is only supported by some services (DynamoDB, S3, RDS).
# Using a dedicated tag set routes continuous backup into its own plan/selection
# so PITR never runs against unsupported types (EFS, EKS, Redshift) — which
# would otherwise produce FAILED jobs and noisy alerts.
#
# Tag DynamoDB/S3/RDS resources with:  backup-continuous = enabled
# Tag everything in scope with:        backup-policy     = enabled
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

module "backup" {
  source = "git::https://github.com/pagopa/<repo-name>.git//modules/backup?ref=v1.0.0"

  aws_region  = "eu-south-1"
  environment = "prod"

  solution_prefix = "team-data-vault"

  # Snapshot backup for everything in scope.
  selection_tags = {
    "backup-policy" = "enabled"
  }

  # Continuous backup (PITR) only for the PITR-capable, explicitly-tagged subset.
  continuous_backup_selection_tags = {
    "backup-continuous" = "enabled"
  }

  dr_region = "eu-central-1"

  tags = {
    "backup-owner" = "team-data"
  }
}

module "backup_alerting" {
  source = "git::https://github.com/pagopa/<repo-name>.git//modules/backup-alerting?ref=v1.0.0"

  solution_prefix = "team-data"
  kms_key_ids     = [module.backup.kms_key_id]
  email_endpoints = ["team-data-oncall@pagopa.it"]
}

output "vault_arn" {
  value = module.backup.vault_arn
}

output "continuous_plan_id" {
  value = module.backup.continuous_plan_id
}
