mock_provider "aws" {
  source = "../../tests/mocks"
  mock_data "aws_region" {
    defaults = { name = "eu-south-1" }
  }
}
run "nonproduction_composition" {
  command = apply
  assert {
    condition     = module.backup.dr_vault_arn == null && module.backup.continuous_plan_id == null && module.backup_alerting.sns_topic_arn != null
    error_message = "Non-production must compose alerting without DR or PITR."
  }
}
