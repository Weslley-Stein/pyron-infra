resource "digitalocean_container_registry" "main" {
  name                   = "${var.registry_name}-${var.region}"
  subscription_tier_slug = "starter"
}

