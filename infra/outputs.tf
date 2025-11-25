output "droplet_ip" {
  value = digitalocean_droplet.main.ipv4_address
}