output "global_ip_address" {
  description = "The global IP address of the load balancer"
  value       = google_compute_global_address.broadcaster_ip.address
}

output "global_ip_name" {
  description = "The name of the global IP address resource"
  value       = google_compute_global_address.broadcaster_ip.name
}

output "ssl_certificate_id" {
  description = "ID of the managed SSL certificate"
  value       = google_compute_managed_ssl_certificate.broadcaster_ssl.id
}

output "url_map_id" {
  description = "ID of the URL map"
  value       = google_compute_url_map.broadcaster_url_map.id
}

output "backend_services" {
  description = "Map of backend service IDs by region"
  value       = {
    for region, backend in google_compute_backend_service.broadcaster_backend : region => backend.id
  }
} 