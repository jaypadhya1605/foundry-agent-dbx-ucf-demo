# Custom agent runtime: an Azure Container Apps job that runs the Python MCP client with its own managed identity and
# calls APIM /uc-entra/mcp with an Entra token (no key anywhere). Stands in for AKS; on AKS the same client uses
# --auth workload with a federated credential on azurerm_user_assigned_identity.runtime.

resource "azurerm_container_app_environment" "runtime" {
  count                      = var.enable_entra_api && var.enable_runtime ? 1 : 0
  name                       = "cae-${var.prefix}-runtime"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }
}

resource "azurerm_container_app_job" "agent" {
  count                        = var.enable_entra_api && var.enable_runtime ? 1 : 0
  name                         = "job-${var.prefix}-agent"
  location                     = var.location
  resource_group_name          = var.resource_group_name
  container_app_environment_id = azurerm_container_app_environment.runtime[0].id
  workload_profile_name        = "Consumption"
  replica_timeout_in_seconds   = 300
  replica_retry_limit          = 0

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.runtime[0].id]
  }

  manual_trigger_config {
    parallelism              = 1
    replica_completion_count = 1
  }

  template {
    container {
      name    = "uc-agent"
      image   = var.runtime_image
      cpu     = 0.25
      memory  = "0.5Gi"
      command = ["python3", "-c", "import base64,os,sys;sys.argv=[\"client\"]+os.environ.get(\"CLIENT_ARGS\",\"\").split();exec(compile(base64.b64decode(os.environ[\"CLIENT_B64\"]),\"python_mcp_client.py\",\"exec\"))"]

      env {
        name  = "CLIENT_B64"
        value = filebase64("${path.module}/../../clients/python_mcp_client.py")
      }
      env {
        name  = "CLIENT_ARGS"
        value = "--facility ${var.runtime_facility}"
      }
      env {
        name  = "APIM_MCP_URL"
        value = "https://${azurerm_api_management.apim.name}.azure-api.net/uc-entra/mcp"
      }
      env {
        name  = "APIM_AUTH"
        value = "mi"
      }
      env {
        name  = "APIM_AUDIENCE"
        value = local.entra_audience
      }
      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.runtime[0].client_id
      }
      env {
        name  = "PYTHONUNBUFFERED"
        value = "1"
      }
    }
  }
}
