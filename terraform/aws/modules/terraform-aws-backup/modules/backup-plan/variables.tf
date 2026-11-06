###############################################################################
# backup-plan — reusable AWS Backup plan + tag-based selection
#
# This is the single place where an aws_backup_plan and its aws_backup_selection
# are defined. It is consumed by:
#   - the core module, for the default plan
#   - the preset wrappers (hourly-backup, long-retention, archival, weekly-full)
#   - product teams directly, for bespoke extra plans
###############################################################################

variable "plan_name" {
  description = "Name of the backup plan. Also used as a prefix for the selection name."
  type        = string
}

variable "selection_name" {
  description = "Name of the backup selection. Defaults to \"<plan_name>-selection\"."
  type        = string
  default     = null
}

variable "iam_role_arn" {
  description = "ARN of the IAM role AWS Backup assumes to run the plan (usually the backup role from the core module)."
  type        = string
}

variable "selection_tags" {
  description = "Tag key/value pairs used to select resources for this plan. Combined (OR) with resource_types and resource_arns when those are set."
  type        = map(string)
  default     = {}
}

variable "resource_types" {
  description = <<-EOT
    Optional list of AWS service types to select ALL of their resources via
    wildcard ARNs (e.g. ["DynamoDB", "S3", "RDS"]). An alternative to tag-based
    selection.

    The set of supported types is defined by the resource_type_arns map in
    locals.tf (currently: S3, DynamoDB, EC2, EBS, RDS, Aurora, EFS). To add a
    new type, add a single entry to that map.
    Note: AWS Backup allows at most 30 wildcard ARNs per selection.
  EOT
  type        = list(string)
  default     = []
}

variable "resource_arns" {
  description = "Optional list of explicit resource ARNs (or wildcard ARNs) to select. Combined (OR) with resource_types and selection_tags."
  type        = list(string)
  default     = []
}

variable "excluded_resource_arns" {
  description = "Optional list of resource ARNs (or wildcard ARNs) to exclude from selection (not_resources). Useful to exclude ephemeral resources when selecting by service type."
  type        = list(string)
  default     = []
}

variable "rules" {
  description = <<-EOT
    List of backup rules for the plan. Each rule supports lifecycle, continuous
    backup and cross-region copy actions. Optional attributes fall back to
    sensible defaults.
  EOT
  type = list(object({
    rule_name                = string
    target_vault_name        = string
    schedule                 = string
    start_window             = optional(number, 480)
    completion_window        = optional(number, 960)
    enable_continuous_backup = optional(bool, false)
    cold_storage_after       = optional(number, 0)
    delete_after             = number
    recovery_point_tags      = optional(map(string), {})
    copy_actions = optional(list(object({
      destination_vault_arn = string
      cold_storage_after    = optional(number, 0)
      delete_after          = number
    })), [])
  }))

  validation {
    condition     = length(var.rules) > 0
    error_message = "At least one rule must be provided."
  }
}

variable "tags" {
  description = "Tags applied to the backup plan."
  type        = map(string)
  default     = {}
}
