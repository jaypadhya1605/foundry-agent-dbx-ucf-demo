$ErrorActionPreference = 'Continue'
$files = 'c:\Users\jaypadhya\.copilot\session-state\7ca7ee45-df94-48ec-ba08-26d1792926a3\files'
$infra = 'C:\Users\jaypadhya\OneDrive - Microsoft\Desktop\SE Ops\my-scout\Customer\Intermountain Healthcare\On site -- Foundry and Databricks Session\infra'
$gw = "$infra\uc-agent-gateway"
$bi = "$gw\azure\bicep"
$cl = "$gw\clients\python_mcp_client.py"
$apim = 'apim-imh-uc-66zpmtcbvhe7w'
$base = "https://management.azure.com/subscriptions/9bbee190-dc61-4c58-ab47-1275cb04018f/resourceGroups/rg-ai/providers/Microsoft.ApiManagement/service/$apim"

'=== splice bicep -> shared policy files ==='
Copy-Item "$bi\main.bicep" (Join-Path $env:TEMP 'main.bicep.bak') -Force
python "$files\splice_bicep.py" "$bi\main.bicep"
az bicep build --file "$bi\main.bicep" --stdout | Out-Null; "main build exit $LASTEXITCODE"
if ($LASTEXITCODE -ne 0) { 'BUILD FAILED - restoring'; Copy-Item (Join-Path $env:TEMP 'main.bicep.bak') "$bi\main.bicep" -Force; 'S9-ABORT'; return }

'=== deploy main ==='
& "$infra\Deploy-BrakekatApimUmi.ps1" | Select-Object -Last 4

'=== regression ==='
'--- /uc key SLC (expect 4 rows) ---'
$env:APIM_SUBSCRIPTION_KEY = az rest --method post --url "$base/subscriptions/foundry-imh-uc-agent/listSecrets?api-version=2024-05-01" --query primaryKey -o tsv
$env:APIM_MCP_URL = "https://$apim.azure-api.net/uc/mcp"
python $cl --facility SLC
'--- /genie tools/list ---'
$env:APIM_SUBSCRIPTION_KEY = az rest --method post --url "$base/subscriptions/foundry-imh-genie-agent/listSecrets?api-version=2024-05-01" --query primaryKey -o tsv
$env:APIM_MCP_URL = "https://$apim.azure-api.net/genie/mcp"
python $cl --list
'--- /uc-limited all facilities (expect row-limit block) ---'
$env:APIM_SUBSCRIPTION_KEY = az rest --method post --url "$base/subscriptions/imh-uc-limited-client/listSecrets?api-version=2024-05-01" --query primaryKey -o tsv
$env:APIM_MCP_URL = "https://$apim.azure-api.net/uc-limited/mcp"
$env:MCP_ARGS = '{"fac": null}'
python $cl
Remove-Item Env:MCP_ARGS
Remove-Item Env:APIM_SUBSCRIPTION_KEY
'--- /uc-entra az cli (expect 401) ---'
$env:APIM_MCP_URL = "https://$apim.azure-api.net/uc-entra/mcp"
python $cl --auth azcli --audience https://management.azure.com --facility SLC
'--- /aoai (expect 200) ---'
$k = az rest --method post --url "$base/subscriptions/databricks-ai-gateway/listSecrets?api-version=2024-05-01" --query primaryKey -o tsv
$body = '{"messages":[{"role":"user","content":"Reply with exactly: gateway ok"}],"max_tokens":10}'
try {
  $r = Invoke-WebRequest -UseBasicParsing -Method Post -Uri "https://$apim.azure-api.net/aoai/openai/deployments/gpt-4.1/chat/completions?api-version=2024-10-21" -Headers @{ 'api-key' = $k } -ContentType 'application/json' -Body $body
  "status $($r.StatusCode) remaining-tokens $($r.Headers['x-imh-remaining-tokens'])"
  ($r.Content | ConvertFrom-Json).choices[0].message.content
} catch { "AOAI-FAIL $($_.Exception.Message)" }
$k = $null
'--- runtime job via /uc-entra (expect 4 SLC rows) ---'
$env:UCGW_SKIP_FOUNDRY = '1'
& "$files\s7-runtime-foundry.ps1"

'=== terraform parity ==='
Copy-Item "$files\tf-main.tf" "$gw\azure\terraform\main.tf" -Force
if (Test-Path "$gw\azure\policy.xml.tftpl") { Remove-Item "$gw\azure\policy.xml.tftpl"; 'removed old policy.xml.tftpl' }
$tf = Get-Command terraform -ErrorAction SilentlyContinue
if (-not $tf) {
  $tfdir = Join-Path $env:LOCALAPPDATA 'ucgw-terraform'
  if (-not (Test-Path "$tfdir\terraform.exe")) {
    New-Item -ItemType Directory -Force $tfdir | Out-Null
    $zip = Join-Path $env:TEMP 'terraform.zip'
    Invoke-WebRequest -UseBasicParsing 'https://releases.hashicorp.com/terraform/1.9.8/terraform_1.9.8_windows_amd64.zip' -OutFile $zip
    Expand-Archive $zip -DestinationPath $tfdir -Force; Remove-Item $zip
  }
  $tfexe = "$tfdir\terraform.exe"
} else { $tfexe = $tf.Source }
& $tfexe version | Select-Object -First 1
$tmp = Join-Path $env:TEMP 'ucgw-tf'
if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
New-Item -ItemType Directory -Force $tmp | Out-Null
Copy-Item -Recurse "$gw\azure" "$tmp\azure"; Copy-Item -Recurse "$gw\clients" "$tmp\clients"; Copy-Item -Recurse "$gw\databricks" "$tmp\databricks"
foreach ($d in "$tmp\azure\terraform", "$tmp\databricks\terraform") {
  "--- $d ---"
  Push-Location $d
  & $tfexe init -backend=false -input=false -no-color 2>&1 | Select-Object -Last 2
  & $tfexe validate -no-color
  & $tfexe fmt -check -diff -no-color
  "fmt exit $LASTEXITCODE"
  Pop-Location
}
Remove-Item -Recurse -Force $tmp
'S9-DONE'
