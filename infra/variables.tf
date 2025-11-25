variable "region" {
    description = ""
    type = string
    default = "lon1"
    validation { 
        condition = var.droplet_name != ""
        error_message = "Region not specified!"
    }
}

variable "registry_name" {
    description = ""
    type = string
    validation {
        condition = var.registry_name != ""
        error_message = "Registry name not specified!" 
    } 
}

variable "droplet_name" {
    description = ""
    type = string
    validation { 
        condition = var.droplet_name != ""
        error_message = "Droplet name not specified!"
    }
}