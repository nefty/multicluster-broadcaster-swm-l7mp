resource "google_compute_network" "vpc" {
  project                 = var.project_id
  name                    = var.network_name
  auto_create_subnetworks = false
  mtu                     = 1500
}

resource "google_compute_subnetwork" "subnet" {
  for_each = var.subnets

  project                  = var.project_id
  name                     = "${var.network_name}-${each.key}"
  ip_cidr_range            = each.value.ip_cidr_range
  region                   = each.value.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods-range"
    ip_cidr_range = each.value.pods_range
  }

  secondary_ip_range {
    range_name    = "services-range"
    ip_cidr_range = each.value.services_range
  }
} 