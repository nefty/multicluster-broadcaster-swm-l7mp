# cicd/main.tf
# This module manages the CI/CD service account and its IAM permissions

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.51.0"
    }
  }
}

# CI/CD Service Account for Cloud Build
resource "google_service_account" "broadcaster_cicd" {
  account_id   = var.service_account_name
  display_name = "Broadcaster CI/CD Service Account"
  description  = "Service account for Cloud Build CI/CD pipeline"
  project      = var.project_id
}

# IAM bindings for the CI/CD service account
resource "google_project_iam_member" "cicd_artifact_registry_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.broadcaster_cicd.email}"
}

resource "google_project_iam_member" "cicd_container_admin" {
  project = var.project_id
  role    = "roles/container.admin"
  member  = "serviceAccount:${google_service_account.broadcaster_cicd.email}"
}

resource "google_project_iam_member" "cicd_logging_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.broadcaster_cicd.email}"
}

# Create the GitHub connection using Cloud Build v2
resource "google_cloudbuildv2_connection" "github_connection" {
  project  = var.project_id
  location = var.connection_location
  name     = "broadcaster-github-connection"

  github_config {
    app_installation_id = var.github_app_installation_id
    authorizer_credential {
      oauth_token_secret_version = var.github_pat_secret_version_id
    }
  }
}

# Create the repository link
resource "google_cloudbuildv2_repository" "github_repo" {
  project           = var.project_id
  location          = var.connection_location
  name              = var.github_repo_name
  parent_connection = google_cloudbuildv2_connection.github_connection.name
  remote_uri        = "https://github.com/${var.github_repo_owner}/${var.github_repo_name}.git"
}

# Create the Cloud Build trigger
resource "google_cloudbuild_trigger" "deploy_main" {
  project     = var.project_id
  location    = var.connection_location
  name        = "deploy-main"
  description = "Deploy broadcaster on push to main branch"

  service_account = google_service_account.broadcaster_cicd.id

  repository_event_config {
    repository = google_cloudbuildv2_repository.github_repo.id
    push {
      branch = "^main$"
    }
  }

  filename = "cloudbuild.yaml"

  depends_on = [google_cloudbuildv2_repository.github_repo]
} 