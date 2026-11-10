mock_provider "aws" {
  source = "tests/mocks"
  mock_data "aws_region" {
    defaults = { name = "eu-south-1" }
  }
}
mock_provider "aws" {
  alias  = "dr"
  source = "tests/mocks"
}
variables {
  aws_region                     = "eu-south-1"
  environment                    = "nonprod"
  solution_prefix                = "test-selection"
  selection_tags                 = { backup-workload = "orders" }
  enable_restore_testing         = true
  restore_testing_resource_types = ["DynamoDB"]
}
run "single_tag_restore_scope" {
  command = apply
  assert {
    condition     = length(aws_backup_restore_testing_selection.this["DynamoDB"].protected_resource_arns) == 0 && aws_backup_restore_testing_selection.this["DynamoDB"].protected_resource_conditions[0].string_equals[0].key == "aws:ResourceTag/backup-workload"
    error_message = "Tag-based restore testing must use conditions without a wildcard ARN selector."
  }
}
run "explicit_arn_restore_scope" {
  command = apply
  variables {
    selection_tags = {}
    resource_arns  = ["arn:aws:dynamodb:eu-south-1:123456789012:table/orders"]
  }
  assert {
    condition     = aws_backup_restore_testing_selection.this["DynamoDB"].protected_resource_arns == toset(var.resource_arns)
    error_message = "Explicit ARN selection must never become all resources."
  }
}
run "reject_multi_tag_restore_and_conversion" {
  command = plan
  variables { selection_tags = { workload = "orders", stage = "prod" } }
  expect_failures = [aws_backup_restore_testing_plan.this]
}
run "reject_restore_exclusions" {
  command = plan
  variables { excluded_resource_arns = ["arn:aws:dynamodb:eu-south-1:123456789012:table/excluded"] }
  expect_failures = [aws_backup_restore_testing_plan.this]
}
run "reject_restore_mixed_selectors" {
  command = plan
  variables { resource_arns = ["arn:aws:dynamodb:eu-south-1:123456789012:table/orders"] }
  expect_failures = [aws_backup_restore_testing_plan.this]
}
run "reject_restore_implicit_type_wildcard" {
  command = plan
  variables {
    selection_tags = {}
    resource_types = ["DynamoDB"]
  }
  expect_failures = [aws_backup_restore_testing_plan.this]
}
run "generic_multiple_tags_remain_supported" {
  command = apply
  variables {
    enable_restore_testing = false
    selection_tags         = { workload = "orders", stage = "prod" }
  }
  assert {
    condition     = length(module.default_plan.selection_tags) == 2
    error_message = "Generic backup tag selection must keep its existing OR semantics."
  }
}

run "reject_restore_wildcard_arn" {
  command = plan
  variables {
    selection_tags = {}
    resource_arns  = ["arn:aws:dynamodb:eu-south-1:123456789012:table/*"]
  }
  expect_failures = [aws_backup_restore_testing_plan.this]
}

run "reject_restore_above_arn_limit" {
  command = plan
  variables {
    selection_tags = {}
    resource_arns  = [for index in range(31) : "arn:aws:dynamodb:eu-south-1:123456789012:table/orders-${index}"]
  }
  expect_failures = [aws_backup_restore_testing_plan.this]
}

run "restore_exact_arn_limit" {
  command = apply
  variables {
    selection_tags = {}
    resource_arns  = [for index in range(30) : "arn:aws:dynamodb:eu-south-1:123456789012:table/orders-${index}"]
  }
  assert {
    condition     = aws_backup_restore_testing_selection.this["DynamoDB"].protected_resource_arns == toset(var.resource_arns)
    error_message = "The 30-ARN boundary must retain the exact resource scope."
  }
}

run "reject_restore_without_resource_types" {
  command = plan
  variables { restore_testing_resource_types = [] }
  expect_failures = [aws_backup_restore_testing_plan.this]
}

run "reject_unsupported_restore_type" {
  command = plan
  variables { restore_testing_resource_types = ["Unsupported"] }
  expect_failures = [var.restore_testing_resource_types]
}

