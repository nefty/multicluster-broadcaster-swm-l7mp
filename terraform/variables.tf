variable "project_id" {
  description = "The GCP project ID to deploy resources into."
  type        = string
}

variable "domain" {
  description = "The root domain name (e.g., example.com)"
  type        = string
}

variable "subnets" {
  description = "Configuration for the VPC subnets."
  type = map(object({
    region         = string
    ip_cidr_range  = string
    pods_range     = string
    services_range = string
  }))
  default = {
    "us-east5" = {
      region         = "us-east5"
      ip_cidr_range  = "10.10.1.0/24"
      pods_range     = "10.20.0.0/16"
      services_range = "10.30.0.0/16"
    },
    "europe-west9" = {
      region         = "europe-west9"
      ip_cidr_range  = "10.10.2.0/24"
      pods_range     = "10.40.0.0/16"
      services_range = "10.50.0.0/16"
    },
    "asia-southeast1" = {
      region         = "asia-southeast1"
      ip_cidr_range  = "10.10.3.0/24"
      pods_range     = "10.60.0.0/16"
      services_range = "10.70.0.0/16"
    }
  }
}
