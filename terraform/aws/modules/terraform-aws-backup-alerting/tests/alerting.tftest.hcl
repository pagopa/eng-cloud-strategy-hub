mock_provider "aws" {
  source = "../terraform-aws-backup/tests/mocks"
}
variables {
  solution_prefix        = "test-alerts"
  enable_backup_coverage = false
}
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
    email_endpoints = ["alerts@example.com", "alerts@example.com"]
  }
  assert {
    condition     = length(aws_sns_topic_subscription.email) == 1 && aws_sns_topic_subscription.email["alerts@example.com"].protocol == "email"
    error_message = "Email endpoints must create deduplicated email subscriptions."
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
    condition = (
      jsonencode(jsondecode(aws_cloudwatch_event_rule.backup_failures[0].event_pattern).detail) == jsonencode({
        "$or" = [
          { state = ["FAILED"] },
          { status = ["FAILED"] },
        ]
      }) &&
      jsondecode(aws_cloudwatch_event_rule.backup_failures[0].event_pattern)["detail-type"] == ["Copy Job State Change"] &&
      jsonencode(jsondecode(aws_cloudwatch_event_rule.kms_deletion[0].event_pattern).detail.requestParameters.keyId) == jsonencode(["test-key", { suffix = "/test-key" }])
    )
    error_message = "EventBridge must preserve configured state, event-type, and KMS-key filters."
  }
}

run "backup_copy_and_restore_failure_fields" {
  command = plan
  assert {
    condition = jsonencode(jsondecode(aws_cloudwatch_event_rule.backup_failures[0].event_pattern)) == jsonencode({
      source      = ["aws.backup"]
      detail-type = ["Backup Job State Change", "Copy Job State Change", "Restore Job State Change"]
      detail = {
        "$or" = [
          { state = ["FAILED", "EXPIRED", "ABORTED"] },
          { status = ["FAILED", "EXPIRED", "ABORTED"] },
        ]
      }
    })
    error_message = "Backup/copy state and restore status must independently match failure states, without also requiring the other field."
  }
}

run "kms_identifiers_match_ids_and_arns" {
  command = plan
  variables {
    kms_key_ids = [
      "00000000-0000-0000-0000-000000000001",
      "arn:aws:kms:eu-south-1:123456789012:key/mrk-00000000000000000000000000000002",
    ]
  }
  assert {
    condition = jsonencode(jsondecode(aws_cloudwatch_event_rule.kms_deletion[0].event_pattern).detail) == jsonencode({
      eventName = ["ScheduleKeyDeletion", "DisableKey"]
      requestParameters = {
        keyId = [
          "00000000-0000-0000-0000-000000000001",
          "mrk-00000000000000000000000000000002",
          { suffix = "/00000000-0000-0000-0000-000000000001" },
          { suffix = "/mrk-00000000000000000000000000000002" },
        ]
      }
    })
    error_message = "Both KMS operations must match key-ID and key-ARN requests for configured IDs or ARNs, including multi-Region keys."
  }
}

run "maximum_solution_prefix" {
  command = plan
  variables {
    solution_prefix = join("", [for _ in range(45) : "a"])
  }
  assert {
    condition     = length(aws_cloudwatch_event_rule.kms_deletion[0].name) == 64 && length(aws_cloudwatch_event_rule.backup_failures[0].name) <= 64
    error_message = "The maximum accepted prefix must keep every EventBridge rule name within 64 characters."
  }
}

run "oversized_solution_prefix" {
  command = plan
  variables {
    solution_prefix = join("", [for _ in range(46) : "a"])
  }
  expect_failures = [var.solution_prefix]
}
