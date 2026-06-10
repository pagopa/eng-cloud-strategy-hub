###############################################################################
# Example: Select resources by service type (instead of tags)
#
# As an alternative to tag-based selection (decision §8 default), this account
# backs up ALL resources of the listed service types via wildcard ARNs. Useful
# in a single-workload account where "back up everything of these types" is the
# intent. Ephemeral resources can be excluded with excluded_resource_arns.
#
# Note: AWS Backup allows at most 30 wildcard ARNs per selection.
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

  environment     = "prod"
  solution_prefix = "team-payments-vault"

  # Select by service type rather than tags. selection_tags is omitted.
  resource_types = ["DynamoDB", "RDS", "Aurora", "S3"]

  # Drop known ephemeral resources from the type-wide selection.
  excluded_resource_arns = [
    "arn:aws:dynamodb:eu-south-1:123456789012:table/tmp-*",
  ]

  dr_region = "eu-central-1"

  tags = {
    "backup-owner" = "team-payments"
  }
}

module "backup_alerting" {
  source = "git::https://github.com/pagopa/<repo-name>.git//modules/backup-alerting?ref=v1.0.0"

  solution_prefix = "team-payments"
  kms_key_ids     = [module.backup.kms_key_id]
  email_endpoints = ["team-payments-oncall@pagopa.it"]
}

###############################################################################
# Combined: service types AND tags (union) — back up all DynamoDB plus anything
# explicitly tagged, in one selection.
###############################################################################

# module "backup_combined" {
#   source = "git::https://github.com/pagopa/<repo-name>.git//modules/backup?ref=v1.0.0"
#   providers = { aws = aws, aws.dr = aws.dr }
#
#   environment     = "prod"
#   solution_prefix = "team-mixed-vault"
#   resource_types  = ["DynamoDB"]
#   selection_tags  = { "backup-policy" = "enabled" }
#   dr_region       = "eu-central-1"
# }

output "vault_arn" {
  value = module.backup.vault_arn
}
