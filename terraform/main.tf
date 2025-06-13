terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.51.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = "us-central1" // Default region for provider-level operations
}

module "networking" {
  source       = "./modules/networking"
  project_id   = var.project_id
  network_name = "broadcaster-vpc"
  subnets      = var.subnets
}

module "gke" {
  source       = "./modules/gke"
  project_id   = var.project_id
  network_name = module.networking.network_name
  subnets      = module.networking.subnets

  depends_on = [module.networking]
}
