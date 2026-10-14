$ErrorActionPreference = 'Continue'
$cl = 'C:\Users\jaypadhya\OneDrive - Microsoft\Desktop\SE Ops\my-scout\Customer\Intermountain Healthcare\On site -- Foundry and Databricks Session\infra\uc-agent-gateway\clients'
$apim = 'apim-imh-uc-66zpmtcbvhe7w'
$base = "https://management.azure.com/subscriptions/9bbee190-dc61-4c58-ab47-1275cb04018f/resourceGroups/rg-ai/providers/Microsoft.ApiManagement/service/$apim/subscriptions"
$env:APIM_SUBSCRIPTION_KEY = az rest --method post --url "$base/foundry-imh-genie-agent/listSecrets?api-version=2024-05-01" --query primaryKey -o tsv
$env:APIM_MCP_URL = "https://$apim.azure-api.net/genie/mcp"
python "$cl\python_mcp_client.py" --query 'List the SLC patients with patient_id, name, ssn and diagnosis'
Remove-Item Env:APIM_SUBSCRIPTION_KEY
'S2-DONE'
