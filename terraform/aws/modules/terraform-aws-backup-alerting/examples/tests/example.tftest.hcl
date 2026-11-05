mock_provider "aws" {
  source = "../../terraform-aws-backup/tests/mocks"
}
run "independent_alerting" {
  command = apply
  assert {
    condition     = module.backup_alerting.sns_topic_arn != null && module.backup_alerting_simple.sns_topic_arn == "arn:aws:sns:eu-south-1:123456789012:existing-alerts-topic" && module.backup_alerting_grafana.sns_topic_arn != null
    error_message = "Alerting examples must run independently without an undeclared backup module."
  }
}
