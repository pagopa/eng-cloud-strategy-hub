###############################################################################
# Example: Email alerting (default topic)
#
# Standalone alerting composition; callers supply the existing backup key IDs.
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.30.0, < 6.0.0"
    }
  }
}

provider "aws" {
  region = "eu-south-1"
}

module "backup_alerting" {
  source = "./.."

  solution_prefix = "team-payments"

  # Monitor the backup CMK for accidental deletion
  kms_key_ids = ["00000000-0000-0000-0000-000000000001"]

  # Email alerts
  email_endpoints = ["team-payments-oncall@pagopa.it"]

  tags = {
    "backup-owner" = "team-payments"
    "Environment"  = "prod"
  }
}

###############################################################################
# Example: Alerting with existing SNS topic (no Chatbot)
###############################################################################

module "backup_alerting_simple" {
  source = "./.."

  solution_prefix = "team-identity"

  # Use existing topic
  create_sns_topic       = false
  existing_sns_topic_arn = "arn:aws:sns:eu-south-1:123456789012:existing-alerts-topic"

  # Only email
  email_endpoints = ["team-identity-oncall@pagopa.it"]

  # Monitor specific KMS keys
  kms_key_ids = ["aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"]

  tags = {
    "backup-owner" = "team-identity"
  }
}
