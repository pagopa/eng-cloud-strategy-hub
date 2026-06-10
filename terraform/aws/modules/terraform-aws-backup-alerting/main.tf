###############################################################################
# SNS Topic — Backup Alerts
###############################################################################

resource "aws_sns_topic" "backup_alerts" {
  count = var.create_sns_topic ? 1 : 0

  name              = "${var.solution_prefix}-backup-alerts"
  kms_master_key_id = local.sns_kms_key_arn
  tags = merge(local.common_tags, {
    Name = "${local.tag_prefix}-backup-alerts"
  })
}

resource "aws_sns_topic_policy" "backup_alerts" {
  count = var.create_sns_topic || var.manage_existing_topic_policy ? 1 : 0

  arn    = local.sns_topic_arn
  policy = data.aws_iam_policy_document.sns_topic_policy.json
}

data "aws_iam_policy_document" "sns_topic_policy" {
  statement {
    sid    = "AllowEventBridgePublish"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    actions   = ["sns:Publish"]
    resources = [local.sns_topic_arn]

    # Restrict to the EventBridge rules this module creates (confused-deputy
    # protection). Falls back to account scope if no rules are enabled.
    dynamic "condition" {
      for_each = length(local.eventbridge_rule_arns) > 0 ? [1] : []
      content {
        test     = "ArnLike"
        variable = "aws:SourceArn"
        values   = local.eventbridge_rule_arns
      }
    }
  }

  # Enforce TLS for any access to the topic.
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions   = ["sns:Publish", "sns:Subscribe"]
    resources = [local.sns_topic_arn]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

###############################################################################
# EventBridge Rule — Backup / Copy / Restore Failures
###############################################################################

resource "aws_cloudwatch_event_rule" "backup_failures" {
  count = var.enable_backup_failure_alerts ? 1 : 0

  name        = "${var.solution_prefix}-backup-failures"
  description = "Captures AWS Backup job failures (backup, copy, restore) for alerting."

  event_pattern = jsonencode({
    source      = ["aws.backup"]
    detail-type = var.monitored_event_types
    detail = {
      state = var.backup_failure_event_states
    }
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "backup_failures_sns" {
  count = var.enable_backup_failure_alerts ? 1 : 0

  rule      = aws_cloudwatch_event_rule.backup_failures[0].name
  target_id = "send-to-sns"
  arn       = local.sns_topic_arn
}

###############################################################################
# EventBridge Rule — KMS Key Pending Deletion
###############################################################################

resource "aws_cloudwatch_event_rule" "kms_deletion" {
  count = var.enable_kms_deletion_alert ? 1 : 0

  name        = "${var.solution_prefix}-kms-deletion-alert"
  description = "Alerts when a KMS key is scheduled for deletion or disabled."

  event_pattern = length(var.kms_key_ids) > 0 ? jsonencode({
    source      = ["aws.kms"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = ["ScheduleKeyDeletion", "DisableKey"]
      requestParameters = {
        keyId = var.kms_key_ids
      }
    }
    }) : jsonencode({
    source      = ["aws.kms"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = ["ScheduleKeyDeletion", "DisableKey"]
    }
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "kms_deletion_sns" {
  count = var.enable_kms_deletion_alert ? 1 : 0

  rule      = aws_cloudwatch_event_rule.kms_deletion[0].name
  target_id = "send-to-sns"
  arn       = local.sns_topic_arn
}

###############################################################################
# SNS Subscriptions — Email
###############################################################################

resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.email_endpoints)

  topic_arn = local.sns_topic_arn
  protocol  = "email"
  endpoint  = each.value
}

###############################################################################
# SNS Subscriptions — HTTPS Webhook
###############################################################################

resource "aws_sns_topic_subscription" "webhook" {
  for_each = toset(var.webhook_endpoints)

  topic_arn = local.sns_topic_arn
  protocol  = "https"
  endpoint  = each.value
}

###############################################################################
# SNS Subscriptions — SQS
###############################################################################

resource "aws_sns_topic_subscription" "sqs" {
  for_each = toset(var.sqs_endpoints)

  topic_arn = local.sns_topic_arn
  protocol  = "sqs"
  endpoint  = each.value
}

###############################################################################
# SNS Subscriptions — Lambda
###############################################################################

resource "aws_sns_topic_subscription" "lambda" {
  for_each = toset(var.lambda_endpoints)

  topic_arn = local.sns_topic_arn
  protocol  = "lambda"
  endpoint  = each.value
}
