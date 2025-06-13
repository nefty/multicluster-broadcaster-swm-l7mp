output "network_name" {
  description = "The name of the VPC network."
  value       = google_compute_network.vpc.name
}

output "subnets" {
  description = "A map of the created subnets."
  value       = google_compute_subnetwork.subnet
} 