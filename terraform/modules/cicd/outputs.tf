# cicd/outputs.tf
# Output values for the CI/CD module

output "service_account_email" {
  description = "Email of the CI/CD service account"
  value       = google_service_account.broadcaster_cicd.email
}

output "service_account_name" {
  description = "Name of the CI/CD service account"
  value       = google_service_account.broadcaster_cicd.name
}

output "service_account_unique_id" {
  description = "Unique ID of the CI/CD service account"
  value       = google_service_account.broadcaster_cicd.unique_id
} 