// BrakeKat demo values (synthetic data, public endpoints). Copy per environment (e.g. imh-dev.bicepparam).
using 'main.bicep'

param location = 'westus3'
param prefix = 'imh-uc'
param publisherEmail = 'jay@brakekat.com'
param publisherName = 'IMH UC demo (synthetic)'
param databricksHost = 'adb-2813105879250022.2.azuredatabricks.net'
param ucCatalog = 'imh_demo'
param ucSchema = 'clinical'
param genieSpaceId = '01f1c5e2508a1326a03ad64e4d7fb1b5'
param callsPerMinute = 30
param apimSku = 'BasicV2'
param foundryAccountName = 'aif-wu3'
param foundryProjectName = 'proj-imh-uc-demo'
param foundryConnectionName = 'uc-fn-via-apim-umi-iac'

// Row/size cap demo (/uc-limited/mcp)
param enableLimitedApi = true
param limitedToolCallsPerMinute = 3
param limitedDailyQuota = 200
param limitedMaxRows = 5
param limitedMaxResponseBytes = 20000

// Entra token validation (/uc-entra/mcp). BrakeKat guest can't create an app registration and Entra won't issue
// tokens with a managed identity as audience (AADSTS100040), so the interim audience is https://management.azure.com,
// locked down by the client-application-ids allow-list. At IMH set gatewayAudience = 'api://<gateway appId>'.
param enableEntraApi = true
param gatewayAudience = ''
param allowedClientAppIds = []

// Databricks AI Gateway -> APIM -> Foundry model (/aoai)
param modelAccountName = 'aif-wu3'
param modelTokensPerMinute = 20000
