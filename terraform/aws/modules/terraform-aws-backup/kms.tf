###############################################################################
# KMS Key — Primary Region (Backup Vault Encryption)
###############################################################################

resource "aws_kms_key" "backup" {
  description             = "CMK for AWS Backup vault: ${var.solution_prefix}"
  deletion_window_in_days = var.kms_deletion_window_in_days
  enable_key_rotation     = var.kms_enable_key_rotation
  multi_region            = var.kms_multi_region

  tags = merge(local.common_tags, {
    Name = "${local.tag_prefix}-backup-key"
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "backup" {
  name          = "alias/${var.solution_prefix}-backup"
  target_key_id = aws_kms_key.backup.key_id
}

resource "aws_kms_key_policy" "backup" {
  key_id = aws_kms_key.backup.id
  policy = data.aws_iam_policy_document.kms_policy.json
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "kms_policy" {
  # Note: Resource="*" in a KMS key policy scopes to THIS key only; the key ARN
  # cannot be referenced here (circular dependency). This is the AWS-recommended
  # default key policy. Key administration is granted to the account root per
  # AWS KMS best practice (also enables the break-glass recovery path).
  # Key administrators
  statement {
    sid    = "KeyAdministration"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions = [
      "kms:Create*",
      "kms:Describe*",
      "kms:Enable*",
      "kms:List*",
      "kms:Put*",
      "kms:Update*",
      "kms:Revoke*",
      "kms:Disable*",
      "kms:Get*",
      "kms:Delete*",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:ScheduleKeyDeletion",
      "kms:CancelKeyDeletion",
    ]
    resources = ["*"]
  }

  # Backup service role usage
  statement {
    sid    = "BackupServiceUsage"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.backup.arn]
    }
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
      "kms:CreateGrant",
    ]
    resources = ["*"]
  }

  # Restore role usage
  statement {
    sid    = "RestoreServiceUsage"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.restore.arn]
    }
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:CreateGrant",
    ]
    resources = ["*"]
  }

  # AWS Backup service
  statement {
    sid    = "AWSBackupService"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
      "kms:CreateGrant",
    ]
    resources = ["*"]
  }
}

###############################################################################
# KMS Key — DR Region (Cross-Region Copy Encryption)
###############################################################################

resource "aws_kms_key" "backup_dr" {
  count = local.enable_cross_region_copy ? 1 : 0

  provider = aws.dr

  description             = "CMK for AWS Backup DR vault: ${var.solution_prefix}-dr"
  deletion_window_in_days = var.kms_deletion_window_in_days
  enable_key_rotation     = var.kms_enable_key_rotation
  multi_region            = var.kms_multi_region

  tags = merge(local.common_tags, {
    Name = "${local.tag_prefix}-backup-dr-key"
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "backup_dr" {
  count = local.enable_cross_region_copy ? 1 : 0

  provider = aws.dr

  name          = "alias/${var.solution_prefix}-backup-dr"
  target_key_id = aws_kms_key.backup_dr[0].key_id
}

resource "aws_kms_key_policy" "backup_dr" {
  count = local.enable_cross_region_copy ? 1 : 0

  provider = aws.dr

  key_id = aws_kms_key.backup_dr[0].id
  policy = data.aws_iam_policy_document.kms_policy_dr[0].json
}

# Mirrors the primary key policy so the backup/restore roles and the AWS Backup
# service can use the DR key for cross-region copy AND for DR restore.
data "aws_iam_policy_document" "kms_policy_dr" {
  count = local.enable_cross_region_copy ? 1 : 0

  # Note: Resource="*" in a KMS key policy scopes to THIS key only; the key ARN
  # cannot be referenced here (circular dependency). AWS-recommended default key
  # policy. Key administration is granted to the account root per KMS best practice.

  statement {
    sid    = "KeyAdministration"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions = [
      "kms:Create*",
      "kms:Describe*",
      "kms:Enable*",
      "kms:List*",
      "kms:Put*",
      "kms:Update*",
      "kms:Revoke*",
      "kms:Disable*",
      "kms:Get*",
      "kms:Delete*",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:ScheduleKeyDeletion",
      "kms:CancelKeyDeletion",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "BackupServiceUsage"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.backup.arn]
    }
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
      "kms:CreateGrant",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "RestoreServiceUsage"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.restore.arn]
    }
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:CreateGrant",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AWSBackupService"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
      "kms:CreateGrant",
    ]
    resources = ["*"]
  }
}
