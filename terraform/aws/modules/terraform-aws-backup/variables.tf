###############################################################################
# Required Variables
###############################################################################
variable "aws_region" {
  description = "Primary region where the workload lives. Must match the caller-supplied aws provider."
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

variable "default_selection_name" {
  description = "Explicit snapshot selection name. Defaults to <solution_prefix>-selection; the final name must fit the AWS 50-character limit. Changing an existing name may replace the selection."
  type        = string
  default     = null
}

variable "continuous_selection_name" {
  description = "Explicit PITR selection name. Defaults to <solution_prefix>-continuous-selection; the final name must fit the AWS 50-character limit."
  type        = string
  default     = null
}

variable "dr_vault_name" {
  description = "Explicit DR vault name. Defaults to <solution_prefix>-dr. Changing an existing name replaces the vault."
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
    Aurora uses the broad RDS cluster ARN pattern, not an engine filter. For
    Aurora-only scope, omit resource_types and use exact cluster resource_arns
    or a dedicated selection tag; selectors combine as a union, not AND.
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
    condition     = var.retention_days == null ? true : var.retention_days >= 1 && floor(var.retention_days) == var.retention_days
    error_message = "retention_days must be a positive whole number of days."
  }
}

variable "cold_storage_after" {
  description = "Number of days before transitioning recovery points to cold storage. 0 (default) disables the transition. When set, retention_days must be at least cold_storage_after + 90 (AWS Backup requirement)."
  type        = number
  default     = null

  validation {
    condition     = var.cold_storage_after == null ? true : var.cold_storage_after >= 0 && floor(var.cold_storage_after) == var.cold_storage_after
    error_message = "cold_storage_after must be a non-negative whole number of days; 0 disables transition."
  }
}

###############################################################################
# Cross-Region Copy
###############################################################################

# Retained as a deprecated compatibility input for existing callers.
# tflint-ignore: terraform_unused_declarations
variable "cross_region_copy" {
  description = <<-EOT
    Deprecated compatibility input. The module no longer uses this variable to
    decide whether DR copy is enabled.

    Current behaviour:
      - prod    : DR copy is enabled by default and requires dr_region
      - nonprod : DR copy is disabled
  EOT
  type        = string
  default     = "Default"

  validation {
    condition     = contains(["Default", "DoNotCopyToOtherRegions", "CopyToSecondaryRegion"], var.cross_region_copy)
    error_message = "cross_region_copy must be one of: Default, DoNotCopyToOtherRegions, CopyToSecondaryRegion."
  }
}

variable "dr_region" {
  description = "Target region for production DR copy. Must differ from aws_region, match the caller's aws.dr provider, and belong to the existing EU allow-list."
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
  validation {
    condition     = var.copy_retention_days == null ? true : var.copy_retention_days >= 1 && floor(var.copy_retention_days) == var.copy_retention_days
    error_message = "copy_retention_days must be a positive whole number of days."
  }
}

###############################################################################
# Continuous Backup (PITR)
###############################################################################

variable "enable_continuous_backup" {
  description = "Enable dedicated AWS Backup continuous backup for supported S3 and RDS/Aurora resources. Disabled by default. DynamoDB PITR is configured natively by the caller."
  type        = bool
  default     = null
}

variable "continuous_backup_selection_tags" {
  description = <<-EOT
    Dedicated, non-empty tags required when continuous backup is enabled.
    Continuous backup always uses its own selection; it never falls back to
    snapshot tags. Tag matches use OR, so each tag must identify only supported
    S3 or RDS/Aurora resources. DynamoDB PITR is separate native configuration.
  EOT
  type        = map(string)
  default     = null
}

variable "continuous_retention_days" {
  description = "Independent AWS Backup PITR retention in whole days, from 1 to 35."
  type        = number
  default     = 35
  validation {
    condition     = var.continuous_retention_days >= 1 && var.continuous_retention_days <= 35 && floor(var.continuous_retention_days) == var.continuous_retention_days
    error_message = "continuous_retention_days must be a whole number from 1 to 35; retention is never silently capped."
  }
}

###############################################################################
# Vault Lock
###############################################################################

