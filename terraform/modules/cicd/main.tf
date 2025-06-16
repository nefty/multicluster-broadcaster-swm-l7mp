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

resource "google_project_iam_member" "cicd_developer_connect_read_token_accessor" {
  project = var.project_id
  role    = "roles/developerconnect.readTokenAccessor"
  member  = "serviceAccount:${google_service_account.broadcaster_cicd.email}"
}

resource "google_project_iam_member" "cicd_logging_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.broadcaster_cicd.email}"
} 