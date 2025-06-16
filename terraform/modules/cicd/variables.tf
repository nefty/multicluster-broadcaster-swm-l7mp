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