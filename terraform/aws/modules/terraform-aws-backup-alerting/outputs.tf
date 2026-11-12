###############################################################################
# Outputs
###############################################################################

output "sns_topic_arn" {
  description = "ARN of the SNS topic for backup alerts."
  value       = local.sns_topic_arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic. Null if using an existing topic."
  value       = var.create_sns_topic ? aws_sns_topic.backup_alerts[0].name : null
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for backup failures."
  value       = var.enable_backup_failure_alerts ? aws_cloudwatch_event_rule.backup_failures[0].arn : null
}

output "kms_deletion_rule_arn" {
  description = "ARN of the EventBridge rule for KMS key deletion alerts."
  value       = var.enable_kms_deletion_alert ? aws_cloudwatch_event_rule.kms_deletion[0].arn : null
}

output "sns_kms_key_arn" {
  description = "ARN of the customer-managed KMS key encrypting the SNS topic (the one created by this module, or the one passed in via sns_kms_key_arn). Null if no topic is created."
  value       = local.sns_kms_key_arn
}

output "coverage_lambda_function_arn" {
  description = "Independent coverage scanner ARN, or null when disabled."
  value       = length(module.backup_coverage) > 0 ? module.backup_coverage[0].lambda_function_arn : null
}

output "coverage_execution_role_arn" {
  description = "Coverage publisher role ARN for external policy owners, or null when disabled."
  value       = length(module.backup_coverage) > 0 ? module.backup_coverage[0].execution_role_arn : null
}

output "coverage_incident_table_arn" {
  description = "Coverage incident-state table ARN, or null when disabled."
  value       = length(module.backup_coverage) > 0 ? module.backup_coverage[0].incident_table_arn : null
}

output "coverage_health_alarm_arns" {
  description = "Coverage health alarm ARN map, or null when disabled."
  value       = length(module.backup_coverage) > 0 ? module.backup_coverage[0].health_alarm_arns : null
}
