$ErrorActionPreference = 'Continue'
$name = 'imh-uc-gateway'
$appId = az ad app list --display-name $name --query '[0].appId' -o tsv
if (-not $appId) {
  $appId = az ad app create --display-name $name --sign-in-audience AzureADMyOrg --query appId -o tsv
  "created app: $appId (exit $LASTEXITCODE)"
} else { "existing app: $appId" }
if (-not $appId) { 'APP-CREATE-FAILED'; return }
$objId = az ad app show --id $appId --query id -o tsv
az ad app update --id $appId --identifier-uris "api://$appId"
"identifierUri exit $LASTEXITCODE"

$scopeId = az ad app show --id $appId --query 'api.oauth2PermissionScopes[0].id' -o tsv
if (-not $scopeId) {
  $scopeId = [guid]::NewGuid().ToString()
  $roleId = [guid]::NewGuid().ToString()
  $body = @{
    api = @{ oauth2PermissionScopes = @(@{ id = $scopeId; value = 'Gateway.Invoke'; type = 'User'; isEnabled = $true
      adminConsentDisplayName = 'Call the UC agent gateway'; adminConsentDescription = 'Call MCP tools through the UC agent gateway (APIM).'
      userConsentDisplayName = 'Call the UC agent gateway'; userConsentDescription = 'Call MCP tools through the UC agent gateway.' }) }
    appRoles = @(@{ id = $roleId; value = 'Gateway.Invoke'; displayName = 'Gateway.Invoke'; description = 'Workload identities allowed to call the UC agent gateway.'
      allowedMemberTypes = @('Application'); isEnabled = $true })
  } | ConvertTo-Json -Depth 6 -Compress
  $f = New-TemporaryFile; Set-Content $f $body
  az rest --method patch --url "https://graph.microsoft.com/v1.0/applications/$objId" --headers 'Content-Type=application/json' --body "@$f"
  "scope+role exit $LASTEXITCODE"
  # Pre-authorize Azure CLI so `az account get-access-token --resource api://<appId>` works without a consent prompt.
  $pre = @{ api = @{ preAuthorizedApplications = @(@{ appId = '04b07795-8ddb-461a-bbee-02f9e1bf7b46'; delegatedPermissionIds = @($scopeId) }) } } | ConvertTo-Json -Depth 6 -Compress
  Set-Content $f $pre
  az rest --method patch --url "https://graph.microsoft.com/v1.0/applications/$objId" --headers 'Content-Type=application/json' --body "@$f"
  "preauth exit $LASTEXITCODE"
  Remove-Item $f
}
$spId = az ad sp list --filter "appId eq '$appId'" --query '[0].id' -o tsv
if (-not $spId) { $spId = az ad sp create --id $appId --query id -o tsv; "sp created exit $LASTEXITCODE" }
"spId: $spId"
az ad app show --id $appId --query '{appId:appId,uris:identifierUris,scopes:api.oauth2PermissionScopes[].value,roles:appRoles[].value,preauth:api.preAuthorizedApplications[].appId}' -o json
'=== token test (az CLI) ==='
$t = az account get-access-token --resource "api://$appId" --query accessToken -o tsv 2>&1
if ($t -match '^eyJ') {
  $p = $t.Split('.')[1].Replace('-', '+').Replace('_', '/'); while ($p.Length % 4) { $p += '=' }
  $c = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p)) | ConvertFrom-Json
  "aud=$($c.aud) appid=$($c.appid) azp=$($c.azp) iss=$($c.iss) ver=$($c.ver) scp=$($c.scp)"
} else { "token failed: $t" }
'ENTRA-DONE'
