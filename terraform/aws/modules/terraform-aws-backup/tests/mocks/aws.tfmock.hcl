mock_data "aws_caller_identity" {
  defaults = {
    account_id = "123456789012"
    arn        = "arn:aws:iam::123456789012:root"
    user_id    = "test"
  }
}

mock_data "aws_partition" {
  defaults = {
    partition  = "aws"
    dns_suffix = "amazonaws.com"
  }
}

mock_resource "aws_lambda_function" {
  defaults = {
    arn = "arn:aws:lambda:eu-south-1:123456789012:function:test-coverage"
  }
}

mock_resource "aws_dynamodb_table" {
  defaults = {
    arn = "arn:aws:dynamodb:eu-south-1:123456789012:table/test-coverage"
  }
}

mock_data "aws_iam_policy_document" {
  defaults = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
}

mock_resource "aws_iam_role" {
  defaults = {
    arn = "arn:aws:iam::123456789012:role/test-backup"
  }
}

mock_resource "aws_kms_key" {
  defaults = {
    arn    = "arn:aws:kms:eu-south-1:123456789012:key/00000000-0000-0000-0000-000000000001"
    key_id = "00000000-0000-0000-0000-000000000001"
  }
}

mock_resource "aws_backup_vault" {
  defaults = {
    arn = "arn:aws:backup:eu-south-1:123456789012:backup-vault:test-vault"
  }
}

mock_resource "aws_backup_plan" {
  defaults = {
    arn = "arn:aws:backup:eu-south-1:123456789012:backup-plan:test-plan"
  }
}

mock_resource "aws_sns_topic" {
  defaults = {
    arn = "arn:aws:sns:eu-south-1:123456789012:test-alerts"
  }
}

mock_resource "aws_cloudwatch_event_rule" {
  defaults = {
    arn = "arn:aws:events:eu-south-1:123456789012:rule/test-alerts"
  }
}

mock_resource "aws_backup_restore_testing_plan" {
  defaults = {
    arn = "arn:aws:backup:eu-south-1:123456789012:restore-testing-plan:test-plan"
  }
}
