[CmdletBinding()]
param(
    [string]$DatabricksHost = 'https://adb-2813105879250022.2.azuredatabricks.net',
    [string]$CliProfile = 'brakekat',
    [string]$WarehouseName = 'adb-demo-wh',
    [string]$SubscriptionId = '9bbee190-dc61-4c58-ab47-1275cb04018f',
    [string]$ResourceGroup = 'rg-ai',
    [string]$ApimName = 'apim-imh-uc-66zpmtcbvhe7w',
    [string]$ApimSubscription = 'databricks-ai-gateway',
    [string]$SecretScope = 'imh-apim',
    [string]$EndpointName = 'imh-foundry-gpt41-via-apim',
    [string]$Deployment = 'gpt-4.1',
    [switch]$SkipSql,
    [switch]$SkipModel
)

# Databricks-side pieces of the UC agent gateway that need a workspace admin (jay@brakekat.com):
#   1. UC row cap: get_patients_limited (get_patients_limited.sql)
#   2. Databricks -> APIM -> Foundry: secret scope with the APIM key, external model endpoint with AI Gateway,
#      then ai_query() through it.
# The APIM key goes from `az rest` into memory and then into the Databricks secret scope. It is never written to disk.
# Safe to rerun: CREATE OR REPLACE for the function, update instead of create for the endpoint.
# Run with: powershell -ExecutionPolicy Bypass -File .\Setup-DatabricksSide.ps1
# F5 in VS Code dot-sources it, which leaves ErrorAction Stop and this folder in that terminal afterwards.
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot

# Copy of the console output in %TEMP% (outside OneDrive) for review after the run. The script prints no secrets.
$log = Join-Path $env:TEMP 'imh-setup-databricks-side.log'
Start-Transcript -LiteralPath $log -Force | Out-Null
trap { Write-Output "ERROR: $($_.Exception.Message)"; Stop-Transcript | Out-Null; break }
Write-Output "Log: $log"

if (-not (Get-Command databricks -ErrorAction SilentlyContinue)) {
    throw 'Databricks CLI not found. Install: winget install Databricks.DatabricksCLI (then open a new terminal).'
}

Write-Output "Sign in to $DatabricksHost as jay@brakekat.com (browser opens)..."
databricks auth login --host $DatabricksHost --profile $CliProfile
if ($LASTEXITCODE -ne 0) { throw 'databricks auth login failed.' }
$me = databricks current-user me --profile $CliProfile -o json | ConvertFrom-Json
Write-Output "Signed in as $($me.userName)"

$wh = (databricks warehouses list --profile $CliProfile -o json | ConvertFrom-Json) | Where-Object { $_.name -eq $WarehouseName } | Select-Object -First 1
if (-not $wh) { throw "Warehouse $WarehouseName not found." }
Write-Output "Warehouse $($wh.name) ($($wh.id))"

# JSON bodies go through a temp file because Windows PowerShell mangles quotes on native command lines.
function Invoke-DbxJson([string]$Method, [string]$Path, [object]$Body) {
    $tmp = Join-Path $env:TEMP ("dbx-" + [guid]::NewGuid().ToString('N') + '.json')
    try {
        $Body | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $tmp -Encoding ascii
        $out = databricks api $Method $Path --json "@$tmp" --profile $CliProfile -o json
        if ($LASTEXITCODE -ne 0) { throw "databricks api $Method $Path failed." }
        return ($out -join "`n") | ConvertFrom-Json
    } finally { Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue }
}

