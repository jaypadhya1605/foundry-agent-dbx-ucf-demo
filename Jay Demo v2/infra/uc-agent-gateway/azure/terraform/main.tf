locals {
  # Well-known Azure Databricks first-party application ID (token audience for managed identity).
  databricks_resource = "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d"
  apim_name           = "apim-${var.prefix}-${var.name_suffix}"
  uc_rewrite          = "/api/2.0/mcp/functions/${var.uc_catalog}/${var.uc_schema}"

  mcp_apis = merge(
    {
      uc = {
        name                      = "imh-uc-functions-mcp"
        display_name              = "IMH UC functions MCP (via UMI)"
        path                      = "uc"
        kind                      = "key"
        rewrite                   = local.uc_rewrite
        key_required              = true
        subscription              = "foundry-imh-uc-agent"
        subscription_display_name = "Foundry agent imh-uc-apim-umi-agent"
        foundry_connection        = var.foundry_connection_name
      }
    },
    var.genie_space_id == "" ? {} : {
      genie = {
        name                      = "imh-genie-mcp"
        display_name              = "IMH Genie space MCP (via UMI)"
        path                      = "genie"
        kind                      = "key"
        rewrite                   = "/api/2.0/mcp/genie/${var.genie_space_id}"
        key_required              = true
        subscription              = "foundry-imh-genie-agent"
        subscription_display_name = "Foundry agent (Genie via APIM)"
        foundry_connection        = "genie-via-apim-umi-iac"
      }
    },
    !var.enable_limited_api ? {} : {
      limited = {
        name                      = "imh-uc-functions-mcp-limited"
        display_name              = "IMH UC functions MCP - limited (rate, quota, size cap)"
        path                      = "uc-limited"
        kind                      = "limited"
        rewrite                   = local.uc_rewrite
        key_required              = true
        subscription              = "imh-uc-limited-client"
        subscription_display_name = "Limited client (demo 429 and size cap)"
        foundry_connection        = "uc-limited-via-apim-umi-iac"
      }
    },
    !var.enable_entra_api ? {} : {
      entra = {
        name                      = "imh-uc-functions-mcp-entra"
        display_name              = "IMH UC functions MCP - Entra token (no key)"
        path                      = "uc-entra"
        kind                      = "entra"
        rewrite                   = local.uc_rewrite
        key_required              = false
        subscription              = ""
        subscription_display_name = ""
        foundry_connection        = ""
      }
    }
  )
  key_apis = { for k, a in local.mcp_apis : k => a if a.key_required }

  mcp_methods = { "mcp-post" = "POST", "mcp-get" = "GET", "mcp-delete" = "DELETE" }
  operations = merge([
    for k, a in local.mcp_apis : {
      for op, method in local.mcp_methods : "${k}/${op}" => { api = k, name = op, method = method }
    }
  ]...)

  # ---------- Policies (shared with Bicep: ../policy-*.xml) ----------
  entra_audience  = var.gateway_audience == "" ? "https://management.azure.com" : var.gateway_audience
  entra_audiences = distinct(concat([local.entra_audience, "${local.entra_audience}/"], startswith(local.entra_audience, "api://") ? [substr(local.entra_audience, 6, -1)] : []))
  entra_clients   = concat(var.enable_entra_api ? [azurerm_user_assigned_identity.runtime[0].client_id] : [], var.allowed_client_app_ids)

  policy_raw = {
    key     = replace(file("${path.module}/../policy-mcp-key.xml"), "__CALLS__", tostring(var.calls_per_minute))
    limited = replace(replace(replace(replace(file("${path.module}/../policy-mcp-limited.xml"), "__TOOLCALLS__", tostring(var.limited_tool_calls_per_minute)), "__QUOTA__", tostring(var.limited_daily_quota)), "__MAXROWS__", tostring(var.limited_max_rows)), "__MAXBYTES__", tostring(var.limited_max_response_bytes))
    entra = replace(replace(replace(replace(file("${path.module}/../policy-mcp-entra.xml"),
      "__CALLS__", tostring(var.calls_per_minute)),
      "__TENANT__", data.azurerm_client_config.current.tenant_id),
      "__AUDIENCES__", join("", [for a in local.entra_audiences : "<audience>${a}</audience>"])),
    "__CLIENTS__", join("", [for c in local.entra_clients : "<application-id>${c}</application-id>"]))
  }
}

data "azurerm_client_config" "current" {}

resource "azurerm_user_assigned_identity" "agent" {
  name                = "umi-${var.prefix}-agent"
  location            = var.location
  resource_group_name = var.resource_group_name
}

# Identity of the custom agent runtime (AKS workload identity / Container Apps job). It only proves who is calling
# APIM; Databricks still sees the APIM identity above.
resource "azurerm_user_assigned_identity" "runtime" {
  count               = var.enable_entra_api ? 1 : 0
  name                = "umi-${var.prefix}-runtime"
  location            = var.location
  resource_group_name = var.resource_group_name
}

resource "azurerm_log_analytics_workspace" "law" {
  name                = "law-${var.prefix}-${var.name_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_api_management" "apim" {
  name                = local.apim_name
  location            = var.location
  resource_group_name = var.resource_group_name
  publisher_name      = var.publisher_name
  publisher_email     = var.publisher_email
  sku_name            = var.apim_sku

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.agent.id]
  }
}

