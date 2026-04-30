variable "project" {
  type = string
}

variable "ecr_oneid_core" {
  type = string
}

variable "idp_entity_ids" {
  type = list(string)
}

variable "clients" {
  type = list(object({
    client_id     = string
    friendly_name = string
  }))
}

variable "cloudwatch_api_alarms_with_sns" {
  type = map(object({
    metric_name         = string
    namespace           = string
    threshold           = number
    evaluation_periods  = number
    period              = number
    statistic           = string
    comparison_operator = string
    resource_name       = string
    method              = string
    sns_topic_alarm_arn = optional(string, null)
  }))
}

variable "cloudwatch_dlq_alarms_with_sns" {
  type = object({
    metric_name         = string
    namespace           = string
    threshold           = number
    evaluation_periods  = number
    period              = number
    statistic           = string
    comparison_operator = string
    sns_topic_alarm_arn = optional(string, null)
  })
}

variable "cloudwatch_ecs_alarms_with_sns" {
  type = map(object({
    metric_name         = string
    namespace           = string
    threshold           = number
    evaluation_periods  = number
    period              = number
    statistic           = string
    comparison_operator = string
    sns_topic_alarm_arn = optional(string, null)
    scaling_policy      = optional(string, null)
  }))
}

variable "cloudwatch_lambda_alarms_with_sns" {
  type = map(object({
    metric_name         = string
    namespace           = string
    threshold           = number
    evaluation_periods  = number
    period              = number
    statistic           = string
    comparison_operator = string
    sns_topic_alarm_arn = optional(string, null)
    treat_missing_data  = string
  }))
}

variable "alarm_subscribers" {
  type = string
}

variable "api_cache_cluster_enabled" {
  type = bool
}

variable "api_method_settings" {
  type = any
}

variable "app_cloudwatch_custom_metric_namespace" {
  type = string
}

variable "app_log_level" {
  type = string
}

variable "assertion_bucket" {
  type = any
}

variable "assertions_crawler_schedule" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "aws_region_short" {
  type = string
}

variable "cie_entity_id" {
  type = string
}

variable "client_registrations_table" {
  type = any
}

variable "client_status_history_table" {
  type = any
}

variable "dlq_assertion_setting" {
  type = object({
    maximum_retry_attempts        = number
    maximum_record_age_in_seconds = number
  })
}

variable "dns_record_ttl" {
  type = number
}

variable "ecs_enable_container_insights" {
  type = bool
}

variable "ecs_oneid_core" {
  type = any
}

variable "enable_nat_gateway" {
  type = bool
}

variable "env_short" {
  type = string
}

variable "idp_metadata_table" {
  type = any
}

variable "idp_status_history_table" {
  type = any
}

variable "is_gh_sns_arn" {
  type = string
}

variable "lambda_cloudwatch_logs_retention_in_days" {
  type = number
}

variable "last_idp_used_table" {
  type = any
}

variable "metadata_info" {
  type = object({
    acs_url = string
    slo_url = string
  })
}

variable "number_of_images_to_keep" {
  type = number
}

variable "pairwise_enabled" {
  type = bool
}

variable "pdv_base_url" {
  type = string
}

variable "pdv_plan_url" {
  type = string
}

variable "r53_dns_zone" {
  type = object({
    name    = string
    comment = string
  })
}

variable "registry_enabled" {
  type = bool
}

variable "repository_image_tag_mutability" {
  type = string
}

variable "rest_api_throttle_settings" {
  type = object({
    burst_limit = number
    rate_limit  = number
  })
}

variable "sessions_table" {
  type = any
}

variable "single_nat_gateway" {
  type = bool
}

variable "ssm_cert_key" {
  type = object({
    cert_pem = string
    key_pem  = string
  })
}

variable "vpc_cidr" {
  type = string
}

variable "vpc_internal_subnets_cidr" {
  type = list(string)
}

variable "vpc_private_subnets_cidr" {
  type = list(string)
}

variable "vpc_public_subnets_cidr" {
  type = list(string)
}

variable "xray_tracing_enabled" {
  type = bool
}
