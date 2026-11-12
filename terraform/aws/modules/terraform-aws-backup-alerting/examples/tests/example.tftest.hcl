mock_provider "aws" {
  source = "../../terraform-aws-backup/tests/mocks"
  mock_data "aws_region" {
    defaults = { name = "eu-south-1" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_resource "aws_lambda_function" {
    defaults = { arn = "arn:aws:lambda:eu-south-1:123456789012:function:test-alerts" }
  }
  mock_resource "aws_dynamodb_table" {
    defaults = { arn = "arn:aws:dynamodb:eu-south-1:123456789012:table/test-alerts" }
  }
}
run "independent_alerting" {
  command = apply
  assert {
    condition     = module.backup_alerting.sns_topic_arn != null && module.backup_alerting_simple.sns_topic_arn == "arn:aws:sns:eu-south-1:123456789012:existing-alerts-topic"
    error_message = "Alerting examples must run independently without an undeclared backup module."
  }
  assert {
    condition     = module.backup_alerting.coverage_lambda_function_arn != null && module.backup_alerting_simple.coverage_lambda_function_arn == null
    error_message = "The owned-topic example enables coverage; the supplied-topic example explicitly opts out."
  }
}
