mock_provider "aws" {
  source = "../../tests/mocks"
  mock_data "aws_region" {
    defaults = { name = "eu-south-1" }
  }
}
run "explicit_nonproduction_compliance" {
  command = apply
  assert {
    condition     = module.backup.vault_name == "team-identity-uat-vault" && module.backup.dr_vault_arn == null
    error_message = "Explicit non-production COMPLIANCE must remain runnable without DR."
  }
}
