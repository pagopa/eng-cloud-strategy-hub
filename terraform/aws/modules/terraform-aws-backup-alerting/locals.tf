locals {
  sns_topic_arn = var.create_sns_topic ? aws_sns_topic.backup_alerts[0].arn : var.existing_sns_topic_arn

  tag_prefix = coalesce(var.tag_identifier_prefix, var.solution_prefix)

  # Create a dedicated CMK only when we own the topic and no existing CMK is supplied.
  create_sns_kms_key = var.create_sns_topic && var.sns_kms_key_arn == null

  sns_kms_key_arn = var.create_sns_topic ? (
    var.sns_kms_key_arn != null ? var.sns_kms_key_arn : aws_kms_key.sns[0].arn
  ) : null

  eventbridge_rule_arns = compact([
    var.enable_backup_failure_alerts ? aws_cloudwatch_event_rule.backup_failures[0].arn : "",
    var.enable_kms_deletion_alert ? aws_cloudwatch_event_rule.kms_deletion[0].arn : "",
  ])

  common_tags = merge(
    {
      "ManagedBy" = "terraform"
      "Module"    = "terraform-aws-backup-alerting"
    },
    var.tags
  )
}
