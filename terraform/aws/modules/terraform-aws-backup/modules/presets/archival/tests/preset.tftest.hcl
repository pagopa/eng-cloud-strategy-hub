mock_provider "aws" {}
variables {
  vault_name      = "test-archival"
  backup_role_arn = "arn:aws:iam::123456789012:role/test-backup"
  selection_tags  = { workload = "orders" }
}
run "defaults" {
  command = apply
  assert {
    condition     = alltrue([for rule in module.plan.rules : rule.schedule == "cron(0 3 * * ? *)" && rule.lifecycle[0].delete_after == 3650 && rule.lifecycle[0].cold_storage_after == 30]) && alltrue([for tag in module.plan.selection_tags : tag.key == "workload" && tag.value == "orders"]) && length(module.plan.selection_tags) == 1
    error_message = "Archival defaults must preserve schedule, retention, cold transition, and tags."
  }
}
run "product_override" {
  command = apply
  variables {
    retention_days     = 120
    cold_storage_after = 30
    schedule           = "cron(0 4 * * ? *)"
  }
  assert {
    condition     = alltrue([for rule in module.plan.rules : rule.lifecycle[0].delete_after == 120 && rule.lifecycle[0].cold_storage_after == 30 && rule.schedule == var.schedule])
    error_message = "Archival product overrides must reach the native plan."
  }
}
