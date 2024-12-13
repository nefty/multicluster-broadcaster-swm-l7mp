provider "azurerm" {
  features {}
}

# Create Resource Groups
resource "azurerm_resource_group" "broadcaster-global_rg" {
  name     = "${var.name-prefix}-rg"
  location = var.regions["1"].location
}

resource "azurerm_traffic_manager_profile" "tm_profile" {
  name                = var.name-prefix
  resource_group_name = azurerm_resource_group.broadcaster-global_rg.name
  traffic_routing_method = "Performance"

  dns_config {
    relative_name = var.name-prefix
    ttl           = 30
  }

  monitor_config {
    protocol = "HTTP"
    port     = 80
    path     = "/"
    expected_status_code_ranges = ["200-399"]
    custom_header {
      name = "host"
      value = "global.broadcaster.stunner.cc"
    }
  }
}

resource "azurerm_traffic_manager_external_endpoint" "tm_endpoint" {
  for_each = var.regions

  name                 = "${var.name-prefix}-endpoint-${each.value.name}"
  profile_id           = azurerm_traffic_manager_profile.tm_profile.id

  always_serve_enabled = false
  priority             = each.key
  weight               = 1
  
  target               = each.value.ip
  endpoint_location    = each.value.location
}

