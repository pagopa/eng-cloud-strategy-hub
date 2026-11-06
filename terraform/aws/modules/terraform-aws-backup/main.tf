###############################################################################
# Backup Vault — Primary Region
###############################################################################

data "aws_region" "primary" {}
data "aws_region" "dr" {
  count    = local.enable_cross_region_copy ? 1 : 0
  provider = aws.dr
}
data "aws_caller_identity" "dr" {
  count    = local.enable_cross_region_copy ? 1 : 0
  provider = aws.dr
}

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
      condition     = local.vault_lock_min_retention_days <= var.vault_lock_max_retention_days && alltrue([for days in local.primary_retention_days : days >= 1 && days >= local.vault_lock_min_retention_days && days <= var.vault_lock_max_retention_days && floor(days) == days])
      error_message = "Every primary snapshot, extra rule, and enabled PITR retention must be a positive whole day value within the primary Vault Lock bounds."
    }

    precondition {
      condition     = alltrue([for rule in local.default_plan_rules : rule.cold_storage_after >= 0 && floor(rule.cold_storage_after) == rule.cold_storage_after && (rule.cold_storage_after == 0 || rule.delete_after >= rule.cold_storage_after + 90)])
      error_message = "Every primary rule must use whole non-negative cold-storage days and retain at least 90 days after transition."
    }

    precondition {
      condition     = !local.is_prod || (var.dr_region != null && var.dr_region != var.aws_region)
      error_message = "Production requires dr_region to be set and different from aws_region."
    }
    precondition {
      condition     = data.aws_region.primary.name == var.aws_region
      error_message = "The caller's aws provider region must match aws_region."
    }
    precondition {
      condition     = local.is_prod ? data.aws_region.dr[0].name == var.dr_region && data.aws_caller_identity.dr[0].account_id == data.aws_caller_identity.current.account_id : true
      error_message = "Production aws.dr must match dr_region and use the same AWS account as aws."
    }
    precondition {
      condition     = !local.enable_continuous_backup || (var.continuous_backup_selection_tags == null ? false : length(var.continuous_backup_selection_tags) > 0)
      error_message = "Enabled continuous backup requires non-empty dedicated continuous_backup_selection_tags."
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
        ) || (try(rule.copy_to_dr, null) == null ? local.enable_cross_region_copy : rule.copy_to_dr)
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
  min_retention_days  = local.dr_vault_lock_min_retention_days
  max_retention_days  = var.vault_lock_max_retention_days

  lifecycle {
    precondition {
      condition     = local.dr_vault_lock_min_retention_days <= var.vault_lock_max_retention_days && alltrue([for days in local.dr_retention_days : days >= 1 && days >= local.dr_vault_lock_min_retention_days && days <= var.vault_lock_max_retention_days && floor(days) == days])
      error_message = "Every copy retention must be a positive whole day value within the destination Vault Lock bounds."
    }
    precondition {
      condition = alltrue(flatten([
        for rule in local.default_plan_rules : [
          for copy in rule.copy_actions : copy.cold_storage_after >= 0 && floor(copy.cold_storage_after) == copy.cold_storage_after && (copy.cold_storage_after == 0 || copy.delete_after >= copy.cold_storage_after + 90)
        ]
      ]))
      error_message = "Every copy lifecycle must use whole non-negative cold-storage days and retain at least 90 days after transition."
    }
  }
}

###############################################################################
# Backup Plan — Default (via the reusable backup-plan sub-module)
###############################################################################

module "default_plan" {
  source     = "./modules/backup-plan"
  depends_on = [aws_backup_vault_lock_configuration.primary, aws_backup_vault_lock_configuration.dr]

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
# Enabled explicitly and scoped to dedicated tags for supported S3/RDS resources.
###############################################################################

module "continuous_plan" {
  count      = local.continuous_in_separate_plan ? 1 : 0
  source     = "./modules/backup-plan"
  depends_on = [aws_backup_vault_lock_configuration.primary]

  plan_name      = "${var.solution_prefix}-continuous-plan"
  selection_name = "${var.solution_prefix}-continuous-selection"
  iam_role_arn   = aws_iam_role.backup.arn
  selection_tags = var.continuous_backup_selection_tags == null ? {} : var.continuous_backup_selection_tags
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
