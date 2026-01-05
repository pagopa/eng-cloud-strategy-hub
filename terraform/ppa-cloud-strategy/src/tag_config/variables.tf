variable "environment" {
  type        = string
  description = "The environment to which the tagged resources belong, e.g., dev, uat, prod."
  validation {
    condition     = contains(["dev", "uat", "prod"], var.environment)
    error_message = "The environment must be one of: dev, uat, prod."
  }
}

variable "domain" {
  type        = string
  description = "The domain to which the tagged resources belong, e.g., bizevent, nodo, core, ..."
}
