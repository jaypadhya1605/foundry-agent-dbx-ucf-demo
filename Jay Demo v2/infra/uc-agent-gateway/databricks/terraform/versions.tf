terraform {
  required_version = ">= 1.6"
  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.80"
    }
  }
  # State may hold the OAuth app secret if create_oauth_app = true. Use a secured remote backend.
  # backend "azurerm" {}
}

# Account-level: groups, service principal, workspace assignment, OAuth app. Needs an account admin.
provider "databricks" {
  alias      = "account"
  host       = "https://accounts.azuredatabricks.net"
  account_id = var.account_id
  auth_type  = "azure-cli"
}

# Workspace-level: grants, warehouse permissions, UC objects. Needs a workspace admin / catalog owner.
provider "databricks" {
  alias     = "workspace"
  host      = "https://${var.databricks_host}"
  auth_type = "azure-cli"
}
