$ErrorActionPreference = 'Continue'
$infra = 'C:\Users\jaypadhya\OneDrive - Microsoft\Desktop\SE Ops\my-scout\Customer\Intermountain Healthcare\On site -- Foundry and Databricks Session\infra'
$bi = "$infra\uc-agent-gateway\azure\bicep"
$cl = "$infra\uc-agent-gateway\clients\python_mcp_client.py"
$apim = 'apim-imh-uc-66zpmtcbvhe7w'

'=== build ==='
az bicep build --file "$bi\main.bicep" --stdout | Out-Null; "main build exit $LASTEXITCODE"

'=== deploy main (audience -> ARM) ==='
& "$infra\Deploy-BrakekatApimUmi.ps1"
$out = Get-Content -Raw "$infra\brakekat-apim-umi-outputs.json" | ConvertFrom-Json
"entraAudience=$($out.entraAudience)"

'=== /uc-entra negative: Jay az cli ARM token (client app not allowed, expect 401) ==='
$env:APIM_MCP_URL = "https://$apim.azure-api.net/uc-entra/mcp"
python $cl --auth azcli --audience https://management.azure.com --facility SLC

'=== runtime job (positive: runtime UMI is allowed) ==='
$env:UCGW_AUD = $out.entraAudience
$env:UCGW_SKIP_FOUNDRY = '1'
& "$env:USERPROFILE\.copilot\session-state\7ca7ee45-df94-48ec-ba08-26d1792926a3\files\s7-runtime-foundry.ps1"
'S8-DONE'
