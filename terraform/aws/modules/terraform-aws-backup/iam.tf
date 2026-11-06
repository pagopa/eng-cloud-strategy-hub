###############################################################################
# IAM Role — Backup
###############################################################################

resource "aws_iam_role" "backup" {
  name               = "${var.solution_prefix}-backup-role"
  description        = "Allows AWS Backup to call AWS services on your behalf for backup operations"
  assume_role_policy = file("${path.module}/policies/iam_trust_backup.json")

  tags = merge(local.common_tags, {
    Name = "${local.tag_prefix}-backup-role"
  })
}

resource "aws_iam_role_policy_attachment" "backup_service" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "backup_s3" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForS3Backup"
}

###############################################################################
# IAM Role — Restore
###############################################################################

resource "aws_iam_role" "restore" {
  name               = "${var.solution_prefix}-restore-role"
  description        = "Allows AWS Backup to call AWS services on your behalf for restore operations"
  assume_role_policy = file("${path.module}/policies/iam_trust_backup.json")

  tags = merge(local.common_tags, {
    Name = "${local.tag_prefix}-restore-role"
  })
}

resource "aws_iam_role_policy_attachment" "restore_service" {
  role       = aws_iam_role.restore.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

resource "aws_iam_role_policy_attachment" "restore_s3" {
  role       = aws_iam_role.restore.name
  policy_arn = "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForS3Restore"
}

###############################################################################
# Additional policy for KMS access on restore (source resource CMKs)
###############################################################################

resource "aws_iam_role_policy" "restore_kms" {
  name   = "${var.solution_prefix}-restore-kms"
  role   = aws_iam_role.restore.id
  policy = file("${path.module}/policies/iam_restore_kms.json")
}
