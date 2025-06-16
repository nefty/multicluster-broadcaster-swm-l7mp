output "load_balancer_ip" {
  description = "Global IP address of the load balancer"
  value       = module.load_balancer.global_ip_address
}

output "dns_name_servers" {
  description = "Name servers to configure at your domain registrar"
  value       = module.dns.name_servers
}

output "dns_zone_name" {
  description = "Name of the created DNS zone"
  value       = module.dns.dns_name
}

output "ssl_certificate_status" {
  description = "SSL certificate ID (check status in GCP Console)"
  value       = module.load_balancer.ssl_certificate_id
}

output "backend_services" {
  description = "Backend services by region"
  value       = module.load_balancer.backend_services
}

output "gke_clusters" {
  description = "GKE cluster information"
  value = {
    for region, cluster in module.gke.clusters : region => {
      name     = cluster.name
      location = cluster.location
      endpoint = cluster.endpoint
    }
  }
}

# Secrets module outputs
output "secrets_service_account_email" {
  description = "Email of the Google Service Account for accessing secrets"
  value       = module.secrets.service_account_email
}

output "kubernetes_service_account_annotation" {
  description = "The annotation needed for the Kubernetes ServiceAccount"
  value       = module.secrets.kubernetes_service_account_annotation
}

output "secret_names" {
  description = "List of created secret names in Secret Manager"
  value       = module.secrets.secret_names
}

# CI/CD module outputs
output "cicd_service_account_email" {
  description = "Email of the CI/CD service account"
  value       = module.cicd.service_account_email
}
