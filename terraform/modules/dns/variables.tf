variable "subdomain" {
  description = "The subdomain for the broadcaster application"
  type        = string
  default     = "broadcaster"
}

variable "domain" {
  description = "The root domain name (e.g., brianeft.com)"
  type        = string
}

variable "environment" {
  description = "Environment name for labeling"
  type        = string
  default     = "production"
}

variable "load_balancer_ip" {
  description = "IP address of the global load balancer"
  type        = string
} 