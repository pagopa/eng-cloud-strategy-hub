###############################################################################
# KMS Key — SNS Topic Encryption (customer-managed)
#
# Decision §6: only customer-managed keys (CMK). AWS-managed / default keys
# are not used anywhere in the solution, including the alerting topic.
#
# The key policy grants EventBridge (events.amazonaws.com) the KMS actions it
# needs to publish to the encrypted topic. Without this, EventBridge → SNS
# delivery fails on an encrypted topic.
###############################################################################

data "aws_caller_identity" "current" {}

resource "aws_kms_key" "sns" {
  count = local.create_sns_kms_key ? 1 : 0

  description             = "CMK for AWS Backup alerting SNS topic: ${var.solution_prefix}"
  deletion_window_in_days = var.kms_deletion_window_in_days
  enable_key_rotation     = true

  policy = data.aws_iam_policy_document.sns_kms[0].json

  tags = merge(local.common_tags, {
    Name = "${local.tag_prefix}-backup-alerts-key"
  })
}

resource "aws_kms_alias" "sns" {
  count = local.create_sns_kms_key ? 1 : 0

  name          = "alias/${var.solution_prefix}-backup-alerts"
  target_key_id = aws_kms_key.sns[0].key_id
}

data "aws_iam_policy_document" "sns_kms" {
  count = local.create_sns_kms_key ? 1 : 0

  # Note: Resource="*" in a KMS key policy scopes to THIS key only; the key ARN
  # cannot be referenced here (circular dependency). AWS-recommended default key
  # policy. Key administration is granted to the account root per KMS best practice.

  # Key administration by the account.
  statement {
    sid    = "KeyAdministration"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  # EventBridge needs to encrypt the message it publishes to the topic.
  statement {
    sid    = "AllowEventBridgeUseOfKey"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    actions = [
      "kms:GenerateDataKey*",
      "kms:Decrypt",
    ]
    resources = ["*"]
  }

  # SNS service usage when delivering/handling encrypted messages.
  statement {
    sid    = "AllowSNSUseOfKey"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }
    actions = [
      "kms:GenerateDataKey*",
      "kms:Decrypt",
    ]
    resources = ["*"]
  }
}
