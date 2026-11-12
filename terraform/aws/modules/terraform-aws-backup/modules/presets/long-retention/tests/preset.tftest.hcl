mock_provider "aws" {}
variables {
  vault_name      = "test-long"
  backup_role_arn = "arn:aws:iam::123456789012:role/test-backup"
  selection_tags  = { workload = "orders" }
}
run "defaults" {
  command = apply
  assert {
    condition     = alltrue([for rule in module.plan.rules : rule.schedule == "cron(0 2 * * ? *)" && rule.lifecycle[0].delete_after == 3650 && rule.lifecycle[0].cold_storage_after == 90]) && alltrue([for tag in module.plan.selection_tags : tag.key == "workload" && tag.value == "orders"]) && length(module.plan.selection_tags) == 1
    error_message = "Long-retention defaults must preserve schedule, retention, transition, and tags."
  }
}
run "product_override" {
  command = apply
  variables {
    retention_days     = 180
    cold_storage_after = 90
    schedule           = "cron(0 4 * * ? *)"
  }
  assert {
    condition     = alltrue([for rule in module.plan.rules : rule.lifecycle[0].delete_after == 180 && rule.lifecycle[0].cold_storage_after == 90 && rule.schedule == var.schedule])
    error_message = "Long-retention product overrides must reach the native plan."
  }
}

run "explicit_names_with_long_vault" {
  command = apply
  variables {
    vault_name     = "payments-prod-eu-south-1"
    plan_name      = "payments-long-retention"
    selection_name = "payments-long-retention-selection"
  }
  assert {
    condition     = alltrue([for rule in module.plan.rules : rule.target_vault_name == "payments-prod-eu-south-1"])
    error_message = "Explicit names must preserve the existing vault name."
  }
}
