terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.30"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.4"
    }
  }
  # State holds the APIM subscription key (sensitive). Use a remote backend with RBAC, never a local file in OneDrive:
  # backend "azurerm" {}
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

provider "azapi" {}
