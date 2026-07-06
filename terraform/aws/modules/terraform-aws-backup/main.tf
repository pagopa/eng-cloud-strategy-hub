###############################################################################
# Backup Vault — Primary Region
###############################################################################

resource "aws_backup_vault" "primary" {
  name        = var.solution_prefix
  kms_key_arn = aws_kms_key.backup.arn
  tags = merge(local.common_tags, {
    Name = "${local.tag_prefix}-vault"
  })
}

###############################################################################
# Vault Lock
###############################################################################

resource "aws_backup_vault_lock_configuration" "primary" {
  backup_vault_name   = aws_backup_vault.primary.name
  changeable_for_days = local.vault_lock_mode == "COMPLIANCE" ? var.vault_lock_changeable_for_days : null
  min_retention_days  = local.vault_lock_min_retention_days
  max_retention_days  = var.vault_lock_max_retention_days

  lifecycle {
    precondition {
      condition     = local.retention_days >= local.vault_lock_min_retention_days
      error_message = "retention_days (${local.retention_days}) must be >= the Vault Lock minimum retention (${local.vault_lock_min_retention_days}). Increase retention_days or lower vault_lock_min_retention_days."
    }

    precondition {
      condition     = local.cold_storage_after == 0 || local.retention_days >= local.cold_storage_after + 90
      error_message = "When cold_storage_after is set, retention_days (${local.retention_days}) must be at least cold_storage_after + 90 (${local.cold_storage_after + 90}). AWS Backup requires recovery points to stay in cold storage for at least 90 days."
    }

    precondition {
      condition     = !local.is_prod || var.dr_region != null
      error_message = "dr_region must be set when environment is prod, because production always enables the DR region configuration."
    }

    precondition {
      condition = alltrue([
        for rule in var.default_plan_additional_rules :
        try(rule.copy_to_dr, null) != true || local.enable_cross_region_copy
      ])
      error_message = "default_plan_additional_rules[*].copy_to_dr can be true only in prod, where the module enables the DR region configuration by default."
    }

    precondition {
      condition = alltrue([
        for rule in var.default_plan_additional_rules :
        (
          try(rule.copy_cold_storage_after, null) == null &&
          try(rule.copy_delete_after, null) == null
        ) || coalesce(try(rule.copy_to_dr, null), local.enable_cross_region_copy)
      ])
      error_message = "default_plan_additional_rules copy_cold_storage_after and copy_delete_after require DR copy to be enabled for that rule."
    }
  }
}

###############################################################################
# Backup Vault — DR Region (if cross-region copy is enabled)
###############################################################################

resource "aws_backup_vault" "dr" {
  count = local.enable_cross_region_copy ? 1 : 0

  provider = aws.dr

  name        = "${var.solution_prefix}-dr"
  kms_key_arn = aws_kms_key.backup_dr[0].arn
  tags = merge(local.common_tags, {
    Name = "${local.tag_prefix}-dr-vault"
  })
}

resource "aws_backup_vault_lock_configuration" "dr" {
  count = local.enable_cross_region_copy ? 1 : 0

  provider = aws.dr

  backup_vault_name   = aws_backup_vault.dr[0].name
  changeable_for_days = local.vault_lock_mode == "COMPLIANCE" ? var.vault_lock_changeable_for_days : null
  min_retention_days  = local.vault_lock_min_retention_days
  max_retention_days  = var.vault_lock_max_retention_days
}

###############################################################################
# Backup Plan — Default (via the reusable backup-plan sub-module)
###############################################################################

module "default_plan" {
  source = "./modules/backup-plan"

  plan_name      = "${var.solution_prefix}-default-plan"
  selection_name = "${var.solution_prefix}-selection"
  iam_role_arn   = aws_iam_role.backup.arn
  selection_tags = var.selection_tags
  tags           = local.common_tags

  resource_types         = var.resource_types
  resource_arns          = var.resource_arns
  excluded_resource_arns = var.excluded_resource_arns

  rules = local.default_plan_rules
}

###############################################################################
# Backup Plan — Continuous Backup (PITR), separate selection
#
# Created only when continuous_backup_selection_tags is set, so PITR runs only
# against supported, explicitly-tagged resources (DynamoDB, S3, RDS).
###############################################################################

module "continuous_plan" {
  count  = local.continuous_in_separate_plan ? 1 : 0
  source = "./modules/backup-plan"

  plan_name      = "${var.solution_prefix}-continuous-plan"
  selection_name = "${var.solution_prefix}-continuous-selection"
  iam_role_arn   = aws_iam_role.backup.arn
  selection_tags = var.continuous_backup_selection_tags
  tags           = local.common_tags

  rules = [
    {
      rule_name                = "continuous-backup"
      target_vault_name        = aws_backup_vault.primary.name
      schedule                 = var.backup_schedule
      start_window             = var.backup_window_minutes
      completion_window        = var.backup_window_minutes * 2
      enable_continuous_backup = true
      delete_after             = local.continuous_retention_days
      recovery_point_tags      = local.common_tags
    }
  ]
}
