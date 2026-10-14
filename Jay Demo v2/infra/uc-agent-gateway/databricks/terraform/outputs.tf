output "umi_service_principal_id" {
  value = databricks_service_principal.umi.id
}

output "setup_job_id" {
  description = "Run once after apply: databricks jobs run-now <id>"
  value       = var.deploy_uc_objects ? databricks_job.uc_objects[0].id : ""
}

output "oauth_client_id" {
  value = var.create_oauth_app ? databricks_custom_app_integration.foundry[0].client_id : ""
}

output "oauth_client_secret" {
  value     = var.create_oauth_app ? databricks_custom_app_integration.foundry[0].client_secret : ""
  sensitive = true
}

output "uc_functions_mcp_url" {
  value = "https://${var.databricks_host}/api/2.0/mcp/functions/${var.uc_catalog}/${var.uc_schema}"
}

output "model_endpoint_name" {
  value = var.apim_model_gateway_url == "" ? "" : databricks_model_serving.foundry_via_apim[0].name
}
