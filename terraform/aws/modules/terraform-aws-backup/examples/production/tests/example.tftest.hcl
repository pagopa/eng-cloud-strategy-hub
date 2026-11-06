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
run "production_composition" {
  command = apply
  assert {
    condition     = module.backup.dr_vault_arn != null && module.backup.continuous_plan_id == null && module.backup_hourly.plan_id != null && module.backup_long_retention.plan_id != null && output.sns_topic_arn != null
    error_message = "Production must compose DR, snapshot presets, and independent alerting without implicit PITR."
  }
}
