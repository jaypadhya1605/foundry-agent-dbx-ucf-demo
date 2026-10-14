[CmdletBinding()]
param(
    [string]$TenantId = '8d038e6a-9b7d-4cb8-bbcf-e84dff156478',
    [string]$SubscriptionId = '9bbee190-dc61-4c58-ab47-1275cb04018f',
    [string]$ResourceGroup = 'rg-ai',
    [switch]$WhatIf
)

# Deploys uc-agent-gateway\azure\bicep\main.bicep with brakekat.bicepparam (APIM + UMI + LAW, UC + Genie MCP APIs,
# optional Foundry connection) into the BrakeKat subscription. -WhatIf previews changes without deploying.
# Writes only non-secret outputs to brakekat-apim-umi-outputs.json.
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot

$current = az account show --query tenantId -o tsv 2>$null
if ($current -ne $TenantId) {
    az login --tenant $TenantId -o none
    if ($LASTEXITCODE -ne 0) { throw 'az login failed.' }
}
az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) { throw "Cannot select subscription $SubscriptionId." }
Write-Output "Account: $(az account show --query '{user:user.name,sub:name}' -o tsv)"

Write-Output 'Registering resource providers (one-time)...'
foreach ($ns in 'Microsoft.ApiManagement', 'Microsoft.ManagedIdentity', 'Microsoft.OperationalInsights', 'Microsoft.Insights') {
    $state = az provider show -n $ns --query registrationState -o tsv 2>$null
    if ($state -ne 'Registered') {
        az provider register -n $ns --wait -o none
        if ($LASTEXITCODE -ne 0) { throw "Provider registration failed: $ns" }
    }
    Write-Output "  $ns registered"
}

$template = 'uc-agent-gateway\azure\bicep\main.bicep'
$params = 'uc-agent-gateway\azure\bicep\brakekat.bicepparam'

Write-Output 'Building Bicep...'
az bicep build --file $template --stdout | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Bicep build failed.' }

if ($WhatIf) {
    az deployment group what-if -g $ResourceGroup -n imh-apim-umi -p $params --result-format ResourceIdOnly
    if ($LASTEXITCODE -ne 0) { throw 'What-if failed. See error above.' }
    Write-Output 'WHATIF-COMPLETE'
    return
}

Write-Output 'Deploying (APIM BasicV2 typically takes 5-15 min)...'
$json = az deployment group create -g $ResourceGroup -n imh-apim-umi -p $params `
    --query properties.outputs -o json
if ($LASTEXITCODE -ne 0) { throw 'Deployment failed. See error above.' }

$outputs = ($json -join "`n") | ConvertFrom-Json
$result = [ordered]@{}
foreach ($p in $outputs.PSObject.Properties) { $result[$p.Name] = $p.Value.value }
$result | ConvertTo-Json | Set-Content -LiteralPath 'brakekat-apim-umi-outputs.json' -Encoding utf8
$result | ConvertTo-Json
Write-Output 'DEPLOY-COMPLETE'