resource "azurerm_api_management_api" "mcp" {
  for_each              = local.mcp_apis
  name                  = each.value.name
  resource_group_name   = var.resource_group_name
  api_management_name   = azurerm_api_management.apim.name
  revision              = "1"
  display_name          = each.value.display_name
  path                  = each.value.path
  protocols             = ["https"]
  service_url           = "https://${var.databricks_host}"
  subscription_required = each.value.key_required

  subscription_key_parameter_names {
    header = "Ocp-Apim-Subscription-Key"
    query  = "subscription-key"
  }
}

resource "azurerm_api_management_api_operation" "mcp" {
  for_each            = local.operations
  operation_id        = each.value.name
  api_name            = azurerm_api_management_api.mcp[each.value.api].name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = var.resource_group_name
  display_name        = "MCP ${each.value.method}"
  method              = each.value.method
  url_template        = "/mcp"
}

resource "azurerm_api_management_api_policy" "mcp" {
  for_each            = local.mcp_apis
  api_name            = azurerm_api_management_api.mcp[each.key].name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = var.resource_group_name

  xml_content = replace(replace(replace(local.policy_raw[each.value.kind],
    "__REWRITE__", each.value.rewrite),
    "__RESOURCE__", local.databricks_resource),
  "__CLIENT_ID__", azurerm_user_assigned_identity.agent.client_id)

  depends_on = [azurerm_api_management_api_operation.mcp]
}

# One key per key-based API. APIM generates the keys; Terraform state holds them, so keep state in a secured remote backend.
resource "azurerm_api_management_subscription" "mcp" {
  for_each            = local.key_apis
  subscription_id     = each.value.subscription
  display_name        = each.value.subscription_display_name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = var.resource_group_name
  api_id              = replace(azurerm_api_management_api.mcp[each.key].id, "/;rev=.*/", "")
  state               = "active"
}

# ---------- Foundry models behind APIM (Databricks -> APIM -> Foundry) ----------

# Cognitive Services OpenAI User for the APIM identity on the model account.
resource "azurerm_role_assignment" "model" {
  count                = var.model_account_id == "" ? 0 : 1
  scope                = var.model_account_id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_user_assigned_identity.agent.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_api_management_api" "model" {
  count                 = var.model_account_id == "" ? 0 : 1
  name                  = "foundry-models"
  resource_group_name   = var.resource_group_name
  api_management_name   = azurerm_api_management.apim.name
  revision              = "1"
  display_name          = "Foundry models (via UMI)"
  path                  = "aoai"
  protocols             = ["https"]
  service_url           = "https://${element(split("/", var.model_account_id), 8)}.openai.azure.com"
  subscription_required = true

  # Databricks external models and OpenAI SDKs send the key in the api-key header.
  subscription_key_parameter_names {
    header = "api-key"
    query  = "subscription-key"
  }
}

resource "azurerm_api_management_api_operation" "model" {
  for_each            = var.model_account_id == "" ? {} : { "post-all" = "POST", "get-all" = "GET" }
  operation_id        = each.key
  api_name            = azurerm_api_management_api.model[0].name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = var.resource_group_name
  display_name        = "${each.value} /*"
  method              = each.value
  url_template        = "/*"
}

resource "azurerm_api_management_api_policy" "model" {
  count               = var.model_account_id == "" ? 0 : 1
  api_name            = azurerm_api_management_api.model[0].name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = var.resource_group_name

  xml_content = replace(replace(replace(file("${path.module}/../policy-model.xml"),
    "__CALLS__", tostring(var.calls_per_minute)),
    "__TPM__", tostring(var.model_tokens_per_minute)),
  "__CLIENT_ID__", azurerm_user_assigned_identity.agent.client_id)

  depends_on = [azurerm_api_management_api_operation.model]
}

resource "azurerm_api_management_subscription" "model" {
  count               = var.model_account_id == "" ? 0 : 1
  subscription_id     = "databricks-ai-gateway"
  display_name        = "Databricks external model (AI Gateway) -> Foundry"
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = var.resource_group_name
  api_id              = replace(azurerm_api_management_api.model[0].id, "/;rev=.*/", "")
  state               = "active"
}

# ---------- Logs ----------

resource "azurerm_monitor_diagnostic_setting" "apim" {
  name                           = "to-law"
  target_resource_id             = azurerm_api_management.apim.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.law.id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category = "GatewayLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# ---------- Foundry project connections (key-based custom MCP, same object the portal creates) ----------

resource "azapi_resource" "foundry_connection" {
  for_each  = var.foundry_project_id == "" ? {} : { for k, a in local.key_apis : k => a if a.foundry_connection != "" }
  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01"
  name      = each.value.foundry_connection
  parent_id = var.foundry_project_id

  body = {
    properties = {
      category      = "RemoteTool"
      target        = "https://${azurerm_api_management.apim.name}.azure-api.net/${each.value.path}/mcp"
      authType      = "CustomKeys"
      isSharedToAll = true
      metadata      = { type = "custom_MCP" }
    }
  }

  # Kept out of the plan output; still stored in state.
  sensitive_body = {
    properties = {
      credentials = {
        keys = { "Ocp-Apim-Subscription-Key" = azurerm_api_management_subscription.mcp[each.key].primary_key }
      }
    }
  }

  schema_validation_enabled = false
}
