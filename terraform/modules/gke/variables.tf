variable "project_id" {
  description = "The ID of the GCP project."
  type        = string
}

variable "network_name" {
  description = "The name of the VPC network to which the GKE clusters will be attached."
  type        = string
}

variable "subnets" {
  description = "The map of subnets where GKE clusters will be created. Passed from the networking module."
  type = map(object({
    self_link              = string
    name                   = string
    region                 = string
    secondary_ip_range     = list(object({ range_name = string, ip_cidr_range = string }))
  }))
}

variable "cluster_names" {
  description = "A map of cluster names, keyed by region."
  type        = map(string)
  default = {
    "us-west1"        = "broadcaster-us"
    "europe-west1"    = "broadcaster-eu"
    "asia-southeast1" = "broadcaster-asia"
  }
} 