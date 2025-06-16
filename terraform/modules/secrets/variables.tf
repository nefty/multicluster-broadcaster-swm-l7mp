# secrets/variables.tf
# Variable definitions for the secrets module

variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., production, staging)"
  type        = string
  default     = "production"
}

variable "service_account_name" {
  description = "Name for the Google Service Account used for Workload Identity"
  type        = string
  default     = "broadcaster-secrets-sa"
}

variable "kubernetes_namespace" {
  description = "Kubernetes namespace where the service account will be created"
  type        = string
  default     = "default"
}

variable "kubernetes_service_account" {
  description = "Name of the Kubernetes service account"
  type        = string
  default     = "broadcaster-sa"
}

variable "cluster_regions" {
  description = "Set of GKE cluster regions for Workload Identity binding"
  type        = set(string)
}

variable "secrets" {
  description = "Map of secrets to create in Secret Manager"
  type = map(object({
    use_generated = bool   # Whether to use generated value or provided value
    value         = string # Value to use if use_generated is false
  }))
  default = {
    "broadcaster-erlang-cookie" = {
      use_generated = true
      value         = ""
    }
    "broadcaster-secret-key-base" = {
      use_generated = true
      value         = ""
    }
    "broadcaster-admin-username" = {
      use_generated = true
      value         = ""
    }
    "broadcaster-admin-password" = {
      use_generated = true
      value         = ""
    }
    "broadcaster-whip-token" = {
      use_generated = true
      value         = ""
    }
    "broadcaster-ice-server-username" = {
      use_generated = true
      value         = ""
    }
    "broadcaster-ice-server-credential" = {
      use_generated = true
      value         = ""
    }
  }
} 