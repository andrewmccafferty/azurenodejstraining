
terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # Root module should specify the maximum provider version
      # The ~> operator is a convenient shorthand for allowing only patch releases within a specific minor release.
      version = "=3.111.0"
    }
  }
}

provider "azurerm" {
  features {}
  skip_provider_registration = true
}

data "azurerm_resource_group" "resource_group" {
  name = "rg-andrewmccafferty-training"
}

resource "azurerm_storage_account" "storage_account" {
  name = "${var.project}${var.environment}storage"
  resource_group_name = data.azurerm_resource_group.resource_group.name
  location = var.location
  account_tier = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_application_insights" "application_insights" {
  name                = "${var.project}-${var.environment}-application-insights"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.resource_group.name
  application_type    = "Node.JS"
}

resource "azurerm_service_plan" "service_plan" {
  name                = "${var.project}-${var.environment}-service-plan"
  resource_group_name = data.azurerm_resource_group.resource_group.name
  location            = var.location
  os_type             = "Linux"
  sku_name            = "Y1"
}

# resource "azurerm_app_service_plan" "app_service_plan" {
#   name                = "${var.project}-${var.environment}-app-service-plan"
#   resource_group_name = data.azurerm_resource_group.resource_group.name
#   location            = var.location
#   kind                = "FunctionApp"
#   reserved = true # this has to be set to true for Linux. Not related to the Premium Plan
#   sku {
#     tier = "Dynamic"
#     size = "Y1"
#   }
# }

resource "azurerm_linux_function_app" "function_app" {
  name                       = "${var.project}-${var.environment}-function-app"
  resource_group_name        = data.azurerm_resource_group.resource_group.name
  location                   = var.location
  service_plan_id        = azurerm_service_plan.service_plan.id
  app_settings = {
    # "WEBSITE_RUN_FROM_PACKAGE" = "",
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.application_insights.instrumentation_key,
    "SIGHTINGS_DB_NAME": azurerm_cosmosdb_sql_database.sightings_database.name,
    "SIGHTINGS_DB_CONTAINER_NAME": azurerm_cosmosdb_sql_container.sightings_database_container.name,
    "SIGHTINGS_DB_MASTER_KEY": azurerm_cosmosdb_account.sightings_database_account.primary_key,
    "SIGHTINGS_DB_ENDPOINT": azurerm_cosmosdb_account.sightings_database_account.endpoint
  }
  site_config {
    application_stack {
      node_version = "20"
    }
  }
  storage_account_name       = azurerm_storage_account.storage_account.name
  storage_account_access_key = azurerm_storage_account.storage_account.primary_access_key

  # lifecycle {
  #   ignore_changes = [
  #     app_settings["WEBSITE_RUN_FROM_PACKAGE"],
  #   ]
  # }
}

# resource "azurerm_function_app" "function_app" {
#   name                       = "${var.project}-${var.environment}-function-app"
#   resource_group_name        = data.azurerm_resource_group.resource_group.name
#   location                   = var.location
#   app_service_plan_id        = azurerm_app_service_plan.app_service_plan.id
#   app_settings = {
#     "WEBSITE_RUN_FROM_PACKAGE" = "",
#     "FUNCTIONS_WORKER_RUNTIME" = "node",
#     "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.application_insights.instrumentation_key,
#     "SIGHTINGS_DB_NAME": azurerm_cosmosdb_sql_database.sightings_database.name,
#     "SIGHTINGS_DB_CONTAINER_NAME": azurerm_cosmosdb_sql_container.sightings_database_container.name,
#     "SIGHTINGS_DB_MASTER_KEY": azurerm_cosmosdb_account.sightings_database_account.primary_key,
#     "SIGHTINGS_DB_ENDPOINT": azurerm_cosmosdb_account.sightings_database_account.endpoint
#   }
#   os_type = "linux"
#   site_config {
#     linux_fx_version          = "node|20"
#     use_32_bit_worker_process = false
#   }
#   storage_account_name       = azurerm_storage_account.storage_account.name
#   storage_account_access_key = azurerm_storage_account.storage_account.primary_access_key
#   version                    = "~4"

#   lifecycle {
#     ignore_changes = [
#       app_settings["WEBSITE_RUN_FROM_PACKAGE"],
#     ]
#   }
# }

# Database resources
resource "azurerm_cosmosdb_account" "sightings_database_account" {
  name                       = "andrewmccaffertykc-sightings-account"
  location                   = var.location
  resource_group_name        = data.azurerm_resource_group.resource_group.name
  offer_type                 = "Standard"
  kind                       = "GlobalDocumentDB"
  automatic_failover_enabled  = false
  analytical_storage_enabled = true
  geo_location {
    location          = var.location
    failover_priority = 0
  }

  consistency_policy {
    consistency_level       = "BoundedStaleness"
    max_interval_in_seconds = 300
    max_staleness_prefix    = 100000
  }
}

resource "azurerm_cosmosdb_sql_database" "sightings_database" {
  name                = "andrewmccaffertykc-sightings-db"
  resource_group_name = data.azurerm_resource_group.resource_group.name
  account_name        = azurerm_cosmosdb_account.sightings_database_account.name
  autoscale_settings {
    max_throughput = 1000    
  }
}

resource "azurerm_cosmosdb_sql_container" "sightings_database_container" {
  name                   = "andrewmccaffertykc-sightings-container"
  resource_group_name    = data.azurerm_resource_group.resource_group.name
  account_name           = azurerm_cosmosdb_account.sightings_database_account.name
  database_name          = azurerm_cosmosdb_sql_database.sightings_database.name
  partition_key_paths     = ["/definition/id"]
  partition_key_version  = 1
  autoscale_settings {
    max_throughput = 1000
  }
  analytical_storage_ttl = -1

  indexing_policy {
    indexing_mode = "none"

    # included_path {
    #   path = "/*"
    # }

    # included_path {
    #   path = "/included/?"
    # }

    # excluded_path {
    #   path = "/excluded/?"
    # }
  }

  unique_key {
    paths = ["/definition/idlong", "/definition/idshort"]
  }
}

# data "archive_file" "file_function_app" {
#  type        = "zip"
#  source_dir  = "../"
#  output_path = "function-app.zip"
# }

# resource "azurerm_storage_container" "storage_container" {
#  name                  = "vhds"
#  storage_account_name  = azurerm_storage_account.storage_account.name
#  container_access_type = "private"
# }

# resource "azurerm_storage_blob" "storage_blob" {
#  name = "${filesha256(data.archive_file.file_function_app.output_path)}.zip"
#  storage_account_name = azurerm_storage_account.storage_account.name
#  storage_container_name = azurerm_storage_container.storage_container.name
#  type = "Block"
#  source = data.archive_file.file_function_app.output_path
# }

# data "azurerm_storage_account_blob_container_sas" "storage_account_blob_container_sas" {
#  connection_string = azurerm_storage_account.storage_account.primary_connection_string
#  container_name    = azurerm_storage_container.storage_container.name

#  start = "2024-07-01T00:00:00Z"
#  expiry = "2024-07-07T00:00:00Z"

#  permissions {
#    read   = true
#    add    = false
#    create = false
#    write  = false
#    delete = false
#    list   = false
#  }
# }