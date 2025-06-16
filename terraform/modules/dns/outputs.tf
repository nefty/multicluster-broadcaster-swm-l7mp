output "managed_zone_name" {
  description = "Name of the managed DNS zone"
  value       = google_dns_managed_zone.broadcaster_zone.name
}

output "dns_name" {
  description = "DNS name of the managed zone"
  value       = google_dns_managed_zone.broadcaster_zone.dns_name
}

output "name_servers" {
  description = "Name servers for the managed zone (to configure at domain registrar)"
  value       = google_dns_managed_zone.broadcaster_zone.name_servers
}

output "zone_id" {
  description = "ID of the managed zone"
  value       = google_dns_managed_zone.broadcaster_zone.id
} 