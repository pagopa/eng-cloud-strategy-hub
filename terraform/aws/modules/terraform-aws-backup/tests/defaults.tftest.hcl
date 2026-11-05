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
  command = apply
  assert {
    condition     = aws_backup_vault_lock_configuration.primary.changeable_for_days == null && aws_backup_vault_lock_configuration.primary.min_retention_days == 35
    error_message = "Production must default to GOVERNANCE and 35-day retention."
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
  command = apply
  variables { environment = "nonprod" }
  assert {
    condition     = aws_backup_vault_lock_configuration.primary.changeable_for_days == null && alltrue([for rule in module.default_plan.rules : rule.lifecycle[0].delete_after == 14 && length(rule.copy_action) == 0])
    error_message = "Non-production must retain 14-day snapshots with GOVERNANCE and no DR."
  }
  assert {
    condition     = output.dr_vault_arn == null && length(module.continuous_plan) == 0
    error_message = "Non-production must not create DR or implicit PITR."
  }
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
    continuous_retention_days        = 21
  }
  assert {
    condition     = alltrue([for rule in module.default_plan.rules : rule.lifecycle[0].delete_after == 365]) && alltrue([for rule in module.continuous_plan[0].rules : rule.lifecycle[0].delete_after == 21 && rule.enable_continuous_backup])
    error_message = "Snapshot and PITR retention must be independent and must not be silently capped."
  }
}

run "explicit_compliance" {
  command = apply
  variables { vault_lock_mode = "COMPLIANCE" }
  assert {
    condition     = aws_backup_vault_lock_configuration.primary.changeable_for_days == 3
    error_message = "COMPLIANCE must remain an explicit supported option."
  }
}
