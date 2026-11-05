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
  solution_prefix = "test-lifecycle"
  selection_tags  = { backup-workload = "orders" }
}
run "seven_day_product_override" {
  command = apply
  variables { retention_days = 7 }
  assert {
    condition     = aws_backup_vault_lock_configuration.primary.min_retention_days == 7 && aws_backup_vault_lock_configuration.dr[0].min_retention_days == 7
    error_message = "Automatic lock minima must allow the actual product retention."
  }
}
run "zero_retention" {
  command = plan
  variables { retention_days = 0 }
  expect_failures = [var.retention_days]
}
run "negative_retention" {
  command = plan
  variables { retention_days = -1 }
  expect_failures = [var.retention_days]
}
run "fractional_retention" {
  command = plan
  variables { retention_days = 1.5 }
  expect_failures = [var.retention_days]
}
run "pitr_above_limit" {
  command = plan
  variables { continuous_retention_days = 36 }
  expect_failures = [var.continuous_retention_days]
}
run "pitr_zero" {
  command = plan
  variables { continuous_retention_days = 0 }
  expect_failures = [var.continuous_retention_days]
}
run "pitr_fractional" {
  command = plan
  variables { continuous_retention_days = 2.5 }
  expect_failures = [var.continuous_retention_days]
}
run "minimum_above_maximum" {
  command = plan
  variables {
    vault_lock_min_retention_days = 40
    vault_lock_max_retention_days = 35
  }
  expect_failures = [aws_backup_vault_lock_configuration.primary, aws_backup_vault_lock_configuration.dr]
}
run "primary_above_maximum" {
  command = plan
  variables {
    retention_days                = 36
    copy_retention_days           = 35
    vault_lock_max_retention_days = 35
  }
  expect_failures = [aws_backup_vault_lock_configuration.primary]
}
run "extra_rule_below_explicit_minimum" {
  command = plan
  variables {
    vault_lock_min_retention_days = 14
    default_plan_additional_rules = [{
      rule_name    = "short"
      schedule     = "cron(0 5 * * ? *)"
      delete_after = 7
      copy_to_dr   = false
    }]
  }
  expect_failures = [aws_backup_vault_lock_configuration.primary]
}
run "copy_above_destination_maximum" {
  command = plan
  variables {
    copy_retention_days           = 36
    vault_lock_max_retention_days = 35
  }
  expect_failures = [aws_backup_vault_lock_configuration.dr]
}
run "copy_below_destination_minimum" {
  command = plan
  variables {
    copy_retention_days           = 7
    vault_lock_min_retention_days = 14
  }
  expect_failures = [aws_backup_vault_lock_configuration.dr]
}
run "cold_storage_requires_ninety_days" {
  command = plan
  variables {
    cold_storage_after  = 30
    retention_days      = 119
    copy_retention_days = 120
  }
  expect_failures = [aws_backup_vault_lock_configuration.primary]
}
run "copy_lifecycle_without_copy" {
  command = plan
  variables {
    default_plan_additional_rules = [{
      rule_name         = "no-copy"
      schedule          = "cron(0 5 * * ? *)"
      delete_after      = 35
      copy_to_dr        = false
      copy_delete_after = 35
    }]
  }
  expect_failures = [aws_backup_vault_lock_configuration.primary]
}
run "distinct_vault_minima" {
  command = apply
  variables {
    retention_days      = 365
    copy_retention_days = 90
    default_plan_additional_rules = [{
      rule_name    = "short-primary"
      schedule     = "cron(0 5 * * ? *)"
      delete_after = 7
      copy_to_dr   = false
    }]
  }
  assert {
    condition     = aws_backup_vault_lock_configuration.primary.min_retention_days == 7 && aws_backup_vault_lock_configuration.dr[0].min_retention_days == 35
    error_message = "DR minima must use copy rules only, not primary-only rules."
  }
}

run "negative_additional_retention" {
  command = plan
  variables {
    default_plan_additional_rules = [{
      rule_name    = "invalid-primary"
      schedule     = "cron(0 5 * * ? *)"
      delete_after = -1
      copy_to_dr   = false
    }]
  }
  expect_failures = [aws_backup_vault_lock_configuration.primary]
}

run "fractional_additional_retention" {
  command = plan
  variables {
    default_plan_additional_rules = [{
      rule_name    = "invalid-primary"
      schedule     = "cron(0 5 * * ? *)"
      delete_after = 1.5
      copy_to_dr   = false
    }]
  }
  expect_failures = [aws_backup_vault_lock_configuration.primary]
}

run "negative_additional_copy_retention" {
  command = plan
  variables {
    default_plan_additional_rules = [{
      rule_name         = "invalid-copy"
      schedule          = "cron(0 5 * * ? *)"
      delete_after      = 35
      copy_delete_after = -1
    }]
  }
  expect_failures = [aws_backup_vault_lock_configuration.dr]
}

run "pitr_below_explicit_minimum" {
  command = plan
  variables {
    enable_continuous_backup         = true
    continuous_backup_selection_tags = { backup-pitr = "orders" }
    continuous_retention_days        = 7
    vault_lock_min_retention_days    = 14
  }
  expect_failures = [aws_backup_vault_lock_configuration.primary]
}

run "nonproduction_copy_is_rejected" {
  command = plan
  variables {
    environment = "nonprod"
    default_plan_additional_rules = [{
      rule_name    = "invalid-copy"
      schedule     = "cron(0 5 * * ? *)"
      delete_after = 35
      copy_to_dr   = true
    }]
  }
  expect_failures = [aws_backup_vault_lock_configuration.primary]
}
