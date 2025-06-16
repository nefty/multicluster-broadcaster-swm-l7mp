# Load Balancer Module - Global HTTPS Load Balancer for broadcaster application
# This module creates a global load balancer that routes traffic to GKE clusters

# Reserve a global static IP address
resource "google_compute_global_address" "broadcaster_ip" {
  name = "broadcaster-global-ip"
}

# Google-managed SSL certificate
resource "google_compute_managed_ssl_certificate" "broadcaster_ssl" {
  name = "broadcaster-ssl-cert"

  managed {
    domains = ["${var.subdomain}.${var.domain}"]
  }
}

# Backend service configuration for each GKE cluster
resource "google_compute_backend_service" "broadcaster_backend" {
  for_each = var.gke_clusters

  name                  = "broadcaster-backend-${each.key}"
  description           = "Backend service for broadcaster in ${each.key}"
  protocol              = "HTTP"
  timeout_sec           = 30
  enable_cdn            = false
  load_balancing_scheme = "EXTERNAL"

  backend {
    group           = each.value.neg_url
    balancing_mode  = "RATE"
    max_rate        = 100
    capacity_scaler = 1.0
  }

  health_checks = [google_compute_health_check.broadcaster_health_check.id]
}

# Health check for the backend services
resource "google_compute_health_check" "broadcaster_health_check" {
  name = "broadcaster-health-check"

  http_health_check {
    port         = 4000
    request_path = "/health"
  }

  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3
}

# URL map for routing
resource "google_compute_url_map" "broadcaster_url_map" {
  name        = "broadcaster-url-map"
  description = "URL map for broadcaster application"

  default_service = google_compute_backend_service.broadcaster_backend[var.default_region].id
}

# HTTPS proxy
resource "google_compute_target_https_proxy" "broadcaster_https_proxy" {
  name             = "broadcaster-https-proxy"
  url_map          = google_compute_url_map.broadcaster_url_map.id
  ssl_certificates = [google_compute_managed_ssl_certificate.broadcaster_ssl.id]
}

# HTTP proxy (redirects to HTTPS)
resource "google_compute_target_http_proxy" "broadcaster_http_proxy" {
  name    = "broadcaster-http-proxy"
  url_map = google_compute_url_map.broadcaster_redirect_url_map.id
}

# URL map for HTTP to HTTPS redirect
resource "google_compute_url_map" "broadcaster_redirect_url_map" {
  name = "broadcaster-redirect-url-map"

  default_url_redirect {
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
    https_redirect         = true
  }
}

# Global forwarding rule for HTTPS traffic
resource "google_compute_global_forwarding_rule" "broadcaster_https_forwarding_rule" {
  name       = "broadcaster-https-forwarding-rule"
  target     = google_compute_target_https_proxy.broadcaster_https_proxy.id
  port_range = "443"
  ip_address = google_compute_global_address.broadcaster_ip.address
}

# Global forwarding rule for HTTP traffic (redirects to HTTPS)
resource "google_compute_global_forwarding_rule" "broadcaster_http_forwarding_rule" {
  name       = "broadcaster-http-forwarding-rule"
  target     = google_compute_target_http_proxy.broadcaster_http_proxy.id
  port_range = "80"
  ip_address = google_compute_global_address.broadcaster_ip.address
} 