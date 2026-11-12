mock_provider "aws" {
  source = "../terraform-aws-backup/tests/mocks"
  mock_data "aws_region" {
    defaults = { name = "eu-south-1" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_resource "aws_lambda_function" {
    defaults = { arn = "arn:aws:lambda:eu-south-1:123456789012:function:test-alerts" }
  }
  mock_resource "aws_dynamodb_table" {
    defaults = { arn = "arn:aws:dynamodb:eu-south-1:123456789012:table/test-alerts" }
  }
}

variables {
  solution_prefix                 = "test-alerts"
  coverage_expected_resource_tags = { workload = "orders" }
  coverage_resource_types         = ["DynamoDB", "S3"]
  coverage_policy = {
    max_backup_age_seconds      = 86400
    freshness_tolerance_seconds = 3600
    initial_grace_seconds       = 86400
    reminder_interval_seconds   = 86400
    schedule                    = "rate(15 minutes)"
  }
}

run "default_activation_preserves_event_alerts" {
  command = apply
  assert {
    condition     = length(module.backup_coverage) == 1 && output.coverage_lambda_function_arn != null && length(aws_cloudwatch_event_rule.backup_failures) == 1 && length(aws_cloudwatch_event_rule.kms_deletion) == 1
    error_message = "Default-enabled coverage must coexist with the existing event alert resources."
  }
  assert {
    condition     = output.coverage_incident_table_arn != null && length(output.coverage_health_alarm_arns) == 5
    error_message = "Integrated coverage must expose state and health alarms."
  }
}

run "complete_opt_out_without_inputs" {
  command = plan
  variables {
    enable_backup_coverage          = false
    coverage_expected_resource_tags = {}
    coverage_resource_types         = []
    coverage_policy                 = null
  }
  assert {
    condition     = length(module.backup_coverage) == 0 && output.coverage_lambda_function_arn == null && output.coverage_incident_table_arn == null && output.coverage_health_alarm_arns == null && length(aws_cloudwatch_event_rule.backup_failures) == 1
    error_message = "One toggle must completely disable coverage without changing existing event alerts."
  }
}

run "default_requires_explicit_configuration" {
  command = plan
  variables {
    coverage_expected_resource_tags = {}
    coverage_resource_types         = []
    coverage_policy                 = null
  }
  expect_failures = [terraform_data.coverage_configuration]
}

run "owned_publisher_policy_inputs" {
  command = apply
  assert {
    condition = (
      contains([for s in data.aws_iam_policy_document.sns_kms[0].statement : s.sid], "AllowCoveragePublisherUseOfKey") &&
      contains([for s in data.aws_iam_policy_document.sns_kms[0].statement : s.sid], "AllowCoverageHealthAlarmsUseOfKey") &&
      contains([for s in data.aws_iam_policy_document.sns_topic_policy.statement : s.sid], "AllowCoverageHealthAlarmsPublish")
    )
    error_message = "Owned topic/key policy inputs must include the exact Lambda publisher and account-scoped health alarm grants."
  }
}

run "supplied_topic_and_key_remain_unmanaged" {
  command = apply
  variables {
    create_sns_topic       = false
    existing_sns_topic_arn = "arn:aws:sns:eu-south-1:123456789012:existing-alerts"
    sns_kms_key_arn        = "arn:aws:kms:eu-south-1:123456789012:key/00000000-0000-0000-0000-000000000001"
  }
  assert {
    condition     = length(aws_kms_key.sns) == 0 && length(aws_sns_topic_policy.backup_alerts) == 0 && output.coverage_lambda_function_arn != null && output.sns_kms_key_arn == null
    error_message = "Coverage must use supplied topic/key inputs without taking policy ownership or changing the existing key-output contract."
  }
}
