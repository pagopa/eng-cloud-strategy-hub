###############################################################################
# Example: Email alerting (default topic)
#
# Snippet showing the alerting module's inputs. `module.backup` refers to the
# core terraform-aws-backup module deployed in the same configuration.
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
# Example: Alerting with existing SNS topic (no Chatbot)
###############################################################################

module "backup_alerting_simple" {
  source = "git::https://github.com/pagopa/<repo-name>.git//modules/backup-alerting?ref=v1.0.0"

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

###############################################################################
# Example: Alerting with Grafana webhook
###############################################################################

module "backup_alerting_grafana" {
  source = "git::https://github.com/pagopa/<repo-name>.git//modules/backup-alerting?ref=v1.0.0"

  solution_prefix = "team-platform"

  webhook_endpoints = ["https://grafana.internal.pagopa.it/api/alertmanager/webhook"]

  email_endpoints = ["team-platform-oncall@pagopa.it"]

  tags = {
    "backup-owner" = "team-platform"
  }
}
