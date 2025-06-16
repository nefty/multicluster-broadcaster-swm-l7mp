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

# Get available zones for each region
data "google_compute_zones" "available" {
  for_each = var.subnets
  region   = each.value.region
}

# Create NEGs for each cluster to connect to the load balancer
resource "google_compute_network_endpoint_group" "broadcaster_neg" {
  for_each = var.subnets

  name         = "broadcaster-neg-${each.key}"
  network      = module.networking.network_name
  subnetwork   = module.networking.subnets[each.key].name
  default_port = "4000"
  zone         = data.google_compute_zones.available[each.key].names[0]  # Use first available zone

  depends_on = [module.gke]
}

module "load_balancer" {
  source = "./modules/load_balancer"
  
  domain    = var.domain
  subdomain = "broadcaster"
  
  gke_clusters = {
    for region, subnet in var.subnets : region => {
      neg_url = google_compute_network_endpoint_group.broadcaster_neg[region].id
      region  = region
    }
  }
  
  default_region = "us-east5"
  
  depends_on = [module.gke]
}

module "dns" {
  source = "./modules/dns"
  
  domain            = var.domain
  subdomain         = "broadcaster"
  environment       = "production"
  load_balancer_ip  = module.load_balancer.global_ip_address
  
  depends_on = [module.load_balancer]
}

# Secret Manager and IAM setup for accessing secrets from GKE
module "secrets" {
  source = "./modules/secrets"
  
  project_id       = var.project_id
  project_number   = var.project_number
  environment      = "production"
  cluster_regions  = toset(keys(var.subnets))
  github_pat       = var.github_pat
  
  depends_on = [module.gke]
}

# CI/CD service account for Cloud Build
module "cicd" {
  source = "./modules/cicd"
  
  project_id                    = var.project_id
  github_app_installation_id   = var.github_app_installation_id
  github_repo_owner             = var.github_repo_owner
  github_repo_name              = var.github_repo_name
  github_pat_secret_version_id  = module.secrets.github_pat_secret_version_id
  
  depends_on = [module.secrets]
}
