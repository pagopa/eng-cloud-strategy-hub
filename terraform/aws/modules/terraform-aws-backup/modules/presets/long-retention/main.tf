###############################################################################
# Preset: Long Retention
#
# Use case: regulatory retention for payment trails and critical data
# (decision §7.3 — >= 10 years). Transitions to cold storage after 90 days to
# optimise cost. Thin wrapper over the backup-plan sub-module.
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
  description = "Tags to select resources for long-retention backup."
  type        = map(string)
}

variable "retention_days" {
  description = "Retention period in days. Defaults to 10 years."
  type        = number
  default     = 3650
}

variable "cold_storage_after" {
  description = "Days before transitioning to cold storage. Must be at least 90 days below retention_days."
  type        = number
  default     = 90
}

variable "schedule" {
  description = "Cron expression for the backup schedule."
  type        = string
  default     = "cron(0 2 * * ? *)"
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}

module "plan" {
  source = "../../backup-plan"

  plan_name      = "${var.vault_name}-long-retention-plan"
  iam_role_arn   = var.backup_role_arn
  selection_tags = var.selection_tags
  tags           = var.tags

  rules = [
    {
      rule_name          = "long-retention-daily"
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
