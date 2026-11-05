mock_provider "aws" {
  source = "../terraform-aws-backup/tests/mocks"
}
variables { solution_prefix = "test-alerts" }
run "new_topic_and_key" {
  command = apply
  assert {
    condition     = length(aws_sns_topic.backup_alerts) == 1 && length(aws_kms_key.sns) == 1 && length(aws_sns_topic_policy.backup_alerts) == 1
    error_message = "Owned topics must create encryption and their managed policy."
  }
}
run "supplied_topic_unmanaged_policy" {
  command = apply
  variables {
    create_sns_topic       = false
    existing_sns_topic_arn = "arn:aws:sns:eu-south-1:123456789012:existing-alerts"
  }
  assert {
    condition     = length(aws_sns_topic.backup_alerts) == 0 && length(aws_kms_key.sns) == 0 && length(aws_sns_topic_policy.backup_alerts) == 0 && output.sns_topic_arn == var.existing_sns_topic_arn
    error_message = "A supplied topic must retain its caller-managed policy by default."
  }
}
run "supplied_topic_managed_policy" {
  command = apply
  variables {
    create_sns_topic             = false
    existing_sns_topic_arn       = "arn:aws:sns:eu-south-1:123456789012:existing-alerts"
    manage_existing_topic_policy = true
  }
  assert {
    condition     = length(aws_sns_topic_policy.backup_alerts) == 1
    error_message = "Supplied topic policy ownership must require explicit opt-in."
  }
}
run "missing_supplied_topic" {
  command = plan
  variables {
    create_sns_topic = false
  }
  expect_failures = [data.aws_iam_policy_document.sns_topic_policy]
}
run "empty_supplied_topic" {
  command = plan
  variables {
    create_sns_topic       = false
    existing_sns_topic_arn = ""
  }
  expect_failures = [data.aws_iam_policy_document.sns_topic_policy]
}
run "missing_supplied_topic_with_subscriptions" {
  command = plan
  variables {
    create_sns_topic = false
    email_endpoints  = ["alerts@example.com"]
  }
  expect_failures = [data.aws_iam_policy_document.sns_topic_policy]
}
run "deduplicated_endpoints" {
  command = apply
  variables {
    email_endpoints   = ["alerts@example.com", "alerts@example.com"]
    webhook_endpoints = ["https://alerts.example.com/webhook", "https://alerts.example.com/webhook"]
    sqs_endpoints     = ["arn:aws:sqs:eu-south-1:123456789012:test-alerts", "arn:aws:sqs:eu-south-1:123456789012:test-alerts"]
    lambda_endpoints  = ["arn:aws:lambda:eu-south-1:123456789012:function:test-alerts", "arn:aws:lambda:eu-south-1:123456789012:function:test-alerts"]
  }
  assert {
    condition     = length(aws_sns_topic_subscription.email) == 1 && length(aws_sns_topic_subscription.webhook) == 1 && length(aws_sns_topic_subscription.sqs) == 1 && length(aws_sns_topic_subscription.lambda) == 1
    error_message = "Every endpoint collection must deduplicate subscriptions."
  }
}
run "disabled_rules" {
  command = apply
  variables {
    enable_backup_failure_alerts = false
    enable_kms_deletion_alert    = false
  }
  assert {
    condition     = length(aws_cloudwatch_event_rule.backup_failures) == 0 && length(aws_cloudwatch_event_rule.kms_deletion) == 0
    error_message = "Disabled alerts must not create EventBridge rules."
  }
}
run "supplied_key_and_event_filters" {
  command = apply
  variables {
    sns_kms_key_arn             = "arn:aws:kms:eu-south-1:123456789012:key/00000000-0000-0000-0000-000000000002"
    kms_key_ids                 = ["test-key"]
    backup_failure_event_states = ["FAILED"]
    monitored_event_types       = ["Copy Job State Change"]
  }
  assert {
    condition     = length(aws_kms_key.sns) == 0 && aws_sns_topic.backup_alerts[0].kms_master_key_id == var.sns_kms_key_arn
    error_message = "A supplied encryption key must not create another key."
  }
  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.backup_failures[0].event_pattern).detail.state == ["FAILED"] && jsondecode(aws_cloudwatch_event_rule.backup_failures[0].event_pattern)["detail-type"] == ["Copy Job State Change"] && jsondecode(aws_cloudwatch_event_rule.kms_deletion[0].event_pattern).detail.requestParameters.keyId == ["test-key"]
    error_message = "EventBridge must preserve configured state, event-type, and KMS-key filters."
  }
}
