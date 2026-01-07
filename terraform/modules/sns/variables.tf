variable "alarm_subscribers_emails" {
  type        = string
  description = "SSM parameter store with the list alarm subscribers emails."
}

variable "sns_topic_name" {
  type        = string
  description = "SNS topic name."
}
