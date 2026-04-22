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

variable "prefix" {
  type        = string
  description = "Optional short product prefix used in resource naming."
  default     = null
}

variable "env_short" {
  type        = string
  description = "Optional short environment identifier used in naming."
  default     = null
}

variable "location" {
  type        = string
  description = "Optional location or region name."
  default     = null
}

variable "location_short" {
  type        = string
  description = "Optional short location identifier used in naming."
  default     = null
}
