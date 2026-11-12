###############################################################################
# Example: Continuous backup (PITR) scoped to supported services only
#
# AWS Backup PITR supports S3 and supported RDS/Aurora configurations.
# Using a dedicated tag set routes continuous backup into its own plan/selection
# so PITR never runs against unsupported types (EFS, EKS, Redshift) — which
# would otherwise produce FAILED jobs and noisy alerts.
#
# DynamoDB PITR is separate native configuration owned by the caller.
# Tag supported resources with: backup-continuous = data
# Tag the snapshot workload with: backup-workload = data
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.72.0, < 6.0.0"
    }
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
  source = "../.."
  providers = {
    aws    = aws
    aws.dr = aws.dr
  }

  aws_region  = "eu-south-1"
  environment = "prod"

  solution_prefix = "team-data-vault"

  # Snapshot backup for everything in scope.
  selection_tags = {
    "backup-workload" = "data"
  }

  enable_continuous_backup  = true
  continuous_retention_days = 35
  retention_days            = 90

  # Continuous backup (PITR) only for the PITR-capable, explicitly-tagged subset.
  continuous_backup_selection_tags = {
    "backup-continuous" = "data"
  }

  dr_region = "eu-central-1"

  tags = {
    "backup-owner" = "team-data"
  }
}

module "backup_alerting" {
  source                 = "../../../terraform-aws-backup-alerting"
  enable_backup_coverage = false

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
