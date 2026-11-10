mock_provider "aws" {
  source = "tests/mocks"
  mock_data "aws_region" {
    defaults = { name = "eu-south-1" }
  }
}
mock_provider "aws" {
  alias  = "dr"
  source = "tests/mocks"
  mock_data "aws_region" {
    defaults = { name = "eu-central-1" }
  }
}

variables {
  aws_region      = "eu-south-1"
  dr_region       = "eu-central-1"
  environment     = "prod"
  solution_prefix = "test-defaults"
  selection_tags  = { backup-workload = "orders" }
}

run "production_defaults" {
  state_key = "production"
  command   = apply
  assert {
    condition     = aws_backup_vault_lock_configuration.primary.changeable_for_days == 3 && aws_backup_vault_lock_configuration.primary.min_retention_days == 30 && aws_backup_vault_lock_configuration.dr[0].changeable_for_days == 3 && aws_backup_vault_lock_configuration.dr[0].min_retention_days == 30
    error_message = "Production must default to COMPLIANCE and a fixed 30-day minimum on both vaults."
  }
  assert {
    condition     = length(module.default_plan.rules) == 1 && alltrue([for rule in module.default_plan.rules : rule.lifecycle[0].delete_after == 35 && !rule.enable_continuous_backup && length(rule.copy_action) == 1])
    error_message = "Production must retain snapshots and DR copies without implicit PITR."
  }
  assert {
    condition     = length(module.continuous_plan) == 0 && output.dr_vault_arn != null
    error_message = "PITR is opt-in; production DR is mandatory."
  }
}

run "nonproduction_defaults" {
  state_key = "nonproduction"
  command   = apply
  variables { environment = "nonprod" }
  assert {
    condition     = aws_backup_vault_lock_configuration.primary.changeable_for_days == null && aws_backup_vault_lock_configuration.primary.min_retention_days == 7 && alltrue([for rule in module.default_plan.rules : rule.lifecycle[0].delete_after == 14 && length(rule.copy_action) == 0])
    error_message = "Non-production must retain 14-day snapshots with GOVERNANCE, a fixed 7-day minimum and no DR."
  }
  assert {
    condition     = output.dr_vault_arn == null && length(module.continuous_plan) == 0
    error_message = "Non-production must not create DR or implicit PITR."
  }
}

run "production_governance_override" {
  command = apply
  variables { vault_lock_mode = "GOVERNANCE" }
  assert {
    condition     = aws_backup_vault_lock_configuration.primary.changeable_for_days == null && aws_backup_vault_lock_configuration.dr[0].changeable_for_days == null && aws_backup_vault_lock_configuration.primary.min_retention_days == 30 && aws_backup_vault_lock_configuration.dr[0].min_retention_days == 30
    error_message = "Production must allow explicit GOVERNANCE without changing either default minimum."
  }
}

run "reject_production_retention_below_default_minimum" {
  command = plan
  variables { retention_days = 29 }
  expect_failures = [aws_backup_vault_lock_configuration.primary, aws_backup_vault_lock_configuration.dr]
}

run "reject_nonproduction_retention_below_default_minimum" {
  command = plan
  variables {
    environment    = "nonprod"
    retention_days = 6
  }
  expect_failures = [aws_backup_vault_lock_configuration.primary]
}

run "missing_production_dr" {
  command = plan
  variables { dr_region = null }
  expect_failures = [aws_backup_vault_lock_configuration.primary]
}

run "same_primary_and_dr_region" {
  command = plan
  variables { dr_region = "eu-south-1" }
  expect_failures = [aws_backup_vault_lock_configuration.primary]
}

run "mismatched_primary_provider" {
  command = plan
  variables { aws_region = "eu-west-1" }
  expect_failures = [aws_backup_vault_lock_configuration.primary]
}

run "mismatched_dr_provider" {
  command = plan
  variables { dr_region = "eu-west-1" }
  expect_failures = [aws_backup_vault_lock_configuration.primary]
}

run "cross_account_dr_is_rejected" {
  command = plan
  override_data {
    target = data.aws_caller_identity.dr[0]
    values = { account_id = "210987654321" }
  }
  expect_failures = [aws_backup_vault_lock_configuration.primary]
}

run "pitr_requires_dedicated_tags" {
  command = plan
  variables { enable_continuous_backup = true }
  expect_failures = [aws_backup_vault_lock_configuration.primary]
}

run "pitr_rejects_empty_tags" {
  command = plan
  variables {
    enable_continuous_backup         = true
    continuous_backup_selection_tags = {}
  }
  expect_failures = [aws_backup_vault_lock_configuration.primary]
}

run "prepared_pitr_tags_do_not_enable_pitr" {
  command = apply
  variables { continuous_backup_selection_tags = { backup-pitr = "orders" } }
  assert {
    condition     = length(module.continuous_plan) == 0
    error_message = "Dedicated tags alone must not activate PITR."
  }
}

run "independent_pitr_retention" {
  command = apply
  variables {
    retention_days                   = 365
    enable_continuous_backup         = true
    continuous_backup_selection_tags = { backup-pitr = "orders" }
    continuous_retention_days        = 30
  }
  assert {
    condition     = alltrue([for rule in module.default_plan.rules : rule.lifecycle[0].delete_after == 365]) && alltrue([for rule in module.continuous_plan[0].rules : rule.lifecycle[0].delete_after == 30 && rule.enable_continuous_backup])
    error_message = "Snapshot and PITR retention must be independent and must not be silently capped."
  }
}

run "explicit_compliance" {
  command = apply
  variables {
    environment     = "nonprod"
    vault_lock_mode = "COMPLIANCE"
  }
  assert {
    condition     = aws_backup_vault_lock_configuration.primary.changeable_for_days == 3
    error_message = "COMPLIANCE must remain an explicit supported option."
  }
}

run "dr_vault_name_boundary" {
  command = apply
  variables {
    solution_prefix        = join("", [for index in range(47) : "a"])
    default_selection_name = "snapshot-selection"
  }
  assert {
    condition     = length(aws_backup_vault.dr[0].name) == 50
    error_message = "A generated DR vault name of exactly 50 characters must remain valid."
  }
}

run "reject_long_dr_vault_name" {
  command = plan
  variables {
    solution_prefix        = join("", [for index in range(48) : "a"])
    default_selection_name = "snapshot-selection"
  }
  expect_failures = [aws_backup_vault.dr]
}

run "explicit_dr_vault_name_preserves_primary" {
  command = apply
  variables {
    solution_prefix        = join("", [for index in range(50) : "a"])
    default_selection_name = "snapshot-selection"
    dr_vault_name          = "payments-dr"
  }
  assert {
    condition     = length(aws_backup_vault.primary.name) == 50 && aws_backup_vault.dr[0].name == "payments-dr"
    error_message = "An explicit DR name must not rename the primary vault."
  }
}
