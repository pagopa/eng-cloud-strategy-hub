terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.72.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "= 2.4.0"
    }
  }
}
provider "aws" { region = "eu-south-1" }
provider "aws" {
  alias  = "dr"
  region = "eu-central-1"
}
module "backup" {
  source = "../../.."
  providers = {
    aws    = aws
    aws.dr = aws.dr
  }
  aws_region      = "eu-south-1"
  dr_region       = "eu-central-1"
  environment     = "prod"
  solution_prefix = "test-provider-minimum"
  selection_tags  = { backup-workload = "minimum" }
}
module "alerting" {
  source                          = "../../../../terraform-aws-backup-alerting"
  solution_prefix                 = "test-provider-minimum"
  coverage_expected_resource_tags = { backup-workload = "minimum" }
  coverage_resource_types         = ["DynamoDB", "S3"]
  coverage_policy = {
    max_backup_age_seconds      = 86400
    freshness_tolerance_seconds = 3600
    initial_grace_seconds       = 86400
    reminder_interval_seconds   = 86400
    schedule                    = "rate(15 minutes)"
  }
}
