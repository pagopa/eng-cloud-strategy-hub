variable "solution_prefix" {
  description = "Account-global unique consumer and regional prefix, 2-45 alphanumeric, hyphen or underscore characters."
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{2,45}$", var.solution_prefix))
    error_message = "solution_prefix must contain 2-45 alphanumeric, hyphen or underscore characters."
  }
}

variable "enabled" {
  description = "Create the scanner and health resources. Disabled mode needs no coverage configuration."
  type        = bool
  default     = true
  nullable    = false
}

variable "expected_resource_tags" {
  description = "Independent expected-inventory tags. Every key/value must match (AND). Required when enabled."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "resource_types" {
  description = "Explicit inventory discovery types: DynamoDB tables and S3 general purpose buckets only."
  type        = set(string)
  default     = []
  nullable    = false
}

variable "coverage_policy" {
  description = "Explicit whole-second freshness/grace/reminder thresholds and rate schedule (minutes or hours). No retention or backup-job inference."
  type = object({
    max_backup_age_seconds      = number
    freshness_tolerance_seconds = number
    initial_grace_seconds       = number
    reminder_interval_seconds   = number
    schedule                    = string
  })
  default = null
}

variable "sns_topic_arn" {
  description = "Caller-owned standard SNS topic in the provider account and Region. Required when enabled."
  type        = string
  default     = null
}

variable "sns_kms_key_arn" {
  description = "Caller-owned SNS customer-managed symmetric KMS key ARN in the provider account and Region. Required when enabled; caller retains key-policy ownership."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional scanner infrastructure tags. Do not include expected workload tags on the incident table."
  type        = map(string)
  default     = {}
  nullable    = false
}
