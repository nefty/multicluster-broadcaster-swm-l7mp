variable "name-prefix" {
  description = "Prefix for the name of the resources"
  type        = string
  default     = "broadcaster-global" 
}

variable "regions" {
  description = "List of Hetzner VMs"
  type        = map(object({
    name     = string
    location = string
    ip       = string
  }))
  default     = {
    "1" = {name = "germany", location = "Germany West Central", ip = "116.203.254.213"}, 
    "2" = {name = "oregon", location = "West US 2", ip = "5.78.69.126"}, 
    "3" = {name = "singapore", location ="Southeast Asia", ip = "5.223.46.141"},
    }
}



