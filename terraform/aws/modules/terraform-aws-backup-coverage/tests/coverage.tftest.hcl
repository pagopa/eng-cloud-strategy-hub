mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_region" {
    defaults = { name = "eu-south-1" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/test-coverage" }
  }
  mock_resource "aws_lambda_function" {
    defaults = { arn = "arn:aws:lambda:eu-south-1:123456789012:function:test-coverage" }
  }
  mock_resource "aws_dynamodb_table" {
    defaults = { arn = "arn:aws:dynamodb:eu-south-1:123456789012:table/test-coverage" }
  }
}

variables {
  solution_prefix        = "test-coverage"
  sns_topic_arn          = "arn:aws:sns:eu-south-1:123456789012:alerts"
  sns_kms_key_arn        = "arn:aws:kms:eu-south-1:123456789012:key/00000000-0000-0000-0000-000000000001"
  expected_resource_tags = { workload = "orders" }
  resource_types         = ["DynamoDB", "S3"]
  coverage_policy = {
    max_backup_age_seconds      = 86400
    freshness_tolerance_seconds = 3600
    initial_grace_seconds       = 86400
    reminder_interval_seconds   = 86400
    schedule                    = "rate(15 minutes)"
  }
}

run "enabled_standalone_and_packaging" {
  command = apply
  assert {
    condition     = length(aws_lambda_function.coverage) == 1 && length(aws_scheduler_schedule.coverage) == 1 && length(aws_dynamodb_table.incidents) == 1 && length(aws_cloudwatch_log_group.coverage) == 1
    error_message = "Standalone coverage must create all scanner infrastructure."
  }
  assert {
    condition     = aws_lambda_function.coverage[0].reserved_concurrent_executions == 1 && aws_lambda_function.coverage[0].timeout == 300 && aws_lambda_function.coverage[0].runtime == "python3.12"
    error_message = "The incident state must have one bounded Lambda writer."
  }
  assert {
    condition     = fileexists(data.archive_file.coverage[0].output_path) && length(data.archive_file.coverage[0].output_base64sha256) == 44 && output.lambda_function_arn != null
    error_message = "The real archive provider must package the Lambda source."
  }
  assert {
    condition     = aws_cloudwatch_log_group.coverage[0].retention_in_days == 30 && aws_dynamodb_table.incidents[0].point_in_time_recovery[0].enabled
    error_message = "Logs must have bounded retention and incident state must have PITR."
  }
}

run "least_privilege_and_health" {
  command = apply
  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_role_policy.coverage[0].policy).Statement :
      !contains(s.Action, "s3:GetObject") && !contains(s.Action, "backup:StartBackupJob") && !contains(s.Action, "*")
    ])
    error_message = "Coverage must read inventory and backup metadata without workload data or mutation permissions."
  }
  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_role_policy.coverage[0].policy).Statement :
      s.Sid != "Publish" || s.Resource == [var.sns_topic_arn]
    ])
    error_message = "SNS publication must be scoped to the supplied topic."
  }
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.health) == 5 && aws_cloudwatch_metric_alarm.health["missing-success"].treat_missing_data == "breaching" && aws_cloudwatch_metric_alarm.health["missing-success"].evaluation_periods == 2
    error_message = "Health must detect failed, missing, empty, errored, and throttled scans."
  }
  assert {
    condition     = jsondecode(aws_iam_role.scheduler[0].assume_role_policy).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "123456789012"
    error_message = "Scheduler trust must be account-scoped."
  }
}

run "disabled_without_configuration" {
  command = plan
  variables {
    enabled                = false
    expected_resource_tags = {}
    resource_types         = []
    coverage_policy        = null
    sns_topic_arn          = null
    sns_kms_key_arn        = null
  }
  assert {
    condition     = length(aws_lambda_function.coverage) == 0 && length(aws_scheduler_schedule.coverage) == 0 && length(aws_dynamodb_table.incidents) == 0 && length(aws_iam_role.coverage) == 0 && length(aws_iam_role.scheduler) == 0 && length(aws_cloudwatch_log_group.coverage) == 0 && length(aws_cloudwatch_metric_alarm.health) == 0 && length(data.archive_file.coverage) == 0
    error_message = "Disabled standalone coverage must create no resources or package."
  }
  assert {
    condition     = output.lambda_function_arn == null && output.execution_role_arn == null && output.incident_table_arn == null && output.schedule_arn == null && output.health_alarm_arns == null
    error_message = "Every disabled resource output must be null."
  }
}

