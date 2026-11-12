mock_provider "aws" {
  source = "tests/mocks"
  mock_data "aws_region" {
    defaults = { name = "eu-south-1" }
  }
}
mock_provider "aws" {
  alias  = "dr"
  source = "tests/mocks"
  mock_data "aws_region" {
    defaults = { name = "eu-central-1" }
  }
}
run "isolated_count_and_for_each" {
  command = apply
  module { source = "./tests/fixtures/consumer" }
  providers = {
    aws    = aws
    aws.dr = aws.dr
  }
  assert {
    condition     = length(output.vault_names) == 3 && length(distinct(output.vault_names)) == 3
    error_message = "Caller providers must permit count and for_each with isolated names."
  }
}
