# 1. Enable necessary APIs
resource "google_project_service" "gke_apis" {
  project                    = var.project_id
  service                    = "container.googleapis.com"
  disable_on_destroy         = false
  disable_dependent_services = false
}

resource "google_project_service" "gke_hub" {
  project                    = var.project_id
  service                    = "gkehub.googleapis.com"
  disable_on_destroy         = false
  disable_dependent_services = false
}

resource "google_project_service" "mcs" {
  project                    = var.project_id
  service                    = "multiclusterservicediscovery.googleapis.com"
  disable_on_destroy         = false
  disable_dependent_services = false
}

# 2. Create GKE Autopilot clusters
resource "google_container_cluster" "primary" {
  for_each = var.subnets

  project  = var.project_id
  name     = var.cluster_names[each.key]
  location = each.value.region

  # When enable_autopilot is true, we do not need to manage node pools.
  # The conflicting `remove_default_node_pool` and `initial_node_count` are removed.

  network    = var.network_name
  subnetwork = each.value.name

  # Specify that this is an Autopilot cluster
  enable_autopilot = true

  # Needed for Multi-Cluster Services
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Enable Secret Manager CSI driver addon
  secret_manager_config {
    enabled = true
  }

  # Fleet registration depends on the cluster being created
  depends_on = [
    google_project_service.gke_apis
  ]
}

# 3. Register clusters to the Fleet (GKE Hub)
resource "google_gke_hub_membership" "membership" {
  for_each = google_container_cluster.primary

  project     = var.project_id
  membership_id = each.value.name
  location    = "global" # Fleet memberships are global resources

  endpoint {
    gke_cluster {
      resource_link = "//container.googleapis.com/${each.value.id}"
    }
  }

  depends_on = [
    google_project_service.gke_hub
  ]
}

# 4. Enable Multi-Cluster Services feature on the Fleet
resource "google_gke_hub_feature" "mcs_feature" {
  project  = var.project_id
  name     = "multiclusterservicediscovery"
  location = "global"

  # Wait for all clusters to be members before enabling the feature
  depends_on = [
    google_gke_hub_membership.membership,
    google_project_service.mcs
  ]
} 