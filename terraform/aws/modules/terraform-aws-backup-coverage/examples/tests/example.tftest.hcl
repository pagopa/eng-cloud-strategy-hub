mock_provider "aws" {
  source = "../../../terraform-aws-backup/tests/mocks"
  mock_data "aws_region" {
    defaults = { name = "eu-south-1" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_resource "aws_lambda_function" {
    defaults = { arn = "arn:aws:lambda:eu-south-1:123456789012:function:test-coverage" }
  }
  mock_resource "aws_dynamodb_table" {
    defaults = { arn = "arn:aws:dynamodb:eu-south-1:123456789012:table/test-coverage" }
  }
}

run "standalone_integrated_and_disabled" {
  command = apply
  assert {
    condition     = module.standalone.lambda_function_arn != null && module.integrated.coverage_lambda_function_arn != null && module.disabled.lambda_function_arn == null && module.disabled.health_alarm_arns == null
    error_message = "Coverage examples must prove standalone, default-integrated, and complete opt-out calls."
  }
}
