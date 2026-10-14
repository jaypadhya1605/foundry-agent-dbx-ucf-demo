$ErrorActionPreference = 'Continue'
$infra = 'C:\Users\jaypadhya\OneDrive - Microsoft\Desktop\SE Ops\my-scout\Customer\Intermountain Healthcare\On site -- Foundry and Databricks Session\infra'
$cl = "$infra\uc-agent-gateway\clients"
if (Test-Path "$cl\python_mcp_client_v2.py") { Move-Item -Force "$cl\python_mcp_client_v2.py" "$cl\python_mcp_client.py"; 'client v2 in place' }

& "$infra\Deploy-BrakekatApimUmi.ps1"
if ($LASTEXITCODE -ne 0 -and $?) { }

$apim = 'apim-imh-uc-66zpmtcbvhe7w'
$base = "https://management.azure.com/subscriptions/9bbee190-dc61-4c58-ab47-1275cb04018f/resourceGroups/rg-ai/providers/Microsoft.ApiManagement/service/$apim/subscriptions"
$env:APIM_SUBSCRIPTION_KEY = az rest --method post --url "$base/foundry-imh-genie-agent/listSecrets?api-version=2024-05-01" --query primaryKey -o tsv
$env:APIM_MCP_URL = "https://$apim.azure-api.net/genie/mcp"
'=== genie tools ==='
python "$cl\python_mcp_client.py" --list
Remove-Item Env:APIM_SUBSCRIPTION_KEY
'S1-DONE'
