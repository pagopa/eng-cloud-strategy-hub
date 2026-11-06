mock_provider "aws" {}
variables {
  plan_name      = "test-plan"
  iam_role_arn   = "arn:aws:iam::123456789012:role/test-backup"
  selection_tags = { workload = "orders", stage = "prod" }
  rules = [{
    rule_name         = "daily"
    target_vault_name = "test-vault"
    schedule          = "cron(0 1 * * ? *)"
    delete_after      = 35
  }]
}
run "mixed_selection_and_exclusions" {
  command = apply
  variables {
    resource_arns          = ["arn:aws:s3:::test-orders"]
    resource_types         = ["DynamoDB"]
    excluded_resource_arns = ["arn:aws:dynamodb:eu-south-1:123456789012:table/excluded"]
  }
  assert {
    condition     = length(aws_backup_selection.this.selection_tag) == 2 && contains(aws_backup_selection.this.resources, "arn:aws:s3:::test-orders") && contains(aws_backup_selection.this.resources, "arn:aws:dynamodb:*:*:table/*") && aws_backup_selection.this.not_resources == toset(var.excluded_resource_arns)
    error_message = "Native ListOfTags, ARN union, service wildcards, and exclusions must remain intact."
  }
}
run "missing_selection" {
  command = plan
  variables { selection_tags = {} }
  expect_failures = [aws_backup_selection.this]
}
run "unsupported_service" {
  command = plan
  variables { resource_types = ["Unsupported"] }
  expect_failures = [aws_backup_selection.this]
}
run "duplicate_rule_names" {
  command = plan
  variables {
    rules = [
      { rule_name = "daily", target_vault_name = "test-vault", schedule = "cron(0 1 * * ? *)", delete_after = 35 },
      { rule_name = "daily", target_vault_name = "test-vault", schedule = "cron(0 2 * * ? *)", delete_after = 35 }
    ]
  }
  expect_failures = [aws_backup_plan.this]
}
run "zero_retention" {
  command = plan
  variables {
    rules = [{ rule_name = "daily", target_vault_name = "test-vault", schedule = "cron(0 1 * * ? *)", delete_after = 0 }]
  }
  expect_failures = [aws_backup_plan.this]
}
run "fractional_retention" {
  command = plan
  variables {
    rules = [{ rule_name = "daily", target_vault_name = "test-vault", schedule = "cron(0 1 * * ? *)", delete_after = 1.5 }]
  }
  expect_failures = [aws_backup_plan.this]
}
run "cold_storage_boundary" {
  command = apply
  variables {
    rules = [{ rule_name = "archive", target_vault_name = "test-vault", schedule = "cron(0 1 * * ? *)", delete_after = 120, cold_storage_after = 30 }]
  }
  assert {
    condition     = alltrue([for rule in aws_backup_plan.this.rule : rule.lifecycle[0].delete_after == 120 && rule.lifecycle[0].cold_storage_after == 30])
    error_message = "Exactly 90 days after cold transition must remain valid."
  }
}
run "insufficient_cold_retention" {
  command = plan
  variables {
    rules = [{ rule_name = "archive", target_vault_name = "test-vault", schedule = "cron(0 1 * * ? *)", delete_after = 119, cold_storage_after = 30 }]
  }
  expect_failures = [aws_backup_plan.this]
}
run "continuous_above_limit" {
  command = plan
  variables {
    rules = [{ rule_name = "pitr", target_vault_name = "test-vault", schedule = "cron(0 1 * * ? *)", delete_after = 36, enable_continuous_backup = true }]
  }
  expect_failures = [aws_backup_plan.this]
}
run "continuous_cold_storage" {
  command = plan
  variables {
    rules = [{ rule_name = "pitr", target_vault_name = "test-vault", schedule = "cron(0 1 * * ? *)", delete_after = 35, cold_storage_after = 1, enable_continuous_backup = true }]
  }
  expect_failures = [aws_backup_plan.this]
}
run "invalid_copy_cold_storage" {
  command = plan
  variables {
    rules = [{
      rule_name    = "daily", target_vault_name = "test-vault", schedule = "cron(0 1 * * ? *)", delete_after = 35
      copy_actions = [{ destination_vault_arn = "arn:aws:backup:eu-central-1:123456789012:backup-vault:test-dr", cold_storage_after = 30, delete_after = 119 }]
    }]
  }
  expect_failures = [aws_backup_plan.this]
}
