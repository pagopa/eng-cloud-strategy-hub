output "plan_id" {
  description = "ID of the backup plan."
  value       = aws_backup_plan.this.id
}

output "plan_arn" {
  description = "ARN of the backup plan."
  value       = aws_backup_plan.this.arn
}

output "selection_id" {
  description = "ID of the backup selection."
  value       = aws_backup_selection.this.id
}
