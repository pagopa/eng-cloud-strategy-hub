data "aws_caller_identity" "current" { count = var.enabled ? 1 : 0 }
data "aws_region" "current" { count = var.enabled ? 1 : 0 }
data "aws_partition" "current" { count = var.enabled ? 1 : 0 }

resource "terraform_data" "configuration" {
  count = var.enabled ? 1 : 0
  lifecycle {
    precondition {
      condition     = length(var.expected_resource_tags) > 0 && alltrue([for key, value in var.expected_resource_tags : value == null ? false : length(trimspace(key)) > 0 && length(trimspace(value)) > 0])
      error_message = "Enabled coverage requires explicit non-empty expected-resource tags."
    }
    precondition {
      condition     = length(var.resource_types) > 0 && length(setsubtract(var.resource_types, toset(["DynamoDB", "S3"]))) == 0
      error_message = "Enabled coverage supports only DynamoDB tables and S3 general purpose buckets."
    }
    precondition {
      condition     = local.policy_valid
      error_message = "Provide whole-second valid thresholds, tolerance below maximum age, reminder at least one cadence, and rate(N minutes|hours) between 10 minutes and 24 hours."
    }
    precondition {
      condition     = var.sns_topic_arn == null ? false : startswith(var.sns_topic_arn, local.topic_prefix) && length(trimprefix(var.sns_topic_arn, local.topic_prefix)) > 0 && !endswith(var.sns_topic_arn, ".fifo")
      error_message = "Enabled coverage requires a standard SNS topic ARN in the provider account and Region."
    }
    precondition {
      condition     = var.sns_kms_key_arn == null ? false : startswith(var.sns_kms_key_arn, local.key_prefix) && length(trimprefix(var.sns_kms_key_arn, local.key_prefix)) > 0
      error_message = "Enabled coverage requires the SNS customer-managed key ARN in the provider account and Region."
    }
    precondition {
      condition     = !alltrue([for key, value in var.expected_resource_tags : lookup(local.common_tags, key, null) == value])
      error_message = "Scanner infrastructure must not match all expected workload tags, or the incident table would monitor itself."
    }
    precondition {
      condition     = length(base64encode(local.runtime_configuration)) <= 4000
      error_message = "Serialized coverage configuration must fit within 3000 UTF-8 bytes, leaving room within Lambda's 4 KB environment limit."
    }
  }
}

data "archive_file" "coverage" {
  count       = var.enabled ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/lambda/coverage.py"
  output_path = "${path.root}/.terraform/${local.name}.zip"
}

resource "aws_cloudwatch_log_group" "coverage" {
  count             = var.enabled ? 1 : 0
  name              = "/aws/lambda/${local.name}"
  retention_in_days = 30
  tags              = local.common_tags
  depends_on        = [terraform_data.configuration]
}

resource "aws_dynamodb_table" "incidents" {
  count        = var.enabled ? 1 : 0
  name         = "${local.name}-incidents"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "resource_arn"
  attribute {
    name = "resource_arn"
    type = "S"
  }
  point_in_time_recovery { enabled = true }
  server_side_encryption { enabled = true }
  tags       = local.common_tags
  depends_on = [terraform_data.configuration]
}

resource "aws_lambda_function" "coverage" {
  count                          = var.enabled ? 1 : 0
  function_name                  = local.name
  role                           = aws_iam_role.coverage[0].arn
  runtime                        = "python3.12"
  handler                        = "coverage.handler"
  filename                       = data.archive_file.coverage[0].output_path
  source_code_hash               = data.archive_file.coverage[0].output_base64sha256
  timeout                        = 300
  memory_size                    = 256
  reserved_concurrent_executions = 1
  environment {
    variables = {
      STATE_TABLE     = aws_dynamodb_table.incidents[0].name
      COVERAGE_CONFIG = local.runtime_configuration
    }
  }
  tags       = local.common_tags
  depends_on = [aws_iam_role_policy.coverage]
}

resource "aws_lambda_function_event_invoke_config" "coverage" {
  count                        = var.enabled ? 1 : 0
  function_name                = aws_lambda_function.coverage[0].function_name
  maximum_retry_attempts       = 2
  maximum_event_age_in_seconds = max(60, local.schedule_seconds)
}

resource "aws_scheduler_schedule_group" "coverage" {
  count      = var.enabled ? 1 : 0
  name       = local.name
  tags       = local.common_tags
  depends_on = [terraform_data.configuration]
}

resource "aws_scheduler_schedule" "coverage" {
  count               = var.enabled ? 1 : 0
  name                = local.name
  group_name          = aws_scheduler_schedule_group.coverage[0].name
  schedule_expression = try(var.coverage_policy.schedule, "")
  flexible_time_window { mode = "OFF" }
  target {
    arn      = aws_lambda_function.coverage[0].arn
    role_arn = aws_iam_role.scheduler[0].arn
    input    = "{}"
    retry_policy {
      maximum_event_age_in_seconds = max(60, local.schedule_seconds)
      maximum_retry_attempts       = 2
    }
  }
  depends_on = [aws_iam_role_policy.scheduler, aws_lambda_function_event_invoke_config.coverage]
}

resource "aws_cloudwatch_metric_alarm" "health" {
  for_each            = var.enabled ? local.health : {}
  alarm_name          = "${local.name}-${each.key}"
  alarm_description   = "Coverage ${each.key}; cadence ${local.schedule_seconds}s, first scan within one cadence; missing-success allows two periods for startup. Shared SNS/KMS delivery is not independently monitored."
  namespace           = each.value.namespace
  metric_name         = each.value.metric
  statistic           = each.value.statistic
  period              = max(600, local.schedule_seconds)
  evaluation_periods  = each.value.periods
  threshold           = each.value.threshold
  comparison_operator = each.value.comparison
  treat_missing_data  = each.value.missing
  dimensions          = each.value.namespace == "AWS/Lambda" ? { FunctionName = aws_lambda_function.coverage[0].function_name } : { Scanner = local.name }
  alarm_actions       = [var.sns_topic_arn]
  ok_actions          = [var.sns_topic_arn]
  tags                = local.common_tags
}
