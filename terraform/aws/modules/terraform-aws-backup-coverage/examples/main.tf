terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.72.0, < 6.0.0"
    }
  }
}

provider "aws" { region = "eu-south-1" }

locals {
  expected_tags = { backup-workload = "orders-prod" }
  policy = {
    max_backup_age_seconds      = 86400
    freshness_tolerance_seconds = 3600
    initial_grace_seconds       = 86400
    reminder_interval_seconds   = 86400
    schedule                    = "rate(15 minutes)"
  }
}

module "standalone" {
  source                 = "../"
  solution_prefix        = "orders-standalone-eu-south-1"
  expected_resource_tags = local.expected_tags
  resource_types         = ["DynamoDB", "S3"]
  coverage_policy        = local.policy
  sns_topic_arn          = "arn:aws:sns:eu-south-1:123456789012:existing-alerts"
  sns_kms_key_arn        = "arn:aws:kms:eu-south-1:123456789012:key/00000000-0000-0000-0000-000000000001"
}

module "integrated" {
  source                          = "../../terraform-aws-backup-alerting"
  solution_prefix                 = "orders-integrated-eu-south-1"
  coverage_expected_resource_tags = local.expected_tags
  coverage_resource_types         = ["DynamoDB", "S3"]
  coverage_policy                 = local.policy
}

module "disabled" {
  source          = "../"
  solution_prefix = "orders-disabled-eu-south-1"
  enabled         = false
}
