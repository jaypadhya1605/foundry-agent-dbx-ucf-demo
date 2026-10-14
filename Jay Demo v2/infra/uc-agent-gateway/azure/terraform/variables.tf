variable "subscription_id" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "prefix" {
  type    = string
  default = "imh-uc"
}

variable "name_suffix" {
  type        = string
  description = "Suffix for globally unique names. Set to an existing suffix (e.g. the Bicep uniqueString) to import a Bicep-built stack."
}

variable "publisher_email" {
  type = string
}

variable "publisher_name" {
  type    = string
  default = "UC agent gateway"
}

variable "databricks_host" {
  type        = string
  description = "Workspace host without scheme, e.g. adb-1234567890123456.7.azuredatabricks.net"
}

variable "uc_catalog" {
  type = string
}

variable "uc_schema" {
  type = string
}

variable "genie_space_id" {
  type        = string
  default     = ""
  description = "Genie space to expose as /genie/mcp. Empty = skip."
}

variable "calls_per_minute" {
  type        = number
  default     = 30
  description = "Per-key rate limit. Set to 3 to demo a 429."
}

variable "apim_sku" {
  type        = string
  default     = "BasicV2_1"
  description = "BasicV2_1 for public demo; StandardV2_1 supports outbound VNet integration to a private Databricks workspace."
}

variable "foundry_project_id" {
  type        = string
  default     = ""
  description = "Full resource ID of the Foundry project. When set, a key-based MCP connection is created."
}

variable "foundry_connection_name" {
  type    = string
  default = "uc-fn-via-apim-umi-iac"
}

variable "enable_limited_api" {
  type        = bool
  default     = true
  description = "Add /uc-limited/mcp: tools/call rate limit, daily quota, row/size cap."
}

variable "limited_tool_calls_per_minute" {
  type    = number
  default = 3
}

variable "limited_daily_quota" {
  type    = number
  default = 200
}

variable "limited_max_rows" {
  type        = number
  default     = 5
  description = "tools/call results with more rows than this are blocked by the gateway."
}

variable "limited_max_response_bytes" {
  type    = number
  default = 20000
}

variable "enable_entra_api" {
  type        = bool
  default     = true
  description = "Add /uc-entra/mcp: no subscription key; APIM validates an Entra token."
}

variable "gateway_audience" {
  type        = string
  default     = ""
  description = "Audience APIM accepts on /uc-entra. Use api://<gateway appId>. Empty = https://management.azure.com (interim; restricted by the client app allow-list)."
}

variable "allowed_client_app_ids" {
  type        = list(string)
  default     = []
  description = "Extra client app IDs allowed on /uc-entra (the runtime identity is always allowed)."
}

variable "model_account_id" {
  type        = string
  default     = ""
  description = "Resource ID of the Foundry (AI Services) account to expose as /aoai. Empty = skip."
}

variable "model_tokens_per_minute" {
  type    = number
  default = 20000
}

variable "enable_runtime" {
  type        = bool
  default     = true
  description = "Create the Container Apps job runtime (requires enable_entra_api)."
}

variable "runtime_image" {
  type        = string
  default     = "mcr.microsoft.com/azurelinux/base/python:3.12"
  description = "Any image with python3 on PATH; the client is standard-library only."
}

variable "runtime_facility" {
  type    = string
  default = "SLC"
}
