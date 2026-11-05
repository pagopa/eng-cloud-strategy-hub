###############################################################################
# Example: Non-Production Account (dev / uat)
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.71.0, < 6.0.0"
    }
  }

}

provider "aws" {
  region = "eu-south-1"
}

# Vault lock mode is by default set to GOVERNANCE in non-production
module "backup" {
  source = "../.."
  providers = {
    aws    = aws
    aws.dr = aws
  }

  aws_region  = "eu-south-1"
  environment = "nonprod"

  solution_prefix = "team-payments-dev-vault"

  selection_tags = {
    "backup-workload" = "payments-dev"
  }

  # Shorter retention for dev
  retention_days = 7

  default_plan_additional_rules = [
    {
      rule_name          = "weekly-compliance"
      schedule           = "cron(0 5 ? * SUN *)"
      cold_storage_after = 30
      delete_after       = 120
      recovery_point_tags = {
        "backup-frequency" = "weekly"
      }
    }
  ]

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
  source = "../../../terraform-aws-backup-alerting"

  solution_prefix = "team-payments-dev"

  kms_key_ids     = [module.backup.kms_key_id]
  email_endpoints = ["team-payments-dev@pagopa.it"]

  tags = {
    "backup-owner" = "team-payments"
    "Environment"  = "dev"
  }
}
