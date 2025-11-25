data "digitalocean_ssh_key" "main" {
  name = "pyron"
}

resource "digitalocean_droplet" "main" {
  image    = "ubuntu-24-04-x64"
  name     = var.droplet_name
  region   = var.region
  size     = "s-1vcpu-1gb"
  backups  = false
  ssh_keys = [data.digitalocean_ssh_key.main.id]
  user_data = file("cloud-init.yaml")
}

resource "digitalocean_firewall" "main" {
  name = "only-ssh-and-https"

  droplet_ids = [digitalocean_droplet.main.id]

  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Enabled temporarely in case ACME Challenge needs it.
  inbound_rule {
    protocol         = "tcp"
    port_range       = "80"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}