variable "key_name" {
  type        = string
  description = "Name for the AWS key pair."
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to the key pair."
  default     = {}
}
