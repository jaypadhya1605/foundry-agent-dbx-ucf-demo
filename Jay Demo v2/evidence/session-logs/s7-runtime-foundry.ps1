$ErrorActionPreference = 'Continue'
$files = 'c:\Users\jaypadhya\.copilot\session-state\7ca7ee45-df94-48ec-ba08-26d1792926a3\files'
$infra = 'C:\Users\jaypadhya\OneDrive - Microsoft\Desktop\SE Ops\my-scout\Customer\Intermountain Healthcare\On site -- Foundry and Databricks Session\infra'
$bi = "$infra\uc-agent-gateway\azure\bicep"
$rg = '/subscriptions/9bbee190-dc61-4c58-ab47-1275cb04018f/resourceGroups/rg-ai'
$out = Get-Content -Raw "$infra\brakekat-apim-umi-outputs.json" | ConvertFrom-Json
$aud = if ($env:UCGW_AUD) { $env:UCGW_AUD } else { $out.entraAudience }

'=== runtime redeploy (updated client) ==='
az deployment group create -g rg-ai -n imh-uc-runtime -f "$bi\runtime.bicep" `
  -p apimName=$($out.apimName) logAnalyticsWorkspaceName=$($out.logAnalyticsWorkspace) runtimeUmiName=$($out.runtimeUmiName) gatewayAudience=$aud `
  --query properties.provisioningState -o tsv

$start = (Get-Date).ToUniversalTime().ToString('o')
$jobUrl = "https://management.azure.com$rg/providers/Microsoft.App/jobs/job-imh-uc-agent"
$exec = az rest --method post --url "$jobUrl/start?api-version=2024-03-01" --query name -o tsv
"execution=$exec"

if (-not $env:UCGW_SKIP_FOUNDRY) {
'=== Foundry agents (while job logs ingest) ==='
& "$files\s6-foundry-agents.ps1"
} else { Start-Sleep 60 }

for ($i = 0; $i -lt 20; $i++) {
  $st = az rest --method get --url "$jobUrl/executions/$exec`?api-version=2024-03-01" --query properties.status -o tsv
  if ($st -in 'Succeeded', 'Failed', 'Stopped', 'Degraded') { break }
  Start-Sleep 10
}
"job status=$st"

'=== job console logs ==='
$cust = az monitor log-analytics workspace show -g rg-ai -n $out.logAnalyticsWorkspace --query customerId -o tsv
$q = "ContainerAppConsoleLogs_CL | where TimeGenerated > datetime($start) and ContainerJobName_s == 'job-imh-uc-agent' | order by TimeGenerated asc | project TimeGenerated, Log_s | take 60"
$tmp = Join-Path $env:TEMP 'laq.json'
Set-Content -LiteralPath $tmp -Value (@{ query = $q } | ConvertTo-Json -Compress) -Encoding ascii
$rows = @()
for ($i = 0; $i -lt 16; $i++) {
  $r = az rest --method post --url "https://api.loganalytics.io/v1/workspaces/$cust/query" --resource https://api.loganalytics.io --body "@$tmp" -o json 2>$null | ConvertFrom-Json
  if ($r -and $r.tables[0].rows.Count -gt 0) { $rows = $r.tables[0].rows; Start-Sleep 20; $r = az rest --method post --url "https://api.loganalytics.io/v1/workspaces/$cust/query" --resource https://api.loganalytics.io --body "@$tmp" -o json 2>$null | ConvertFrom-Json; if ($r) { $rows = $r.tables[0].rows }; break }
  Start-Sleep 30
}
foreach ($row in $rows) { "$($row[0]) $($row[1])" }
Remove-Item $tmp
'S7-DONE'
