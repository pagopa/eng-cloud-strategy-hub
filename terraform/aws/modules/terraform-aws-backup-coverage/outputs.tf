output "lambda_function_arn" {
  description = "Coverage scanner Lambda ARN, or null when disabled."
  value       = var.enabled ? aws_lambda_function.coverage[0].arn : null
}
output "execution_role_arn" {
  description = "Publisher role ARN for caller-owned topic/key policies, or null when disabled."
  value       = var.enabled ? aws_iam_role.coverage[0].arn : null
}
output "incident_table_arn" {
  description = "Incident-state table ARN, or null when disabled."
  value       = var.enabled ? aws_dynamodb_table.incidents[0].arn : null
}
output "schedule_arn" {
  description = "Scanner schedule ARN, or null when disabled."
  value       = var.enabled ? aws_scheduler_schedule.coverage[0].arn : null
}
output "health_alarm_arns" {
  description = "Health alarm ARN map, or null when disabled."
  value       = var.enabled ? { for key, alarm in aws_cloudwatch_metric_alarm.health : key => alarm.arn } : null
}
