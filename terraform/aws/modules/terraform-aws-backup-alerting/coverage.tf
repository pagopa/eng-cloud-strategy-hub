locals {
  coverage_configured = length(var.coverage_expected_resource_tags) > 0 && length(var.coverage_resource_types) > 0 && var.coverage_policy != null
}

resource "terraform_data" "coverage_configuration" {
  count = var.enable_backup_coverage ? 1 : 0
  lifecycle {
    precondition {
      condition     = local.coverage_configured
      error_message = "Default-enabled coverage requires coverage_expected_resource_tags, coverage_resource_types and coverage_policy. Set enable_backup_coverage=false for event-only alerting."
    }
  }
}

module "backup_coverage" {
  count  = var.enable_backup_coverage && local.coverage_configured ? 1 : 0
  source = "../terraform-aws-backup-coverage"

  solution_prefix        = var.solution_prefix
  expected_resource_tags = var.coverage_expected_resource_tags
  resource_types         = var.coverage_resource_types
  coverage_policy        = var.coverage_policy
  sns_topic_arn          = local.sns_topic_arn
  sns_kms_key_arn        = var.create_sns_topic ? local.sns_kms_key_arn : var.sns_kms_key_arn
  tags                   = local.common_tags
  depends_on             = [terraform_data.coverage_configuration, aws_sns_topic_policy.backup_alerts]
}
