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
