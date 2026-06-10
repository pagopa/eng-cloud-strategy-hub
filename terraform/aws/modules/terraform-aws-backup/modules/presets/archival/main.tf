###############################################################################
# Preset: Archival
#
# Use case: cost-optimised long-term storage for archival data. Transitions to
# cold storage as early as allowed. Thin wrapper over the backup-plan sub-module.
#
# Note: AWS Backup requires delete_after >= cold_storage_after + 90, so the
# minimum viable retention for this preset is cold_storage_after + 90.
###############################################################################

variable "vault_name" {
  description = "Name of the existing backup vault (from the core module)."
  type        = string
}

variable "backup_role_arn" {
  description = "ARN of the backup IAM role (from the core module output)."
  type        = string
}

variable "selection_tags" {
  description = "Tags to select resources for archival backup."
  type        = map(string)
}

variable "retention_days" {
  description = "Retention period in days. Defaults to 10 years."
  type        = number
  default     = 3650
}

variable "cold_storage_after" {
  description = "Days before transitioning to cold storage."
  type        = number
  default     = 30
}

variable "schedule" {
  description = "Cron expression for the backup schedule."
  type        = string
  default     = "cron(0 3 * * ? *)"
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}

module "plan" {
  source = "../../backup-plan"

  plan_name      = "${var.vault_name}-archival-plan"
  iam_role_arn   = var.backup_role_arn
  selection_tags = var.selection_tags
  tags           = var.tags

  rules = [
    {
      rule_name          = "archival-daily"
      target_vault_name  = var.vault_name
      schedule           = var.schedule
      cold_storage_after = var.cold_storage_after
      delete_after       = var.retention_days
    }
  ]
}

output "plan_id" {
  value = module.plan.plan_id
}
