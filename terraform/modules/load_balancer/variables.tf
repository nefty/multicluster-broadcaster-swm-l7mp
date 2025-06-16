variable "subdomain" {
  description = "The subdomain for the broadcaster application"
  type        = string
  default     = "broadcaster"
}

variable "domain" {
  description = "The root domain name (e.g., example.com)"
  type        = string
}

variable "gke_clusters" {
  description = "Map of GKE clusters with their NEG URLs"
  type = map(object({
    neg_url = string
    region  = string
  }))
}

variable "default_region" {
  description = "Default region to route traffic to"
  type        = string
  default     = "us-east5"
} 