mock_provider "aws" {}
variables {
  vault_name      = "test-hourly"
  backup_role_arn = "arn:aws:iam::123456789012:role/test-backup"
  selection_tags  = { workload = "orders" }
}
run "defaults" {
  command = apply
  assert {
    condition     = alltrue([for rule in module.plan.rules : rule.schedule == "cron(0 * * * ? *)" && rule.lifecycle[0].delete_after == 7 && (rule.lifecycle[0].cold_storage_after == null || rule.lifecycle[0].cold_storage_after == 0)]) && length(module.plan.selection_tags) == 1 && alltrue([for tag in module.plan.selection_tags : tag.key == "workload" && tag.value == "orders"])
    error_message = "Hourly defaults must retain 7 days and pass the selector without cold storage."
  }
}
run "product_override" {
  command = apply
  variables {
    retention_days = 35
    schedule       = "cron(0 */2 * * ? *)"
  }
  assert {
    condition     = alltrue([for rule in module.plan.rules : rule.lifecycle[0].delete_after == 35 && rule.schedule == var.schedule])
    error_message = "Hourly product retention and schedule overrides must reach the native plan."
  }
}
