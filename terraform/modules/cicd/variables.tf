# cicd/variables.tf
# Variable definitions for the CI/CD module

variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "service_account_name" {
  description = "Name for the CI/CD service account"
  type        = string
  default     = "broadcaster-ci-cd"
}

variable "github_app_installation_id" {
  description = "GitHub App installation ID for Cloud Build"
  type        = string
}

variable "github_repo_owner" {
  description = "GitHub repository owner/organization"
  type        = string
}

variable "github_repo_name" {
  description = "GitHub repository name"
  type        = string
}

variable "connection_location" {
  description = "Location for the Cloud Build v2 connection"
  type        = string
  default     = "us-central1"
}

variable "github_pat_secret_version_id" {
  description = "Full resource ID of the GitHub PAT secret version from secrets module"
  type        = string
} 