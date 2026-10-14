# Databricks -> APIM -> Foundry model. A Databricks external-model serving endpoint whose OpenAI base URL is the APIM
# /aoai API, so model calls from Databricks (ai_query, agents, notebooks) go through the same gateway as the agents.
# The APIM key (azure/terraform: azurerm_api_management_subscription.model) is stored in a Databricks secret scope.
# Pass it via TF_VAR_apim_model_key; never put it in tfvars.

resource "databricks_secret_scope" "apim" {
  count    = var.apim_model_gateway_url == "" ? 0 : 1
  provider = databricks.workspace
  name     = var.apim_secret_scope
}

resource "databricks_secret" "apim_model_key" {
  count        = var.apim_model_gateway_url == "" ? 0 : 1
  provider     = databricks.workspace
  scope        = databricks_secret_scope.apim[0].name
  key          = "aoai-key"
  string_value = var.apim_model_key
}

resource "databricks_model_serving" "foundry_via_apim" {
  count    = var.apim_model_gateway_url == "" ? 0 : 1
  provider = databricks.workspace
  name     = var.model_endpoint_name

  config {
    served_entities {
      name = "gpt41-via-apim"
      external_model {
        name     = var.model_deployment
        provider = "openai"
        task     = "llm/v1/chat"
        openai_config {
          openai_api_type        = "azure"
          openai_api_key         = "{{secrets/${databricks_secret_scope.apim[0].name}/${databricks_secret.apim_model_key[0].key}}}"
          openai_api_base        = var.apim_model_gateway_url
          openai_deployment_name = var.model_deployment
          openai_api_version     = var.model_api_version
        }
      }
    }
  }

  # Databricks AI Gateway on top of APIM: usage tracking (system.serving tables) and an endpoint rate limit.
  ai_gateway {
    usage_tracking_config {
      enabled = true
    }
    rate_limits {
      calls          = var.model_calls_per_minute
      key            = "endpoint"
      renewal_period = "minute"
    }
  }
}
