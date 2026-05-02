locals {
  project                           = var.project
  ecr_oneid_core                    = var.ecr_oneid_core
  idp_entity_ids                    = var.idp_entity_ids
  clients                           = var.clients
  cloudwatch_api_alarms_with_sns    = var.cloudwatch_api_alarms_with_sns
  cloudwatch_dlq_alarms_with_sns    = var.cloudwatch_dlq_alarms_with_sns
  cloudwatch_ecs_alarms_with_sns    = var.cloudwatch_ecs_alarms_with_sns
  cloudwatch_lambda_alarms_with_sns = var.cloudwatch_lambda_alarms_with_sns
}
