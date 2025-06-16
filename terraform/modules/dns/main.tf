# DNS Module - Cloud DNS configuration
# This module creates a managed DNS zone for the broadcaster subdomain

resource "google_dns_managed_zone" "broadcaster_zone" {
  name     = "broadcaster-zone"
  dns_name = "${var.subdomain}.${var.domain}."
  
  description = "DNS zone for broadcaster application subdomain"
  
  labels = {
    environment = var.environment
    application = "broadcaster"
  }
}

# A record pointing to the global load balancer IP
resource "google_dns_record_set" "broadcaster_a" {
  name = google_dns_managed_zone.broadcaster_zone.dns_name
  type = "A"
  ttl  = 300

  managed_zone = google_dns_managed_zone.broadcaster_zone.name

  rrdatas = [var.load_balancer_ip]
} 