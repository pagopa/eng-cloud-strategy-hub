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
run "dedicated_pitr_composition" {
  command = apply
  assert {
    condition     = output.continuous_plan_id != null && module.backup.dr_vault_arn != null
    error_message = "The PITR example must explicitly enable a dedicated continuous plan alongside production snapshot DR."
  }
}
