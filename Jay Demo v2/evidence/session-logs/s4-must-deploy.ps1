$ErrorActionPreference = 'Continue'
$infra = 'C:\Users\jaypadhya\OneDrive - Microsoft\Desktop\SE Ops\my-scout\Customer\Intermountain Healthcare\On site -- Foundry and Databricks Session\infra'
$bi = "$infra\uc-agent-gateway\azure\bicep"
$cl = "$infra\uc-agent-gateway\clients\python_mcp_client.py"
if (Test-Path "$bi\main_new.bicep") { Move-Item -Force "$bi\main_new.bicep" "$bi\main.bicep"; 'main.bicep replaced' }
'bearer line check:'; (Select-String -LiteralPath $cl -Pattern 'Bearer').Line

'=== build ==='
az bicep build --file "$bi\main.bicep" --stdout | Out-Null; "main build exit $LASTEXITCODE"
az bicep build --file "$bi\runtime.bicep" --stdout | Out-Null; "runtime build exit $LASTEXITCODE"
az bicep build-params --file "$bi\brakekat.bicepparam" --stdout | Out-Null; "params build exit $LASTEXITCODE"

$apim = 'apim-imh-uc-66zpmtcbvhe7w'
$base = "https://management.azure.com/subscriptions/9bbee190-dc61-4c58-ab47-1275cb04018f/resourceGroups/rg-ai/providers/Microsoft.ApiManagement/service/$apim/subscriptions"

'=== size probe on /uc (before deploy) ==='
$env:APIM_SUBSCRIPTION_KEY = az rest --method post --url "$base/foundry-imh-uc-agent/listSecrets?api-version=2024-05-01" --query primaryKey -o tsv
$env:APIM_MCP_URL = "https://$apim.azure-api.net/uc/mcp"
$o = python $cl --facility SLC | Out-String; "SLC output chars: $($o.Length)"; $o
$env:MCP_ARGS = '{"fac": null}'
$o = python $cl | Out-String; "null-fac output chars: $($o.Length)"; $o
Remove-Item Env:MCP_ARGS

'=== deploy ==='
& "$infra\Deploy-BrakekatApimUmi.ps1"

'=== /uc-limited tests ==='
$env:APIM_SUBSCRIPTION_KEY = az rest --method post --url "$base/imh-uc-limited-client/listSecrets?api-version=2024-05-01" --query primaryKey -o tsv
$env:APIM_MCP_URL = "https://$apim.azure-api.net/uc-limited/mcp"
'--- T1 SLC (expect rows) ---'
python $cl --facility SLC
'--- T2 all facilities (expect size block) ---'
$env:MCP_ARGS = '{"fac": null}'
python $cl
Remove-Item Env:MCP_ARGS
'--- T3 repeat 5 (expect 429 after 3 tool calls/min; T1+T2 already used 2) ---'
python $cl --facility SLC --repeat 5
Remove-Item Env:APIM_SUBSCRIPTION_KEY

'=== /uc-entra negative tests ==='
$env:APIM_MCP_URL = "https://$apim.azure-api.net/uc-entra/mcp"
'--- E1 ARM token (wrong audience, expect 401) ---'
python $cl --auth azcli --audience https://management.azure.com
'--- E2 az cli token for gateway audience (expect consent error or 401: client not allowed) ---'
$aud = (Get-Content -Raw "$infra\brakekat-apim-umi-outputs.json" | ConvertFrom-Json).entraAudience
"audience=$aud"
python $cl --auth azcli --audience $aud

'=== /aoai test ==='
$k = az rest --method post --url "$base/databricks-ai-gateway/listSecrets?api-version=2024-05-01" --query primaryKey -o tsv
$body = '{"messages":[{"role":"user","content":"Reply with exactly: gateway ok"}],"max_tokens":10}'
try {
  $r = Invoke-WebRequest -UseBasicParsing -Method Post -Uri "https://$apim.azure-api.net/aoai/openai/deployments/gpt-4.1/chat/completions?api-version=2024-10-21" -Headers @{ 'api-key' = $k } -ContentType 'application/json' -Body $body
  "status $($r.StatusCode) remaining-tokens $($r.Headers['x-imh-remaining-tokens'])"
  ($r.Content | ConvertFrom-Json).choices[0].message.content
} catch { "AOAI-FAIL $($_.Exception.Message)"; $_.ErrorDetails.Message }
$k = $null
'S4-DONE'
