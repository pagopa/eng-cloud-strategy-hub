###############################################################################
# Required Variables
###############################################################################

variable "solution_prefix" {
  description = "Prefix for alerting resources created by this solution (EventBridge rules, SNS topic, KMS alias). Caution: changing this value may break execution as different AWS resources have different naming limits."
  type        = string
  default     = "backup-solution"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{2,50}$", var.solution_prefix))
    error_message = "solution_prefix must be 2-50 characters, alphanumeric plus hyphen and underscore only."
  }
}

variable "tag_identifier_prefix" {
  description = "Prefix for the Name tag applied to resources created by this solution. Defaults to solution_prefix."
  type        = string
  default     = null
}

###############################################################################
# EventBridge — Backup Failures
###############################################################################

variable "enable_backup_failure_alerts" {
  description = "Whether to create the EventBridge rule for backup/copy/restore failures."
  type        = bool
  default     = true
}

variable "backup_failure_event_states" {
  description = "Backup job states that trigger an alert."
  type        = list(string)
  default     = ["FAILED", "EXPIRED", "ABORTED"]
}

variable "monitored_event_types" {
  description = "List of AWS Backup event detail-types to capture."
  type        = list(string)
  default = [
    "Backup Job State Change",
    "Copy Job State Change",
    "Restore Job State Change",
  ]
}

###############################################################################
# EventBridge — KMS Key Deletion
###############################################################################

variable "enable_kms_deletion_alert" {
  description = "Whether to alert when a KMS key is scheduled for deletion."
  type        = bool
  default     = true
}

variable "kms_key_ids" {
  description = "List of KMS key IDs to monitor for deletion. If empty and enable_kms_deletion_alert is true, monitors all ScheduleKeyDeletion events in the account."
  type        = list(string)
  default     = []
}

###############################################################################
# SNS Topic
###############################################################################

variable "create_sns_topic" {
  description = "Whether to create a new SNS topic. Set to false if you want to use an existing topic."
  type        = bool
  default     = true
}

variable "existing_sns_topic_arn" {
  description = "ARN of an existing SNS topic to use. Required when create_sns_topic is false."
  type        = string
  default     = null
}

variable "manage_existing_topic_policy" {
  description = "When using an existing SNS topic (create_sns_topic = false), also manage its access policy so EventBridge can publish. Leave false if the topic policy is managed elsewhere. WARNING: enabling this overwrites the existing topic's policy."
  type        = bool
  default     = false
}

variable "sns_kms_key_arn" {
  description = "ARN of an existing customer-managed KMS key to encrypt the SNS topic. If null (default), the module creates a dedicated CMK. AWS-managed keys (e.g. alias/aws/sns) are intentionally not supported — the key policy must allow events.amazonaws.com to call kms:GenerateDataKey* and kms:Decrypt."
  type        = string
  default     = null
}

variable "kms_deletion_window_in_days" {
  description = "Waiting period in days before deletion of the SNS CMK created by this module. Between 7 and 30."
  type        = number
  default     = 30

  validation {
    condition     = var.kms_deletion_window_in_days >= 7 && var.kms_deletion_window_in_days <= 30
    error_message = "kms_deletion_window_in_days must be between 7 and 30 days."
  }
}

###############################################################################
# Notification Endpoints
###############################################################################

variable "email_endpoints" {
  description = "List of email addresses to subscribe to backup alerts."
  type        = list(string)
  default     = []
}

variable "webhook_endpoints" {
  description = "List of HTTPS webhook URLs to subscribe (e.g., Grafana, PagerDuty)."
  type        = list(string)
  default     = []
}

variable "sqs_endpoints" {
  description = "List of SQS queue ARNs to subscribe."
  type        = list(string)
  default     = []
}

variable "lambda_endpoints" {
  description = "List of Lambda function ARNs to subscribe."
  type        = list(string)
  default     = []
}

###############################################################################
# Tags
###############################################################################

variable "tags" {
  description = "Additional tags to apply to all resources."
  type        = map(string)
  default     = {}
}
