mock_provider "aws" {
  source = "../../tests/mocks"
  mock_data "aws_region" {
    defaults = { name = "eu-south-1" }
  }
}
mock_provider "aws" {
  alias  = "dr"
  source = "../../tests/mocks"
  mock_data "aws_region" {
    defaults = { name = "eu-central-1" }
  }
}
run "extra_plan_composition" {
  command = apply
  assert {
    condition     = module.backup.dr_vault_arn != null && module.hourly.plan_id != null && module.long_retention.plan_id != null && module.twice_daily.plan_id != null
    error_message = "Extra plans must compose with the caller's protected vault and IAM role."
  }
}
