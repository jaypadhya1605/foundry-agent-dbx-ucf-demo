$ErrorActionPreference = 'Continue'
$infra = 'C:\Users\jaypadhya\OneDrive - Microsoft\Desktop\SE Ops\my-scout\Customer\Intermountain Healthcare\On site -- Foundry and Databricks Session\infra'
$bi = "$infra\uc-agent-gateway\azure\bicep"
$cl = "$infra\uc-agent-gateway\clients\python_mcp_client.py"
$sub = '9bbee190-dc61-4c58-ab47-1275cb04018f'
$rg = "/subscriptions/$sub/resourceGroups/rg-ai"
$apim = 'apim-imh-uc-66zpmtcbvhe7w'
$base = "https://management.azure.com$rg/providers/Microsoft.ApiManagement/service/$apim/subscriptions"

'=== redeploy main (row cap) ==='
& "$infra\Deploy-BrakekatApimUmi.ps1" | Select-Object -Last 3

'=== runtime deploy (ACA job) ==='
$out = Get-Content -Raw "$infra\brakekat-apim-umi-outputs.json" | ConvertFrom-Json
az deployment group create -g rg-ai -n imh-uc-runtime -f "$bi\runtime.bicep" `
  -p apimName=$($out.apimName) logAnalyticsWorkspaceName=$($out.logAnalyticsWorkspace) runtimeUmiName=$($out.runtimeUmiName) gatewayAudience=$($out.entraAudience) `
  --query "{state:properties.provisioningState, out:properties.outputs}" -o json
"runtime deploy exit $LASTEXITCODE"

'=== /uc-limited tests (after 60s rate window) ==='
Start-Sleep 60
$env:APIM_SUBSCRIPTION_KEY = az rest --method post --url "$base/imh-uc-limited-client/listSecrets?api-version=2024-05-01" --query primaryKey -o tsv
$env:APIM_MCP_URL = "https://$apim.azure-api.net/uc-limited/mcp"
'--- T1 SLC (4 rows, expect pass) ---'
python $cl --facility SLC
'--- T2 all facilities (12 rows, expect row-limit block) ---'
$env:MCP_ARGS = '{"fac": null}'
python $cl
Remove-Item Env:MCP_ARGS
Remove-Item Env:APIM_SUBSCRIPTION_KEY

'=== start ACA job ==='
$jobUrl = "https://management.azure.com$rg/providers/Microsoft.App/jobs/job-imh-uc-agent"
$exec = az rest --method post --url "$jobUrl/start?api-version=2024-03-01" --query name -o tsv
"execution=$exec"
for ($i = 0; $i -lt 30; $i++) {
  Start-Sleep 10
  $st = az rest --method get --url "$jobUrl/executions/$exec`?api-version=2024-03-01" --query properties.status -o tsv
  "status=$st"
  if ($st -in 'Succeeded', 'Failed', 'Stopped', 'Degraded') { break }
}
'S5-DONE'
