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

  # Cross-region copy: "Default" follows the per-environment rule (§4),
  # otherwise the explicit enum value wins.
  enable_cross_region_copy = (
    var.cross_region_copy == "Default" ? local.is_prod :
    var.cross_region_copy == "CopyToSecondaryRegion"
  )

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
}
