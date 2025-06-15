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

  lifecycle {
    ignore_changes = [
      secondary_ip_range,
    ]
  }
}

resource "google_compute_firewall" "allow_internal" {
  project = var.project_id
  name    = "${var.network_name}-allow-internal"
  network = google_compute_network.vpc.name

  allow {
    protocol = "all"
  }

  source_ranges = [
    for s in google_compute_subnetwork.subnet : s.ip_cidr_range
  ]
}