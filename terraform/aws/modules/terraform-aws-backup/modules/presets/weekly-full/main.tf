###############################################################################
# Preset: Weekly Full Backup
#
# Use case: a guaranteed weekly recovery point alongside the daily plan.
# Thin wrapper over the backup-plan sub-module.
###############################################################################

variable "vault_name" {
  description = "Name of the existing backup vault (from the core module)."
  type        = string
}

variable "plan_name" {
  description = "Optional explicit plan name. Defaults to <vault_name>-weekly-full-plan."
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
  description = "Tags to select resources for weekly full backup."
  type        = map(string)
}

variable "retention_days" {
  description = "Retention for weekly recovery points."
  type        = number
  default     = 90
}

variable "schedule" {
  description = "Cron expression for the weekly backup (default: Sunday 02:00 UTC)."
  type        = string
  default     = "cron(0 2 ? * SUN *)"
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}

module "plan" {
  source = "../../backup-plan"

  plan_name      = coalesce(var.plan_name, "${var.vault_name}-weekly-full-plan")
  selection_name = var.selection_name
  iam_role_arn   = var.backup_role_arn
  selection_tags = var.selection_tags
  tags           = var.tags

  rules = [
    {
      rule_name         = "weekly-full"
      target_vault_name = var.vault_name
      schedule          = var.schedule
      delete_after      = var.retention_days
    }
  ]
}

output "plan_id" {
  value = module.plan.plan_id
}
