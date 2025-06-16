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

output "github_connection_name" {
  description = "Name of the GitHub connection"
  value       = google_cloudbuildv2_connection.github_connection.name
}

output "build_trigger_id" {
  description = "ID of the Cloud Build trigger"
  value       = google_cloudbuild_trigger.deploy_main.trigger_id
}

output "repository_id" {
  description = "ID of the GitHub repository"
  value       = google_cloudbuildv2_repository.github_repo.id
} 