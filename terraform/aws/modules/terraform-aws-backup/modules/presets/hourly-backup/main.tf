###############################################################################
# Preset: Hourly Backup
#
# Use case: low-RPO workloads that need a recovery point every hour.
# Thin wrapper over the backup-plan sub-module with opinionated defaults.
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
  description = "Tags to select resources for hourly backup. Typically more specific than the default plan."
  type        = map(string)
}

variable "retention_days" {
  description = "Retention for hourly recovery points."
  type        = number
  default     = 7
}

variable "schedule" {
  description = "Cron expression for hourly backup."
  type        = string
  default     = "cron(0 * * * ? *)"
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}

module "plan" {
  source = "../../backup-plan"

  plan_name      = "${var.vault_name}-hourly-plan"
  iam_role_arn   = var.backup_role_arn
  selection_tags = var.selection_tags
  tags           = var.tags

  rules = [
    {
      rule_name         = "hourly-backup"
      target_vault_name = var.vault_name
      schedule          = var.schedule
      start_window      = 60
      completion_window = 120
      delete_after      = var.retention_days
    }
  ]
}

output "plan_id" {
  value = module.plan.plan_id
}
