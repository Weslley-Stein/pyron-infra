terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "2.69.0"
    }
  }
  required_version = "~>1.14"
}

provider "digitalocean" {}