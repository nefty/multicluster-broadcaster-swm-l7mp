# secrets/outputs.tf
# Output values for the secrets module

output "service_account_email" {
  description = "Email of the Google Service Account for Workload Identity"
  value       = google_service_account.broadcaster_secrets_sa.email
}

output "service_account_name" {
  description = "Name of the Google Service Account"
  value       = google_service_account.broadcaster_secrets_sa.name
}

output "secret_names" {
  description = "List of created secret names"
  value       = keys(google_secret_manager_secret.broadcaster_secrets)
}

output "kubernetes_service_account_annotation" {
  description = "The annotation needed for the Kubernetes ServiceAccount"
  value = {
    "iam.gke.io/gcp-service-account" = google_service_account.broadcaster_secrets_sa.email
  }
}

# Sensitive outputs for debugging (use with terraform output -raw)
output "generated_secrets" {
  description = "Generated secret values (sensitive)"
  value       = local.generated_secrets
  sensitive   = true
} 