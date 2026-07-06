locals {
  is_prod = var.environment == "prod"

  # Tag Name prefix defaults to the solution prefix when not overridden.
  tag_prefix = coalesce(var.tag_identifier_prefix, var.solution_prefix)

  retention_days = coalesce(
    var.retention_days,
    local.is_prod ? 35 : 14
  )

  # Cold storage transition is OFF by default. It is a cost optimisation that
  # teams opt into explicitly (directly or via the archival / long-retention
  # templates), because AWS Backup requires delete_after >= cold_storage_after
  # + 90 days, which is incompatible with the light default retention.
  cold_storage_after = coalesce(
    var.cold_storage_after,
    0
  )

  # DR copy is mandatory in prod and disabled in nonprod.
  # cross_region_copy is kept only as a deprecated compatibility input.
  enable_cross_region_copy = local.is_prod

  enable_continuous_backup = coalesce(
    var.enable_continuous_backup,
    local.is_prod
  )

  vault_lock_mode = coalesce(
    var.vault_lock_mode,
    local.is_prod ? "COMPLIANCE" : "GOVERNANCE"
  )

  # Vault Lock minimum retention. Defaults are environment-aware and are kept
  # at or below the plan retention so the default plan never produces recovery
  # points that violate the lock (prod: 35, nonprod: 7).
  vault_lock_min_retention_days = coalesce(
    var.vault_lock_min_retention_days,
    local.is_prod ? 35 : 7
  )

  copy_retention_days = coalesce(
    var.copy_retention_days,
    local.retention_days
  )

  # Continuous backup (PITR) supports a maximum delete_after of 35 days.
  continuous_retention_days = min(local.retention_days, 35)

  # When a dedicated tag set is provided, continuous backup runs in its own
  # plan/selection (scoped to PITR-capable resources) instead of sharing the
  # main selection. This avoids FAILED continuous jobs on unsupported types.
  continuous_in_separate_plan = local.enable_continuous_backup && var.continuous_backup_selection_tags != null
  continuous_in_default_plan  = local.enable_continuous_backup && var.continuous_backup_selection_tags == null

  common_tags = merge(
    {
      "ManagedBy"   = "terraform"
      "Module"      = "terraform-aws-backup"
      "Environment" = var.environment
    },
    var.tags
  )

  default_plan_additional_rules = [
    for rule in var.default_plan_additional_rules : {
      rule_name         = rule.rule_name
      target_vault_name = aws_backup_vault.primary.name
      schedule          = rule.schedule

      start_window       = coalesce(rule.start_window, var.backup_window_minutes)
      completion_window  = coalesce(rule.completion_window, var.backup_window_minutes * 2)
      cold_storage_after = rule.cold_storage_after
      delete_after       = rule.delete_after

      recovery_point_tags = merge(local.common_tags, rule.recovery_point_tags)
      copy_actions = (try(rule.copy_to_dr, null) == null ? local.enable_cross_region_copy : rule.copy_to_dr) ? [
        {
          destination_vault_arn = aws_backup_vault.dr[0].arn
          cold_storage_after    = coalesce(rule.copy_cold_storage_after, rule.cold_storage_after)
          delete_after          = coalesce(rule.copy_delete_after, rule.delete_after)
        }
      ] : []
    }
  ]

  default_plan_rules = concat(
    [
      {
        rule_name           = "daily-backup"
        target_vault_name   = aws_backup_vault.primary.name
        schedule            = var.backup_schedule
        start_window        = var.backup_window_minutes
        completion_window   = var.backup_window_minutes * 2
        cold_storage_after  = local.cold_storage_after
        delete_after        = local.retention_days
        recovery_point_tags = local.common_tags
        copy_actions = local.enable_cross_region_copy ? [
          {
            destination_vault_arn = aws_backup_vault.dr[0].arn
            cold_storage_after    = local.cold_storage_after
            delete_after          = local.copy_retention_days
          }
        ] : []
      }
    ],
    local.continuous_in_default_plan ? [
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
    ] : [],
    local.default_plan_additional_rules
  )
}
