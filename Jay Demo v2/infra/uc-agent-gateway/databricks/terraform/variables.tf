variable "account_id" {
  type        = string
  description = "Databricks account ID (accounts.azuredatabricks.net)."
}

variable "databricks_host" {
  type        = string
  description = "Workspace host without scheme."
}

variable "workspace_id" {
  type        = number
  description = "Numeric workspace ID (the o= value in the workspace URL)."
}

variable "umi_client_id" {
  type        = string
  description = "Client ID of the APIM user-assigned managed identity (azure/terraform output umi_client_id)."
}

variable "umi_display_name" {
  type    = string
  default = "umi-imh-uc-agent"
}

variable "groups" {
  type = object({
    phi_full      = string
    clinician_slc = string
    analyst       = string
  })
  default = {
    phi_full      = "imh_phi_full"
    clinician_slc = "imh_clinician_slc"
    analyst       = "imh_analyst"
  }
  description = "Account groups used by the row filter and masks. At IMH these would be SCIM-synced Entra groups."
}

variable "agent_group_key" {
  type        = string
  default     = "analyst"
  description = "Which group the APIM managed identity joins. It gets that group's rows and masks for every caller."
}

variable "create_groups" {
  type        = bool
  default     = true
  description = "false when the groups are SCIM-synced from Entra ID (IMH)."
}

variable "uc_catalog" {
  type = string
}

variable "uc_schema" {
  type = string
}

variable "create_catalog" {
  type        = bool
  default     = false
  description = "true to create the catalog and schema. Needs catalog_storage_root when the metastore has no root storage."
}

variable "catalog_storage_root" {
  type    = string
  default = ""
}

variable "warehouse_id" {
  type        = string
  description = "SQL warehouse used by Genie, UC function MCP and the setup job."
}

variable "manage_warehouse_permissions" {
  type        = bool
  default     = false
  description = "databricks_permissions is authoritative: it replaces ALL ACLs on the warehouse. Leave false on shared warehouses."
}

variable "deploy_uc_objects" {
  type        = bool
  default     = true
  description = "Upload the SQL (table, synthetic rows, row filter, masks, get_patients) and create a run-once job."
}

variable "workspace_sql_path" {
  type    = string
  default = "/Shared/uc-agent-gateway/uc_objects.sql"
}

variable "create_oauth_app" {
  type        = bool
  default     = false
  description = "Custom OAuth app for Foundry per-user (OBO) connections. Its secret lands in state."
}

variable "oauth_redirect_urls" {
  type        = list(string)
  default     = []
  description = "Redirect URI(s) shown by Foundry when adding the Azure Databricks connection."
}

variable "apim_model_gateway_url" {
  type        = string
  default     = ""
  description = "APIM /aoai URL (azure/terraform output model_gateway_url). Empty = skip the serving endpoint."
}

variable "apim_model_key" {
  type        = string
  default     = ""
  sensitive   = true
  description = "APIM subscription key for databricks-ai-gateway. Set via TF_VAR_apim_model_key only."
}

variable "apim_secret_scope" {
  type    = string
  default = "imh-apim"
}

variable "model_endpoint_name" {
  type    = string
  default = "imh-foundry-gpt41-via-apim"
}

variable "model_deployment" {
  type    = string
  default = "gpt-4.1"
}

variable "model_api_version" {
  type    = string
  default = "2024-10-21"
}

variable "model_calls_per_minute" {
  type    = number
  default = 60
}
