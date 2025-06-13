variable "project_id" {
  description = "The ID of the GCP project."
  type        = string
}

variable "network_name" {
  description = "The name for the VPC network."
  type        = string
  default     = "broadcaster-vpc"
}

variable "subnets" {
  description = "A map of subnets to create. Key is the region."
  type = map(object({
    region        = string
    ip_cidr_range = string
    pods_range    = string
    services_range = string
  }))
} 