run "restore_metadata_is_scoped_by_resource_type" {
  command = apply
  variables {
    restore_testing_resource_types = ["RDS", "DynamoDB"]
    restore_testing_metadata_overrides = {
      RDS = {
        DBSubnetGroupName   = "restore-test-subnets"
        VpcSecurityGroupIds = "[\"sg-0123456789abcdef0\"]"
      }
    }
  }
  assert {
    condition     = try(aws_backup_restore_testing_selection.this["RDS"].restore_metadata_overrides["DBSubnetGroupName"] == "restore-test-subnets" && aws_backup_restore_testing_selection.this["RDS"].restore_metadata_overrides["VpcSecurityGroupIds"] == "[\"sg-0123456789abcdef0\"]", false)
    error_message = "RDS restore parameters must reach its selection unchanged."
  }
  assert {
    condition     = !contains(keys(aws_backup_restore_testing_selection.this["DynamoDB"].restore_metadata_overrides), "DBSubnetGroupName")
    error_message = "RDS overrides must not leak into another resource type."
  }
}

run "explicit_names_preserve_long_prefix" {
  command = apply
  variables {
    solution_prefix                  = "payments-production-backup-eu-south-1-long"
    default_selection_name           = "payments-snapshot"
    enable_continuous_backup         = true
    continuous_backup_selection_tags = { backup-pitr = "orders" }
    continuous_selection_name        = "payments-continuous"
    restore_testing_plan_name        = "payments_restore_test"
    restore_testing_selection_names  = { DynamoDB = "payments_dynamodb" }
  }
  assert {
    condition     = aws_backup_vault.primary.name == "payments-production-backup-eu-south-1-long" && aws_backup_restore_testing_plan.this[0].name == "payments_restore_test" && aws_backup_restore_testing_selection.this["DynamoDB"].name == "payments_dynamodb"
    error_message = "Name overrides must preserve the physical vault name and reach restore resources."
  }
}

run "reject_unused_restore_metadata_type" {
  command = plan
  variables { restore_testing_metadata_overrides = { RDS = { DBSubnetGroupName = "restore-subnets" } } }
  expect_failures = [aws_backup_restore_testing_plan.this]
}

run "restore_name_boundary" {
  command = apply
  variables { solution_prefix = join("", [for index in range(37) : "a"]) }
  assert {
    condition     = length(aws_backup_restore_testing_plan.this[0].name) == 50
    error_message = "A generated restore plan name of exactly 50 characters must remain valid."
  }
}

run "reject_long_restore_plan_name" {
  command = plan
  variables { solution_prefix = join("", [for index in range(38) : "a"]) }
  expect_failures = [aws_backup_restore_testing_plan.this]
}

run "restore_selection_name_boundary" {
  command = apply
  variables {
    solution_prefix           = join("", [for index in range(41) : "a"])
    default_selection_name    = "snapshot-selection"
    restore_testing_plan_name = "restore_test"
  }
  assert {
    condition     = length(aws_backup_restore_testing_selection.this["DynamoDB"].name) == 50
    error_message = "A generated restore selection name of exactly 50 characters must remain valid."
  }
}

run "reject_long_restore_selection_name" {
  command = plan
  variables {
    solution_prefix           = join("", [for index in range(42) : "a"])
    default_selection_name    = "snapshot-selection"
    restore_testing_plan_name = "restore_test"
  }
  expect_failures = [aws_backup_restore_testing_selection.this]
}

run "reject_duplicate_restore_names" {
  command = plan
  variables {
    restore_testing_resource_types  = ["RDS", "DynamoDB"]
    restore_testing_selection_names = { RDS = "same_selection", DynamoDB = "same_selection" }
  }
  expect_failures = [aws_backup_restore_testing_plan.this]
}

run "reject_fractional_restore_window" {
  command = plan
  variables { restore_testing_start_window = 90 }
  expect_failures = [var.restore_testing_start_window]
}

run "reject_restore_window_above_limit" {
  command = plan
  variables { restore_testing_start_window = 10140 }
  expect_failures = [var.restore_testing_start_window]
}

run "reject_fractional_restore_duration" {
  command = plan
  variables { restore_testing_max_duration = 1.5 }
  expect_failures = [var.restore_testing_max_duration]
}
