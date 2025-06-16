# secrets/main.tf
# This module manages secrets in Google Secret Manager and sets up IAM permissions
# for accessing them from GKE clusters using Workload Identity

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.51.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.1.0"
    }
  }
}

# Generate secure random values for secrets if not provided
resource "random_id" "erlang_cookie_suffix" {
  byte_length = 16
}

resource "random_password" "secret_key_base" {
  length  = 64
  special = true
}

resource "random_password" "admin_password" {
  length  = 16
  special = true
}

resource "random_password" "whip_token" {
  length  = 16
  special = false
}

resource "random_password" "ice_server_username" {
  length  = 12
  special = false
}

resource "random_password" "ice_server_credential" {
  length  = 24
  special = true
}

# Secret Manager secrets
resource "google_secret_manager_secret" "broadcaster_secrets" {
  for_each = var.secrets

  secret_id = each.key
  
  replication {
    auto {}
  }

  labels = {
    app         = "broadcaster"
    environment = var.environment
  }
}

# Secret versions with actual values
resource "google_secret_manager_secret_version" "broadcaster_secret_versions" {
  for_each = var.secrets

  secret      = google_secret_manager_secret.broadcaster_secrets[each.key].id
  secret_data_wo = each.value.use_generated ? local.generated_secrets[each.key] : each.value.value
}

# Google Service Account for Workload Identity
resource "google_service_account" "broadcaster_secrets_sa" {
  account_id   = var.service_account_name
  display_name = "Broadcaster Secrets Service Account"
  description  = "Service account for accessing Secret Manager from GKE pods"
}

# Grant Secret Manager Secret Accessor role to the service account
resource "google_project_iam_member" "secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.broadcaster_secrets_sa.email}"
}

# Workload Identity bindings for each cluster
resource "google_service_account_iam_member" "workload_identity_binding" {
  for_each = var.cluster_regions

  service_account_id = google_service_account.broadcaster_secrets_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.kubernetes_namespace}/${var.kubernetes_service_account}]"
}

# Enable required APIs
resource "google_project_service" "secretmanager" {
  service = "secretmanager.googleapis.com"
  
  disable_dependent_services = true
}

# GitHub Personal Access Token secret for Cloud Build integration
resource "google_secret_manager_secret" "github_pat" {
  secret_id = "github-pat"
  
  replication {
    auto {}
  }

  labels = {
    app         = "broadcaster"
    environment = var.environment
    purpose     = "cicd"
  }
}

resource "google_secret_manager_secret_version" "github_pat_version" {
  secret        = google_secret_manager_secret.github_pat.id
  secret_data_wo = var.github_pat
}

# Grant Cloud Build Service Agent access to the GitHub PAT secret
data "google_iam_policy" "cloudbuild_secretAccessor" {
  binding {
    role = "roles/secretmanager.secretAccessor"
    members = ["serviceAccount:service-${var.project_number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"]
  }
}

resource "google_secret_manager_secret_iam_policy" "github_pat_policy" {
  project     = var.project_id
  secret_id   = google_secret_manager_secret.github_pat.secret_id
  policy_data = data.google_iam_policy.cloudbuild_secretAccessor.policy_data
}

# Local values for generated secrets
locals {
  generated_secrets = {
    "broadcaster-erlang-cookie"         = "multicluster-broadcaster-cookie-${random_id.erlang_cookie_suffix.hex}"
    "broadcaster-secret-key-base"       = random_password.secret_key_base.result
    "broadcaster-admin-password"        = random_password.admin_password.result
    "broadcaster-whip-token"            = random_password.whip_token.result
    "broadcaster-ice-server-username"   = random_password.ice_server_username.result
    "broadcaster-ice-server-credential" = random_password.ice_server_credential.result
    "broadcaster-admin-username"        = "admin"
  }
} 