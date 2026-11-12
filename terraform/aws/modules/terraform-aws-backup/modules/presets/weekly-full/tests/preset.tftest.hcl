mock_provider "aws" {}
variables {
  vault_name      = "test-weekly"
  backup_role_arn = "arn:aws:iam::123456789012:role/test-backup"
  selection_tags  = { workload = "orders" }
}
run "defaults" {
  command = apply
  assert {
    condition     = alltrue([for rule in module.plan.rules : rule.schedule == "cron(0 2 ? * SUN *)" && rule.lifecycle[0].delete_after == 90 && (rule.lifecycle[0].cold_storage_after == null || rule.lifecycle[0].cold_storage_after == 0)]) && alltrue([for tag in module.plan.selection_tags : tag.key == "workload" && tag.value == "orders"]) && length(module.plan.selection_tags) == 1
    error_message = "Weekly defaults must preserve schedule, retention, tags, and no cold transition."
  }
}
run "product_override" {
  command = apply
  variables {
    retention_days = 120
    schedule       = "cron(0 4 ? * SAT *)"
  }
  assert {
    condition     = alltrue([for rule in module.plan.rules : rule.lifecycle[0].delete_after == 120 && rule.schedule == var.schedule])
    error_message = "Weekly product overrides must reach the native plan."
  }
}

run "explicit_names_with_long_vault" {
  command = apply
  variables {
    vault_name     = "payments-prod-eu-south-1"
    plan_name      = "payments-weekly"
    selection_name = "payments-weekly-selection"
  }
  assert {
    condition     = alltrue([for rule in module.plan.rules : rule.target_vault_name == "payments-prod-eu-south-1"])
    error_message = "Explicit names must allow the existing vault name without truncation."
  }
}
