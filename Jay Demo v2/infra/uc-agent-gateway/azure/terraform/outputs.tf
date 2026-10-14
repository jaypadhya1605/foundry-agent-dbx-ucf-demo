output "apim_name" {
  value = azurerm_api_management.apim.name
}

output "mcp_url" {
  value = "https://${azurerm_api_management.apim.name}.azure-api.net/uc/mcp"
}

output "genie_mcp_url" {
  value = var.genie_space_id == "" ? "" : "https://${azurerm_api_management.apim.name}.azure-api.net/genie/mcp"
}

output "umi_name" {
  value = azurerm_user_assigned_identity.agent.name
}

output "umi_client_id" {
  description = "Use as application_id for the Databricks service principal (databricks/terraform)."
  value       = azurerm_user_assigned_identity.agent.client_id
}

output "umi_principal_id" {
  value = azurerm_user_assigned_identity.agent.principal_id
}

output "log_analytics_workspace" {
  value = azurerm_log_analytics_workspace.law.name
}

output "foundry_connection_names" {
  value = var.foundry_project_id == "" ? [] : [for k, a in local.key_apis : a.foundry_connection if a.foundry_connection != ""]
}

output "limited_mcp_url" {
  value = var.enable_limited_api ? "https://${azurerm_api_management.apim.name}.azure-api.net/uc-limited/mcp" : ""
}

output "entra_mcp_url" {
  value = var.enable_entra_api ? "https://${azurerm_api_management.apim.name}.azure-api.net/uc-entra/mcp" : ""
}

output "entra_audience" {
  value = var.enable_entra_api ? local.entra_audience : ""
}

output "model_gateway_url" {
  value = var.model_account_id == "" ? "" : "https://${azurerm_api_management.apim.name}.azure-api.net/aoai"
}

output "runtime_umi_client_id" {
  value = var.enable_entra_api ? azurerm_user_assigned_identity.runtime[0].client_id : ""
}

output "runtime_job_name" {
  value = var.enable_entra_api && var.enable_runtime ? azurerm_container_app_job.agent[0].name : ""
}