variable "vault_lock_mode" {
  description = "Vault Lock mode: defaults to COMPLIANCE in prod and GOVERNANCE in nonprod. Either mode may be explicitly selected in either environment. COMPLIANCE becomes immutable after its cooling-off period."
  type        = string
  default     = null

  validation {
    condition     = var.vault_lock_mode == null ? true : contains(["COMPLIANCE", "GOVERNANCE"], var.vault_lock_mode)
    error_message = "vault_lock_mode must be 'COMPLIANCE' or 'GOVERNANCE'."
  }
}

variable "vault_lock_min_retention_days" {
  description = "Explicit minimum retention for both vaults. When null, the fixed minimum is 30 days in prod and 7 in nonprod; shorter plan retention never lowers it automatically. External plans remain caller-owned."
  type        = number
  default     = null
  validation {
    condition     = var.vault_lock_min_retention_days == null ? true : var.vault_lock_min_retention_days >= 1 && floor(var.vault_lock_min_retention_days) == var.vault_lock_min_retention_days
    error_message = "vault_lock_min_retention_days must be a positive whole number of days."
  }
}

variable "vault_lock_max_retention_days" {
  description = "Maximum retention in days enforced by Vault Lock. Recovery points cannot have a retention longer than this. Backup jobs targeting the vault must set delete_after within [vault_lock_min_retention_days, vault_lock_max_retention_days]; jobs outside this range are rejected by the vault."
  type        = number
  default     = 3650

  validation {
    condition     = var.vault_lock_max_retention_days >= 1 && floor(var.vault_lock_max_retention_days) == var.vault_lock_max_retention_days
    error_message = "vault_lock_max_retention_days must be a positive whole number of days."
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

  validation {
    condition     = var.backup_window_minutes >= 60 && floor(var.backup_window_minutes) == var.backup_window_minutes
    error_message = "backup_window_minutes must be at least 60 whole minutes."
  }
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

  validation {
    condition     = var.restore_testing_start_window >= 60 && var.restore_testing_start_window <= 10080 && var.restore_testing_start_window % 60 == 0
    error_message = "restore_testing_start_window must be a whole number of hours expressed in minutes, from 60 to 10080 (1-168 hours)."
  }
}

variable "restore_testing_max_duration" {
  description = "Hours a restored test resource is retained so optional validation can run (validation_window_hours). Between 1 and 168."
  type        = number
  default     = 24

  validation {
    condition     = var.restore_testing_max_duration >= 1 && var.restore_testing_max_duration <= 168 && floor(var.restore_testing_max_duration) == var.restore_testing_max_duration
    error_message = "restore_testing_max_duration must be a whole number between 1 and 168 hours."
  }
}

variable "restore_testing_resource_types" {
  description = "Protected resource types to include in the Restore Testing Plan selections (e.g., DynamoDB, EBS, RDS, S3, EFS, Redshift). One selection is created per type."
  type        = list(string)
  default     = ["DynamoDB", "EBS", "RDS", "S3", "EFS"]

  validation {
    condition     = alltrue([for resource_type in var.restore_testing_resource_types : contains(["Aurora", "DocumentDB", "DynamoDB", "EBS", "EC2", "EFS", "FSx", "Neptune", "RDS", "Redshift", "S3"], resource_type)])
    error_message = "restore_testing_resource_types supports Aurora, DocumentDB, DynamoDB, EBS, EC2, EFS, FSx, Neptune, RDS, Redshift and S3."
  }
}

variable "restore_testing_plan_name" {
  description = "Explicit restore testing plan name. Defaults to <solution_prefix with hyphens replaced by underscores>_restore_test. Names must use 1-50 letters, digits or underscores."
  type        = string
  default     = null
}

variable "restore_testing_selection_names" {
  description = "Optional restore selection names keyed by protected resource type. Unspecified types retain <normalized solution_prefix>_<lowercase type>. Names must use 1-50 letters, digits or underscores."
  type        = map(string)
  default     = {}
}

variable "restore_testing_metadata_overrides" {
  description = "Restore metadata string maps keyed by selected resource type, for example RDS = { DBSubnetGroupName = \"restore-subnets\" }. Values replace AWS-inferred metadata only for that selection. Encode structured values with jsonencode when required by AWS."
  type        = map(map(string))
  default     = {}
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
