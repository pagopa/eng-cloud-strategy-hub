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

variable "plan_name" {
  description = "Optional explicit plan name. Defaults to <vault_name>-archival-plan."
  type        = string
  default     = null
}

variable "selection_name" {
  description = "Optional explicit selection name. Defaults to <plan_name>-selection; the final name must use 1-50 letters, digits, underscores, periods or hyphens."
  type        = string
  default     = null
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

  plan_name      = coalesce(var.plan_name, "${var.vault_name}-archival-plan")
  selection_name = var.selection_name
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
