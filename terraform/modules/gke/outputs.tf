output "clusters" {
  description = "A map of the created GKE clusters."
  value       = google_container_cluster.primary
}

output "memberships" {
  description = "The Fleet memberships for the created clusters."
  value       = google_gke_hub_membership.membership
} 