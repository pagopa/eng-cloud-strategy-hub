resource "aws_iam_role" "coverage" {
  count = var.enabled ? 1 : 0
  name  = "${var.solution_prefix}-coverage-lambda"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow", Action = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
  tags       = local.common_tags
  depends_on = [terraform_data.configuration]
}

resource "aws_iam_role_policy" "coverage" {
  count = var.enabled ? 1 : 0
  name  = "${local.name}-scan"
  role  = aws_iam_role.coverage[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid      = "BackupRead", Effect = "Allow"
          Action   = ["backup:ListRecoveryPointsByResource"]
          Resource = ["*"]
        },
        {
          Sid      = "IncidentState", Effect = "Allow"
          Action   = ["dynamodb:Scan", "dynamodb:PutItem"]
          Resource = [aws_dynamodb_table.incidents[0].arn]
        },
        {
          Sid      = "Logs", Effect = "Allow"
          Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
          Resource = ["${aws_cloudwatch_log_group.coverage[0].arn}:*"]
        },
        {
          Sid       = "Metrics", Effect = "Allow"
          Action    = ["cloudwatch:PutMetricData"], Resource = ["*"]
          Condition = { StringEquals = { "cloudwatch:namespace" = "AWSBackup/Coverage" } }
        },
        {
          Sid    = "Publish", Effect = "Allow"
          Action = ["sns:Publish"], Resource = [var.sns_topic_arn]
        },
        {
          Sid      = "TopicEncryption", Effect = "Allow"
          Action   = ["kms:GenerateDataKey*", "kms:Decrypt"]
          Resource = [var.sns_kms_key_arn]
        },
      ],
      contains(var.resource_types, "S3") ? [
        {
          Sid    = "S3Inventory", Effect = "Allow"
          Action = ["s3:ListAllMyBuckets"], Resource = ["*"]
        },
      ] : [],
      contains(var.resource_types, "S3") ? [
        {
          Sid       = "S3Tags", Effect = "Allow"
          Action    = ["s3:GetBucketTagging"]
          Resource  = ["arn:${data.aws_partition.current[0].partition}:s3:::*"]
          Condition = { StringEquals = { "s3:ResourceAccount" = data.aws_caller_identity.current[0].account_id } }
        },
      ] : [],
      contains(var.resource_types, "DynamoDB") ? [
        {
          Sid    = "DynamoDBInventory", Effect = "Allow"
          Action = ["dynamodb:ListTables"], Resource = ["*"]
        },
        {
          Sid      = "DynamoDBTags", Effect = "Allow"
          Action   = ["dynamodb:ListTagsOfResource"]
          Resource = ["arn:${data.aws_partition.current[0].partition}:dynamodb:${data.aws_region.current[0].name}:${data.aws_caller_identity.current[0].account_id}:table/*"]
        },
      ] : [],
    )
  })
}

resource "aws_iam_role" "scheduler" {
  count = var.enabled ? 1 : 0
  name  = "${var.solution_prefix}-coverage-scheduler"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow", Action = "sts:AssumeRole"
      Principal = { Service = "scheduler.amazonaws.com" }
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current[0].account_id }
        ArnEquals    = { "aws:SourceArn" = aws_scheduler_schedule_group.coverage[0].arn }
      }
    }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy" "scheduler" {
  count = var.enabled ? 1 : 0
  name  = "${local.name}-invoke"
  role  = aws_iam_role.scheduler[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow", Action = ["lambda:InvokeFunction"]
      Resource = [aws_lambda_function.coverage[0].arn]
    }]
  })
}
