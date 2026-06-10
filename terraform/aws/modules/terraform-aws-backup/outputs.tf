###############################################################################
# Outputs
###############################################################################

output "vault_arn" {
  description = "ARN of the primary backup vault."
  value       = aws_backup_vault.primary.arn
}

output "vault_name" {
  description = "Name of the primary backup vault."
  value       = aws_backup_vault.primary.name
}

output "dr_vault_arn" {
  description = "ARN of the DR backup vault. Null if cross-region copy is disabled."
  value       = local.enable_cross_region_copy ? aws_backup_vault.dr[0].arn : null
}

output "backup_plan_id" {
  description = "ID of the default backup plan."
  value       = module.default_plan.plan_id
}

output "backup_plan_arn" {
  description = "ARN of the default backup plan."
  value       = module.default_plan.plan_arn
}

output "continuous_plan_id" {
  description = "ID of the dedicated continuous-backup plan. Null unless continuous_backup_selection_tags is set."
  value       = local.continuous_in_separate_plan ? module.continuous_plan[0].plan_id : null
}

output "backup_role_arn" {
  description = "ARN of the IAM role used by AWS Backup for backup operations."
  value       = aws_iam_role.backup.arn
}

output "restore_role_arn" {
  description = "ARN of the IAM role used by AWS Backup for restore operations."
  value       = aws_iam_role.restore.arn
}

output "kms_key_arn" {
  description = "ARN of the KMS key encrypting the primary vault."
  value       = aws_kms_key.backup.arn
}

output "kms_key_id" {
  description = "ID of the KMS key encrypting the primary vault."
  value       = aws_kms_key.backup.key_id
}

output "dr_kms_key_arn" {
  description = "ARN of the KMS key encrypting the DR vault. Null if cross-region copy is disabled."
  value       = local.enable_cross_region_copy ? aws_kms_key.backup_dr[0].arn : null
}

output "dr_kms_key_id" {
  description = "ID of the KMS key encrypting the DR vault. Null if cross-region copy is disabled. Pass to the alerting module to monitor the DR key for deletion."
  value       = local.enable_cross_region_copy ? aws_kms_key.backup_dr[0].key_id : null
}

output "restore_testing_plan_arn" {
  description = "ARN of the Restore Testing Plan. Null if restore testing is disabled."
  value       = var.enable_restore_testing ? aws_backup_restore_testing_plan.this[0].arn : null
}
