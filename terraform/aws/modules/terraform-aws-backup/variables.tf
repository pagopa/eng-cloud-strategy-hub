###############################################################################
# Required Variables
###############################################################################
variable "aws_region" {
  description = "Primary region where the workload lives. Used as the module's primary-region input and as the fallback region for the internal aws.dr alias when cross-region copy is disabled."
  type        = string
}

variable "environment" {
  description = "Environment type. Drives default behaviour for Vault Lock, cross-region copy, retention, etc."
  type        = string

  validation {
    condition     = contains(["prod", "nonprod"], var.environment)
    error_message = "environment must be 'prod' or 'nonprod'."
  }
}

variable "solution_prefix" {
  description = "Prefix for resources created by this solution (vault, IAM roles, KMS aliases, plans). Caution: changing this value may break execution as different AWS resources have different naming limits (e.g. no underscore for IAM roles)."
  type        = string
  default     = "backup-solution"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{2,50}$", var.solution_prefix))
    error_message = "solution_prefix must be 2-50 characters, alphanumeric plus hyphen and underscore only."
  }
}

variable "tag_identifier_prefix" {
  description = "Prefix for the Name tag applied to resources created by this solution. Defaults to solution_prefix."
  type        = string
  default     = null
}

###############################################################################
# Resource Selection
#
# Provide at least one of the following selectors. When several are set, AWS
# Backup includes a resource matching ANY of them (union):
#   - selection_tags  : tag-based selection (default method, decision §8)
#   - resource_types  : select all resources of a service type via wildcard ARNs
#   - resource_arns   : select explicit (or wildcard) ARNs
###############################################################################

variable "selection_tags" {
  description = "Map of tag key/value pairs used to select resources for the backup plan (default selection method, decision §8). Optional if resource_types or resource_arns are set."
  type        = map(string)
  default     = {}
}

variable "resource_types" {
  description = <<-EOT
    Optional list of AWS service types to back up by selecting ALL of their
    resources via wildcard ARNs (e.g. ["DynamoDB", "S3", "RDS"]), as an
    alternative or complement to tag-based selection.

    Supported types are defined by the resource_type_arns map in the backup-plan
    sub-module (currently: S3, DynamoDB, EC2, EBS, RDS, Aurora, EFS). Unsupported
    values are rejected with a clear error at plan time.
    Note: AWS Backup allows at most 30 wildcard ARNs per selection.
  EOT
  type        = list(string)
  default     = []
}

variable "resource_arns" {
  description = "Optional list of explicit (or wildcard) resource ARNs to select, combined with resource_types and selection_tags."
  type        = list(string)
  default     = []
}

variable "excluded_resource_arns" {
  description = "Optional list of resource ARNs (or wildcard ARNs) to exclude from the default plan selection. Useful to drop ephemeral resources when selecting by service type."
  type        = list(string)
  default     = []
}

###############################################################################
# Retention & Lifecycle
###############################################################################

variable "retention_days" {
  description = "Number of days to retain recovery points. Defaults to 35 in prod and 14 in nonprod. Must be >= the Vault Lock minimum retention."
  type        = number
  default     = null

  validation {
    condition     = var.retention_days == null ? true : var.retention_days >= 1
    error_message = "retention_days must be a positive number of days."
  }
}

variable "cold_storage_after" {
  description = "Number of days before transitioning recovery points to cold storage. 0 (default) disables the transition. When set, retention_days must be at least cold_storage_after + 90 (AWS Backup requirement)."
  type        = number
  default     = null

  validation {
    condition     = var.cold_storage_after == null ? true : var.cold_storage_after >= 0
    error_message = "cold_storage_after must be 0 (disabled) or a positive number of days."
  }
}

###############################################################################
# Cross-Region Copy
###############################################################################

variable "cross_region_copy" {
  description = <<-EOT
    Cross-region copy behaviour for disaster recovery. One of:
      - "Default"                 : enabled in prod, disabled in nonprod (per §4)
      - "DoNotCopyToOtherRegions" : never copy
      - "CopyToSecondaryRegion"   : copy to the DR region declared in dr_region
  EOT
  type        = string
  default     = "Default"

  validation {
    condition     = contains(["Default", "DoNotCopyToOtherRegions", "CopyToSecondaryRegion"], var.cross_region_copy)
    error_message = "cross_region_copy must be one of: Default, DoNotCopyToOtherRegions, CopyToSecondaryRegion."
  }
}

variable "dr_region" {
  description = "Target region for cross-region copy. Used both to configure the module's internal aws.dr alias and to validate against the DenyNoEURegions SCP allow-list. Required when cross_region_copy results in copying (i.e. not DoNotCopyToOtherRegions)."
  type        = string
  default     = null

  validation {
    condition     = var.dr_region == null ? true : contains(["eu-central-1", "eu-south-1", "eu-west-1", "eu-west-3"], var.dr_region)
    error_message = "dr_region must be one of the SCP-allowed EU regions: eu-central-1, eu-south-1, eu-west-1, eu-west-3."
  }
}

variable "copy_retention_days" {
  description = "Retention period for cross-region copies. Defaults to the primary retention_days."
  type        = number
  default     = null
}

###############################################################################
# Continuous Backup (PITR)
###############################################################################

variable "enable_continuous_backup" {
  description = "Enable continuous backup (Point-In-Time Recovery) for supported services (DynamoDB, S3, RDS)."
  type        = bool
  default     = null
}

variable "continuous_backup_selection_tags" {
  description = <<-EOT
    Optional dedicated tag set used to select resources for the continuous
    backup (PITR) rule. PITR is only supported by some services (DynamoDB, S3,
    RDS); selecting unsupported types (EFS, EKS, Redshift) produces FAILED jobs.
    When set, continuous backup runs in its own plan/selection scoped to these
    tags. When null (default), the continuous rule shares the main selection_tags.
  EOT
  type        = map(string)
  default     = null
}

