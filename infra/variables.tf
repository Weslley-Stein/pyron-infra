variable "region" {
  description = "Region where resources will be provisioned."
  type        = string
  default     = "lon1"
  validation {
    condition     = var.region != ""
    error_message = "Region not specified!"
  }
}

variable "registry_name" {
  description = "Name of the registry for API image."
  type        = string
  default = "pyron-api"
  validation {
    condition     = var.registry_name != ""
    error_message = "Registry name not specified!"
  }
}

variable "droplet_name" {
  description = "Webserver name."
  type        = string
  default = "pyron-webserver"
  validation {
    condition     = var.droplet_name != ""
    error_message = "Droplet name not specified!"
  }
}