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
run "explicit_service_selection" {
  command = apply
  assert {
    condition     = output.vault_arn != null && module.backup.dr_vault_arn != null && module.backup.continuous_plan_id == null
    error_message = "Explicit service selection must preserve production DR without implicit continuous backup."
  }
}