function Invoke-Sql([string]$Statement) {
    $r = Invoke-DbxJson post '/api/2.0/sql/statements' @{ warehouse_id = $wh.id; statement = $Statement; wait_timeout = '50s' }
    while ($r.status.state -in 'PENDING', 'RUNNING') {
        Start-Sleep 3
        $r = (databricks api get "/api/2.0/sql/statements/$($r.statement_id)" --profile $CliProfile -o json) -join "`n" | ConvertFrom-Json
    }
    if ($r.status.state -ne 'SUCCEEDED') { throw "SQL failed on '$(($Statement -split "`n")[0])': $($r.status.error.message)" }
    return $r.result.data_array
}

if (-not $SkipSql) {
    Write-Output '--- 1. UC row cap (get_patients_limited) ---'
    $sql = (Get-Content -LiteralPath 'get_patients_limited.sql' | ForEach-Object { $_ -replace '\s*--.*$', '' }) -join "`n"
    $statements = $sql -split ';' | Where-Object { $_.Trim() }
    foreach ($s in $statements) {
        $rows = Invoke-Sql $s.Trim()
        Write-Output ("OK: " + ($s.Trim() -split "`n")[0] + $(if ($rows) { "  -> " + ($rows | ConvertTo-Json -Compress) } else { '' }))
    }
}

if (-not $SkipModel) {
    Write-Output '--- 2. Databricks -> APIM -> Foundry model ---'
    az account set --subscription $SubscriptionId
    $url = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName/subscriptions/$ApimSubscription/listSecrets?api-version=2024-05-01"
    $key = az rest --method post --url $url --query primaryKey -o tsv
    if (-not $key) { throw 'Could not read the APIM key (az login to the BrakeKat tenant first).' }

    $scopes = (databricks secrets list-scopes --profile $CliProfile -o json | ConvertFrom-Json)
    if (-not ($scopes | Where-Object { $_.name -eq $SecretScope })) {
        databricks secrets create-scope $SecretScope --profile $CliProfile
    }
    databricks secrets put-secret $SecretScope 'aoai-key' --string-value $key --profile $CliProfile
    if ($LASTEXITCODE -ne 0) { throw 'put-secret failed.' }
    $key = $null
    Write-Output "Secret $SecretScope/aoai-key set (APIM key, not the Foundry key)."

    $config = @{
        served_entities = @(@{
            name           = 'gpt41-via-apim'
            external_model = @{
                name          = $Deployment
                provider      = 'openai'
                task          = 'llm/v1/chat'
                openai_config = @{
                    openai_api_type        = 'azure'
                    openai_api_key         = "{{secrets/$SecretScope/aoai-key}}"
                    openai_api_base        = "https://$ApimName.azure-api.net/aoai"
                    openai_deployment_name = $Deployment
                    openai_api_version     = '2024-10-21'
                }
            }
        })
    }
    $gateway = @{
        usage_tracking_config = @{ enabled = $true }
        rate_limits           = @(@{ calls = 60; key = 'endpoint'; renewal_period = 'minute' })
    }

    $existing = $null
    try { $existing = (databricks serving-endpoints get $EndpointName --profile $CliProfile -o json 2>$null) -join "`n" | ConvertFrom-Json } catch { }
    if ($existing) {
        Invoke-DbxJson put "/api/2.0/serving-endpoints/$EndpointName/config" $config | Out-Null
        Invoke-DbxJson put "/api/2.0/serving-endpoints/$EndpointName/ai-gateway" $gateway | Out-Null
        Write-Output "Updated endpoint $EndpointName"
    } else {
        Invoke-DbxJson post '/api/2.0/serving-endpoints' @{ name = $EndpointName; config = $config; ai_gateway = $gateway } | Out-Null
        Write-Output "Created endpoint $EndpointName"
    }
    for ($i = 0; $i -lt 30; $i++) {
        $ep = (databricks serving-endpoints get $EndpointName --profile $CliProfile -o json) -join "`n" | ConvertFrom-Json
        if ($ep.state.ready -eq 'READY') { break }
        Start-Sleep 10
    }
    Write-Output "Endpoint state: $($ep.state.ready)"

    $resp = Invoke-DbxJson post "/serving-endpoints/$EndpointName/invocations" @{ messages = @(@{ role = 'user'; content = 'Reply with exactly: databricks to foundry via apim ok' }); max_tokens = 20 }
    Write-Output "REST invocation: $($resp.choices[0].message.content)"

    $rows = Invoke-Sql "SELECT ai_query('$EndpointName', 'In one sentence, what does Unity Catalog govern?') AS answer"
    # PowerShell unrolls the one-row data_array, so $rows is the row itself; [0][0] would print one character.
    Write-Output "ai_query: $(@($rows) -join ' ')"
}

Write-Output 'DATABRICKS-SIDE-COMPLETE'
Stop-Transcript | Out-Null