run "s3_only_inventory_permissions" {
  command = plan
  variables { resource_types = ["S3"] }
  assert {
    condition = (
      contains([for s in jsondecode(aws_iam_role_policy.coverage[0].policy).Statement : s.Sid], "S3Inventory") &&
      contains([for s in jsondecode(aws_iam_role_policy.coverage[0].policy).Statement : s.Sid], "S3Tags") &&
      !contains([for s in jsondecode(aws_iam_role_policy.coverage[0].policy).Statement : s.Sid], "DynamoDBInventory") &&
      !contains([for s in jsondecode(aws_iam_role_policy.coverage[0].policy).Statement : s.Sid], "DynamoDBTags")
    )
    error_message = "S3-only coverage must include both S3 inventory grants and no DynamoDB inventory grants."
  }
}

run "dynamodb_only_inventory_permissions" {
  command = plan
  variables { resource_types = ["DynamoDB"] }
  assert {
    condition = (
      contains([for s in jsondecode(aws_iam_role_policy.coverage[0].policy).Statement : s.Sid], "DynamoDBInventory") &&
      contains([for s in jsondecode(aws_iam_role_policy.coverage[0].policy).Statement : s.Sid], "DynamoDBTags") &&
      !contains([for s in jsondecode(aws_iam_role_policy.coverage[0].policy).Statement : s.Sid], "S3Inventory") &&
      !contains([for s in jsondecode(aws_iam_role_policy.coverage[0].policy).Statement : s.Sid], "S3Tags")
    )
    error_message = "DynamoDB-only coverage must include both DynamoDB inventory grants and no S3 inventory grants."
  }
}

run "missing_enabled_configuration" {
  command = plan
  variables {
    expected_resource_tags = {}
    resource_types         = []
    coverage_policy        = null
  }
  expect_failures = [terraform_data.configuration]
}

run "unsupported_discovery_type" {
  command = plan
  variables { resource_types = ["EC2"] }
  expect_failures = [terraform_data.configuration]
}

run "invalid_policy" {
  command = plan
  variables {
    coverage_policy = {
      max_backup_age_seconds      = 60
      freshness_tolerance_seconds = 60
      initial_grace_seconds       = -1
      reminder_interval_seconds   = 1
      schedule                    = "cron(0 * * * ? *)"
    }
  }
  expect_failures = [terraform_data.configuration]
}

run "foreign_topic" {
  command = plan
  variables { sns_topic_arn = "arn:aws:sns:eu-west-1:123456789012:alerts" }
  expect_failures = [terraform_data.configuration]
}

run "singular_hour_schedule" {
  command = plan
  variables {
    coverage_policy = {
      max_backup_age_seconds      = 86400
      freshness_tolerance_seconds = 0
      initial_grace_seconds       = 0
      reminder_interval_seconds   = 3600
      schedule                    = "rate(1 hour)"
    }
  }
  assert {
    condition     = aws_scheduler_schedule.coverage[0].schedule_expression == "rate(1 hour)"
    error_message = "A singular hourly schedule with explicit zero tolerances/grace must be supported."
  }
}

run "reject_inconsistent_schedule_plural" {
  command = plan
  variables {
    coverage_policy = {
      max_backup_age_seconds      = 86400
      freshness_tolerance_seconds = 0
      initial_grace_seconds       = 0
      reminder_interval_seconds   = 3600
      schedule                    = "rate(1 hours)"
    }
  }
  expect_failures = [terraform_data.configuration]
}

run "maximum_prefix_keeps_names_valid" {
  command = plan
  variables { solution_prefix = join("", [for _ in range(45) : "a"]) }
  assert {
    condition     = length(aws_lambda_function.coverage[0].function_name) <= 64 && length(aws_scheduler_schedule.coverage[0].name) <= 64 && length(aws_iam_role.scheduler[0].name) <= 64 && length(aws_iam_role.coverage[0].name) <= 64
    error_message = "The maximum accepted alerting prefix must keep coverage account-global names valid."
  }
}

run "missing_external_key" {
  command = plan
  variables { sns_kms_key_arn = null }
  expect_failures = [terraform_data.configuration]
}

run "reject_infrastructure_self_selection" {
  command = plan
  variables { tags = { workload = "orders" } }
  expect_failures = [terraform_data.configuration]
}

run "reject_oversized_runtime_configuration" {
  command = plan
  variables {
    expected_resource_tags = { workload = join("", [for _ in range(350) : "aaaaaaaaaa"]) }
  }
  assert {
    condition     = length(var.expected_resource_tags["workload"]) == 3500
    error_message = "The oversized configuration fixture must retain its 3500-character payload."
  }
  expect_failures = [terraform_data.configuration]
}
