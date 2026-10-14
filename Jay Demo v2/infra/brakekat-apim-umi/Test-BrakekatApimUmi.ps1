[CmdletBinding()]
param(
    [string]$ResourceGroup = 'rg-ai',
    [string]$SubscriptionId = '9bbee190-dc61-4c58-ab47-1275cb04018f',
    [string]$Fac = 'SLC'
)

# Smoke test: APIM (UMI) -> Databricks UC functions MCP. Key is read into memory only, never printed or saved.
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$out = Get-Content -LiteralPath 'brakekat-apim-umi-outputs.json' -Raw | ConvertFrom-Json
$subUrl = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$($out.apimName)/subscriptions/foundry-imh-uc-agent/listSecrets?api-version=2024-05-01"
$key = az rest --method post --url $subUrl --query primaryKey -o tsv
if ($LASTEXITCODE -ne 0 -or -not $key) { throw 'Could not read APIM subscription key.' }

$headers = @{ 'Ocp-Apim-Subscription-Key' = $key; 'Accept' = 'application/json, text/event-stream' }

function Invoke-Mcp([int]$Id, [string]$Method, $Params) {
    $body = @{ jsonrpc = '2.0'; id = $Id; method = $Method }
    if ($Params) { $body.params = $Params }
    try {
        $r = Invoke-WebRequest -Uri $out.mcpUrl -Method Post -Headers $headers -ContentType 'application/json' `
            -Body ($body | ConvertTo-Json -Depth 10 -Compress) -UseBasicParsing
        Write-Output "== $Method -> HTTP $($r.StatusCode)  correlation=$($r.Headers['x-imh-correlation-id'])"
        Write-Output ($r.Content.Substring(0, [Math]::Min(3000, $r.Content.Length)))
    } catch {
        $resp = $_.Exception.Response
        Write-Output "== $Method -> FAILED $([int]$resp.StatusCode)"
        if ($_.ErrorDetails.Message) { Write-Output $_.ErrorDetails.Message }
    }
}

Invoke-Mcp 1 'initialize' @{ protocolVersion = '2025-03-26'; capabilities = @{}; clientInfo = @{ name = 'imh-smoke'; version = '1.0' } }
Invoke-Mcp 2 'tools/list' $null
Invoke-Mcp 3 'tools/call' @{ name = 'imh_demo__clinical__get_patients'; arguments = @{ fac = $Fac } }
Write-Output 'SMOKE-COMPLETE'