###############################################################################
# Vault Lock
###############################################################################

variable "vault_lock_mode" {
  description = "Vault Lock mode: COMPLIANCE or GOVERNANCE. Defaults to COMPLIANCE in prod, GOVERNANCE in nonprod."
  type        = string
  default     = null

  validation {
    condition     = var.vault_lock_mode == null ? true : contains(["COMPLIANCE", "GOVERNANCE"], var.vault_lock_mode)
    error_message = "vault_lock_mode must be 'COMPLIANCE' or 'GOVERNANCE'."
  }
}

variable "vault_lock_min_retention_days" {
  description = "Minimum retention enforced by Vault Lock. Recovery points cannot have a retention shorter than this. Defaults to 35 in prod and 7 in nonprod."
  type        = number
  default     = null
}

variable "vault_lock_max_retention_days" {
  description = "Maximum retention in days enforced by Vault Lock. Recovery points cannot have a retention longer than this. Backup jobs targeting the vault must set delete_after within [vault_lock_min_retention_days, vault_lock_max_retention_days]; jobs outside this range are rejected by the vault."
  type        = number
  default     = 3650

  validation {
    condition     = var.vault_lock_max_retention_days >= 1
    error_message = "vault_lock_max_retention_days must be a positive number of days."
  }
}

variable "vault_lock_changeable_for_days" {
  description = "Cooling-off period in days during which the Vault Lock can still be removed (Compliance mode only). Minimum 3."
  type        = number
  default     = 3

  validation {
    condition     = var.vault_lock_changeable_for_days >= 3
    error_message = "vault_lock_changeable_for_days must be at least 3 (AWS minimum for Compliance mode)."
  }
}

###############################################################################
# Backup Schedule
###############################################################################

variable "backup_schedule" {
  description = "Cron expression for the backup schedule."
  type        = string
  default     = "cron(0 1 * * ? *)"
}

variable "backup_window_minutes" {
  description = "Duration of the backup window in minutes."
  type        = number
  default     = 480
}

variable "default_plan_additional_rules" {
  description = <<-EOT
    Optional scheduled rules appended to the default backup plan. Use this
    when the same selection of resources needs extra schedules or retention
    policies without creating a separate backup-plan module.

    These rules reuse the core module's primary vault, default selection, and
    backup IAM role. For separate selections or fully custom plans, use the
    backup-plan sub-module or one of the preset wrappers instead.
  EOT
  type = list(object({
    rule_name               = string
    schedule                = string
    start_window            = optional(number)
    completion_window       = optional(number)
    cold_storage_after      = optional(number, 0)
    delete_after            = number
    recovery_point_tags     = optional(map(string), {})
    copy_to_dr              = optional(bool)
    copy_cold_storage_after = optional(number)
    copy_delete_after       = optional(number)
  }))
  default = []

  validation {
    condition = alltrue([
      for rule in var.default_plan_additional_rules : !contains([
        "daily-backup",
        "continuous-backup"
      ], rule.rule_name)
    ])
    error_message = "default_plan_additional_rules cannot reuse reserved rule names: daily-backup, continuous-backup."
  }

  validation {
    condition     = length(var.default_plan_additional_rules) == length(distinct([for rule in var.default_plan_additional_rules : rule.rule_name]))
    error_message = "default_plan_additional_rules rule_name values must be unique."
  }
}

###############################################################################
# Restore Testing
###############################################################################

variable "enable_restore_testing" {
  description = "Whether to create a Restore Testing Plan."
  type        = bool
  default     = false
}

variable "restore_testing_schedule" {
  description = "Cron expression for restore testing schedule."
  type        = string
  default     = "cron(0 3 ? * SAT *)"
}

variable "restore_testing_start_window" {
  description = "Start window for restore testing in minutes."
  type        = number
  default     = 480
}

variable "restore_testing_max_duration" {
  description = "Hours a restored test resource is retained so optional validation can run (validation_window_hours). Between 1 and 168."
  type        = number
  default     = 24

  validation {
    condition     = var.restore_testing_max_duration >= 1 && var.restore_testing_max_duration <= 168
    error_message = "restore_testing_max_duration must be between 1 and 168 hours."
  }
}

variable "restore_testing_resource_types" {
  description = "Protected resource types to include in the Restore Testing Plan selections (e.g., DynamoDB, EBS, RDS, S3, EFS, Redshift). One selection is created per type."
  type        = list(string)
  default     = ["DynamoDB", "EBS", "RDS", "S3", "EFS"]
}

###############################################################################
# KMS
###############################################################################

variable "kms_deletion_window_in_days" {
  description = "Waiting period in days before KMS key deletion. Between 7 and 30."
  type        = number
  default     = 30

  validation {
    condition     = var.kms_deletion_window_in_days >= 7 && var.kms_deletion_window_in_days <= 30
    error_message = "kms_deletion_window_in_days must be between 7 and 30 days."
  }
}

variable "kms_enable_key_rotation" {
  description = "Enable automatic annual key rotation."
  type        = bool
  default     = true
}

variable "kms_multi_region" {
  description = "Whether the backup CMKs are multi-region keys. Multi-region keys simplify cross-region DR restore (the same key material exists in the DR region). Cannot be changed after key creation. See decision §6.3 (KMS key protection)."
  type        = bool
  default     = false
}

###############################################################################
# Tags
###############################################################################

variable "tags" {
  description = "Additional tags to apply to all resources created by the module."
  type        = map(string)
  default     = {}
}
