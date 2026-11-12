locals {
  name = "${var.solution_prefix}-backup-coverage"
  common_tags = merge(var.tags, {
    ManagedBy = "terraform"
    Module    = "terraform-aws-backup-coverage"
  })
  schedule_parts   = try(regex("^rate\\(([1-9][0-9]*) (minute|minutes|hour|hours)\\)$", var.coverage_policy.schedule), [])
  schedule_seconds = try(tonumber(local.schedule_parts[0]) * (startswith(local.schedule_parts[1], "hour") ? 3600 : 60), 0)
  schedule_grammar_valid = try(
    tonumber(local.schedule_parts[0]) == 1 ? contains(["minute", "hour"], local.schedule_parts[1]) : contains(["minutes", "hours"], local.schedule_parts[1]),
    false
  )
  policy_valid = var.coverage_policy == null ? false : (
    alltrue([for value in [
      var.coverage_policy.max_backup_age_seconds,
      var.coverage_policy.freshness_tolerance_seconds,
      var.coverage_policy.initial_grace_seconds,
      var.coverage_policy.reminder_interval_seconds,
    ] : value != null ? value == floor(value) : false]) &&
    try(var.coverage_policy.max_backup_age_seconds > 0, false) &&
    try(var.coverage_policy.freshness_tolerance_seconds >= 0 && var.coverage_policy.freshness_tolerance_seconds < var.coverage_policy.max_backup_age_seconds, false) &&
    try(var.coverage_policy.initial_grace_seconds >= 0, false) &&
    try(var.coverage_policy.reminder_interval_seconds >= local.schedule_seconds, false) &&
    local.schedule_grammar_valid && local.schedule_seconds >= 600 && local.schedule_seconds <= 86400
  )
  topic_prefix = var.enabled ? "arn:${data.aws_partition.current[0].partition}:sns:${data.aws_region.current[0].name}:${data.aws_caller_identity.current[0].account_id}:" : ""
  key_prefix   = var.enabled ? "arn:${data.aws_partition.current[0].partition}:kms:${data.aws_region.current[0].name}:${data.aws_caller_identity.current[0].account_id}:key/" : ""
  runtime_configuration = var.enabled ? jsonencode({
    name           = local.name
    region         = data.aws_region.current[0].name
    account        = data.aws_caller_identity.current[0].account_id
    partition      = data.aws_partition.current[0].partition
    expected_tags  = var.expected_resource_tags
    resource_types = sort(tolist(var.resource_types))
    policy         = var.coverage_policy
    topic_arn      = var.sns_topic_arn
  }) : null
  health = {
    scan-failure = {
      namespace = "AWSBackup/Coverage", metric = "ScanFailure", statistic = "Sum"
      threshold = 1, comparison = "GreaterThanOrEqualToThreshold", periods = 1, missing = "notBreaching"
    }
    missing-success = {
      namespace = "AWSBackup/Coverage", metric = "ScanSuccess", statistic = "Sum"
      threshold = 1, comparison = "LessThanThreshold", periods = 2, missing = "breaching"
    }
    empty-inventory = {
      namespace = "AWSBackup/Coverage", metric = "EmptyInventory", statistic = "Maximum"
      threshold = 1, comparison = "GreaterThanOrEqualToThreshold", periods = 1, missing = "notBreaching"
    }
    lambda-errors = {
      namespace = "AWS/Lambda", metric = "Errors", statistic = "Sum"
      threshold = 1, comparison = "GreaterThanOrEqualToThreshold", periods = 1, missing = "notBreaching"
    }
    lambda-throttles = {
      namespace = "AWS/Lambda", metric = "Throttles", statistic = "Sum"
      threshold = 1, comparison = "GreaterThanOrEqualToThreshold", periods = 1, missing = "notBreaching"
    }
  }
}
