// UC agent gateway (Azure side): agent -> APIM (user-assigned managed identity) -> Databricks managed MCP -> Unity Catalog.
// Mirrors the IMH Azure Agents Control Plane pattern (APIM + UMI). Unity Catalog stays the only data governance layer.
// No secrets in files: APIM signs in to Databricks (and Foundry models) with the UMI; callers use an APIM subscription
// key that APIM generates, or an Entra token that APIM validates.
targetScope = 'resourceGroup'

param location string = resourceGroup().location
param prefix string = 'imh-uc'
param publisherEmail string
param publisherName string = 'UC agent gateway'

@description('Databricks workspace host, no scheme. e.g. adb-1234567890123456.7.azuredatabricks.net')
param databricksHost string
param ucCatalog string
param ucSchema string

@description('Genie space ID to expose as /genie/mcp. Leave empty to skip the Genie API.')
param genieSpaceId string = ''

@description('Calls per minute per subscription key on the standard MCP APIs. Lower it (e.g. 3) to demo a 429.')
param callsPerMinute int = 30

@description('Add /uc-limited/mcp: same UC tools with a tight tools/call rate limit, a daily quota and a response-size cap.')
param enableLimitedApi bool = true
param limitedToolCallsPerMinute int = 3
param limitedDailyQuota int = 200
@description('tools/call results with more rows than this are blocked by the gateway (UC functions return {columns, rows}).')
param limitedMaxRows int = 5
@description('tools/call results larger than this many bytes are blocked by the gateway.')
param limitedMaxResponseBytes int = 20000

@description('Add /uc-entra/mcp: no subscription key; APIM validates an Entra token instead.')
param enableEntraApi bool = true
@description('Token audience APIM accepts on /uc-entra. Use the gateway app registration ID URI (api://<appId>). Empty = https://management.azure.com (interim when no app registration can be created; Entra refuses tokens whose audience is a managed identity). The client-application-ids allow-list still restricts callers.')
param gatewayAudience string = ''
@description('Extra client application IDs allowed to call /uc-entra (the runtime identity created here is always allowed).')
param allowedClientAppIds array = []

@description('Add /aoai: Foundry model endpoint behind APIM (for Databricks external models / AI Gateway). Empty = skip.')
param modelAccountName string = ''
param modelTokensPerMinute int = 20000

@allowed(['BasicV2', 'StandardV2'])
@description('BasicV2 = public demo. StandardV2 supports outbound VNet integration to reach a private Databricks workspace.')
param apimSku string = 'BasicV2'

@description('Optional Foundry account in this resource group. When set with foundryProjectName, key-based MCP connections are created.')
param foundryAccountName string = ''
param foundryProjectName string = ''
param foundryConnectionName string = 'uc-fn-via-apim-umi-iac'

// Well-known Azure Databricks first-party application ID (token audience for managed identity).
var databricksResource = '2ff814a6-3304-4ab8-85cb-cd0e6f879c1d'
var suffix = uniqueString(resourceGroup().id, prefix)
var createFoundryConnections = !empty(foundryAccountName) && !empty(foundryProjectName)

resource umi 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'umi-${prefix}-agent'
  location: location
}

// Identity of the custom agent runtime (AKS workload identity / Container Apps). It only proves who is calling APIM;
// Databricks still sees the APIM identity above.
resource runtimeUmi 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = if (enableEntraApi) {
  name: 'umi-${prefix}-runtime'
  location: location
}

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'law-${prefix}-${suffix}'
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource apim 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: 'apim-${prefix}-${suffix}'
  location: location
  sku: { name: apimSku, capacity: 1 }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${umi.id}': {} }
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
}

// ---------- Policies ----------

var commonHeadersAndAuth = '''
    <set-variable name="correlationId" value="@(context.RequestId.ToString())" />
    <set-header name="x-imh-correlation-id" exists-action="override"><value>@((string)context.Variables["correlationId"])</value></set-header>
    <set-header name="Authorization" exists-action="delete" />
    <set-header name="Ocp-Apim-Subscription-Key" exists-action="delete" />
    <rewrite-uri template="__REWRITE__" copy-unmatched-params="false" />
    <authentication-managed-identity resource="__RESOURCE__" client-id="__CLIENT_ID__" ignore-error="false" />
'''

var commonTail = '''
  <outbound>
    <set-header name="x-imh-correlation-id" exists-action="override"><value>@((string)context.Variables["correlationId"])</value></set-header>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
'''

// Standard: subscription key + per-key rate limit.
var policyKeyRaw = '''
<policies>
  <inbound>
    <base />
    <rate-limit-by-key calls="__CALLS__" renewal-period="60" counter-key="@(context.Subscription.Id)" />
__COMMON__
  </inbound>
  <backend><forward-request timeout="120" buffer-response="false" /></backend>
__TAIL__'''

// Limited: tools/call rate limit, daily quota, and a response-size cap returned as an MCP tool error.
var policyLimitedRaw = '''
<policies>
  <inbound>
    <base />
    <set-variable name="rpcMethod" value="@{
      if (context.Request.Method != "POST") { return ""; }
      var body = context.Request.Body?.As<string>(preserveContent: true);
      if (string.IsNullOrEmpty(body)) { return ""; }
      var m = Newtonsoft.Json.Linq.JObject.Parse(body)["method"];
      return m == null ? "" : m.ToString();
    }" />
    <set-variable name="rpcId" value="@{
      if (context.Request.Method != "POST") { return "null"; }
      var body = context.Request.Body?.As<string>(preserveContent: true);
      if (string.IsNullOrEmpty(body)) { return "null"; }
      var id = Newtonsoft.Json.Linq.JObject.Parse(body)["id"];
      return id == null ? "null" : id.ToString(Newtonsoft.Json.Formatting.None);
    }" />
    <choose>
      <when condition="@((string)context.Variables["rpcMethod"] == "tools/call")">
        <rate-limit-by-key calls="__TOOLCALLS__" renewal-period="60" counter-key="@(context.Subscription.Id + "-tools")" />
      </when>
    </choose>
    <quota-by-key calls="__QUOTA__" renewal-period="86400" counter-key="@(context.Subscription.Id)" />
__COMMON__
  </inbound>
  <backend><forward-request timeout="120" buffer-response="true" /></backend>
  <outbound>
    <choose>
      <when condition="@((string)context.Variables["rpcMethod"] == "tools/call")">
        <set-variable name="respBody" value="@(context.Response.Body.As<string>(preserveContent: true))" />
        <set-variable name="rowCount" value="@{
          try {
            var body = (string)context.Variables["respBody"];
            var json = body.Trim();
            if (!json.StartsWith("{")) {
              var idx = json.LastIndexOf("data:");
              if (idx < 0) { return 0; }
              json = json.Substring(idx + 5).Trim();
            }
            var msg = Newtonsoft.Json.Linq.JObject.Parse(json);
            var text = (string)msg["result"]["content"][0]["text"];
            var rows = Newtonsoft.Json.Linq.JObject.Parse(text)["rows"] as Newtonsoft.Json.Linq.JArray;
            return rows == null ? 0 : rows.Count;
          } catch { return 0; }
        }" />
        <set-variable name="blockReason" value="@{
          if ((int)context.Variables["rowCount"] > __MAXROWS__) { return "rows"; }
          if (((string)context.Variables["respBody"]).Length > __MAXBYTES__) { return "bytes"; }
          return "";
        }" />
        <choose>
          <when condition="@((string)context.Variables["blockReason"] != "")">
            <return-response>
              <set-status code="200" reason="OK" />
              <set-header name="Content-Type" exists-action="override"><value>application/json</value></set-header>
              <set-header name="x-imh-correlation-id" exists-action="override"><value>@((string)context.Variables["correlationId"])</value></set-header>
              <set-header name="x-imh-gateway-block" exists-action="override"><value>@((string)context.Variables["blockReason"] == "rows" ? "row-limit " + context.Variables["rowCount"] + ">__MAXROWS__" : "response-size")</value></set-header>
              <set-body>@("{\"jsonrpc\":\"2.0\",\"id\":" + (string)context.Variables["rpcId"] + ",\"result\":{\"isError\":true,\"content\":[{\"type\":\"text\",\"text\":\"Blocked by gateway policy: the result has " + context.Variables["rowCount"] + " rows (limit __MAXROWS__) or is larger than __MAXBYTES__ bytes. Ask a narrower question, for example one facility.\"}]}}")</set-body>
            </return-response>
          </when>
        </choose>
      </when>
    </choose>
    <set-header name="x-imh-correlation-id" exists-action="override"><value>@((string)context.Variables["correlationId"])</value></set-header>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
'''

// Entra: no key. APIM validates the caller's Entra token (tenant, audience, allowed client app IDs).
var policyEntraRaw = '''
<policies>
  <inbound>
    <base />
    <validate-azure-ad-token tenant-id="__TENANT__" header-name="Authorization" failed-validation-httpcode="401" failed-validation-error-message="A valid Entra token for the UC agent gateway is required." output-token-variable-name="callerJwt">
      <client-application-ids>__CLIENTS__</client-application-ids>
      <audiences>__AUDIENCE__</audiences>
    </validate-azure-ad-token>
    <set-variable name="callerAppId" value="@(((Jwt)context.Variables["callerJwt"]).Claims.GetValueOrDefault("appid", ((Jwt)context.Variables["callerJwt"]).Claims.GetValueOrDefault("azp", "unknown")))" />
    <rate-limit-by-key calls="__CALLS__" renewal-period="60" counter-key="@((string)context.Variables["callerAppId"])" />
    <set-header name="x-imh-caller-appid" exists-action="override"><value>@((string)context.Variables["callerAppId"])</value></set-header>
__COMMON__
  </inbound>
  <backend><forward-request timeout="120" buffer-response="false" /></backend>
__TAIL__'''

var common = replace(replace(commonHeadersAndAuth, '__RESOURCE__', databricksResource), '__CLIENT_ID__', umi.properties.clientId)
var policyKey = replace(replace(replace(policyKeyRaw, '__COMMON__', common), '__TAIL__', commonTail), '__CALLS__', string(callsPerMinute))
var policyLimited = replace(replace(replace(replace(replace(policyLimitedRaw, '__COMMON__', common), '__TOOLCALLS__', string(limitedToolCallsPerMinute)), '__QUOTA__', string(limitedDailyQuota)), '__MAXBYTES__', string(limitedMaxResponseBytes)), '__MAXROWS__', string(limitedMaxRows))
var armAudience = endsWith(environment().resourceManager, '/') ? substring(environment().resourceManager, 0, length(environment().resourceManager) - 1) : environment().resourceManager
var entraAudience = empty(gatewayAudience) ? armAudience : gatewayAudience
// v1 tokens carry the resource as aud (sometimes with a trailing slash); v2 tokens for api://<appId> carry the bare appId.
var entraAudiences = union([entraAudience, '${entraAudience}/'], startsWith(entraAudience, 'api://') ? [substring(entraAudience, 6)] : [])
var entraAudiencesXml = join(map(entraAudiences, a => '<audience>${a}</audience>'), '')
var entraClients = concat(enableEntraApi ? [runtimeUmi!.properties.clientId] : [], allowedClientAppIds)
var entraClientsXml = join(map(entraClients, c => '<application-id>${c}</application-id>'), '')
var policyEntra = replace(replace(replace(replace(replace(replace(policyEntraRaw, '__COMMON__', common), '__TAIL__', commonTail), '__CALLS__', string(callsPerMinute)), '__TENANT__', tenant().tenantId), '__AUDIENCE__', entraAudiencesXml), '__CLIENTS__', entraClientsXml)

var ucRewrite = '/api/2.0/mcp/functions/${ucCatalog}/${ucSchema}'

// Index 0 must stay the UC functions API.
var mcpApis = concat(
  [
    {
      name: 'imh-uc-functions-mcp'
      displayName: 'IMH UC functions MCP (via UMI)'
      path: 'uc'
      kind: 'key'
      rewrite: ucRewrite
      keyRequired: true
      subscription: 'foundry-imh-uc-agent'
      subscriptionDisplayName: 'Foundry agent imh-uc-apim-umi-agent'
      foundryConnection: foundryConnectionName
    }
  ],
  empty(genieSpaceId) ? [] : [
    {
      name: 'imh-genie-mcp'
      displayName: 'IMH Genie space MCP (via UMI)'
      path: 'genie'
      kind: 'key'
      rewrite: '/api/2.0/mcp/genie/${genieSpaceId}'
      keyRequired: true
      subscription: 'foundry-imh-genie-agent'
      subscriptionDisplayName: 'Foundry agent (Genie via APIM)'
      foundryConnection: 'genie-via-apim-umi-iac'
    }
  ],
  !enableLimitedApi ? [] : [
    {
      name: 'imh-uc-functions-mcp-limited'
      displayName: 'IMH UC functions MCP - limited (rate, quota, size cap)'
      path: 'uc-limited'
      kind: 'limited'
      rewrite: ucRewrite
      keyRequired: true
      subscription: 'imh-uc-limited-client'
      subscriptionDisplayName: 'Limited client (demo 429 and size cap)'
      foundryConnection: 'uc-limited-via-apim-umi-iac'
    }
  ],
  !enableEntraApi ? [] : [
    {
      name: 'imh-uc-functions-mcp-entra'
      displayName: 'IMH UC functions MCP - Entra token (no key)'
      path: 'uc-entra'
      kind: 'entra'
      rewrite: ucRewrite
      keyRequired: false
      subscription: ''
      subscriptionDisplayName: ''
      foundryConnection: ''
    }
  ]
)

resource apis 'Microsoft.ApiManagement/service/apis@2024-05-01' = [for a in mcpApis: {
  parent: apim
  name: a.name
  properties: {
    displayName: a.displayName
    path: a.path
    protocols: ['https']
    serviceUrl: 'https://${databricksHost}'
    subscriptionRequired: a.keyRequired
    subscriptionKeyParameterNames: { header: 'Ocp-Apim-Subscription-Key', query: 'subscription-key' }
  }
}]

resource opPost 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = [for (a, i) in mcpApis: {
  parent: apis[i]
  name: 'mcp-post'
  properties: { displayName: 'MCP POST', method: 'POST', urlTemplate: '/mcp', responses: [] }
}]

resource opGet 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = [for (a, i) in mcpApis: {
  parent: apis[i]
  name: 'mcp-get'
  properties: { displayName: 'MCP GET', method: 'GET', urlTemplate: '/mcp', responses: [] }
}]

resource opDelete 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = [for (a, i) in mcpApis: {
  parent: apis[i]
  name: 'mcp-delete'
  properties: { displayName: 'MCP DELETE', method: 'DELETE', urlTemplate: '/mcp', responses: [] }
}]

resource policies 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = [for (a, i) in mcpApis: {
  parent: apis[i]
  name: 'policy'
  properties: { format: 'rawxml', value: replace(a.kind == 'limited' ? policyLimited : (a.kind == 'entra' ? policyEntra : policyKey), '__REWRITE__', a.rewrite) }
  dependsOn: [opPost[i], opGet[i], opDelete[i]]
}]

// One key per key-based API. APIM generates the keys; they are never written to disk.
resource subs 'Microsoft.ApiManagement/service/subscriptions@2024-05-01' = [for (a, i) in mcpApis: if (a.keyRequired) {
  parent: apim
  name: a.keyRequired ? a.subscription : 'unused-${i}'
  properties: {
    displayName: a.subscriptionDisplayName
    scope: '/apis/${apis[i].name}'
    state: 'active'
  }
}]

// ---------- Foundry models behind APIM (Databricks -> APIM -> Foundry) ----------

resource modelAccount 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = if (!empty(modelAccountName)) {
  name: empty(modelAccountName) ? 'none' : modelAccountName
}

// Cognitive Services OpenAI User for the APIM identity on the model account.
resource modelRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(modelAccountName)) {
  name: guid(modelAccount.id, umi.id, '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
  scope: modelAccount
  properties: {
    principalId: umi.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
  }
}

var policyModel = replace(replace(replace('''
<policies>
  <inbound>
    <base />
    <rate-limit-by-key calls="__CALLS__" renewal-period="60" counter-key="@(context.Subscription.Id)" />
    <llm-token-limit counter-key="@(context.Subscription.Id)" tokens-per-minute="__TPM__" estimate-prompt-tokens="false" remaining-tokens-header-name="x-imh-remaining-tokens" />
    <set-variable name="correlationId" value="@(context.RequestId.ToString())" />
    <set-header name="api-key" exists-action="delete" />
    <set-header name="Authorization" exists-action="delete" />
    <authentication-managed-identity resource="https://cognitiveservices.azure.com" client-id="__CLIENT_ID__" ignore-error="false" />
  </inbound>
  <backend><forward-request timeout="120" /></backend>
__TAIL__''', '__TAIL__', commonTail), '__CALLS__', string(callsPerMinute)), '__TPM__', string(modelTokensPerMinute))

resource modelApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = if (!empty(modelAccountName)) {
  parent: apim
  name: 'foundry-models'
  properties: {
    displayName: 'Foundry models (via UMI)'
    path: 'aoai'
    protocols: ['https']
    serviceUrl: 'https://${empty(modelAccountName) ? 'none' : modelAccountName}.openai.azure.com'
    subscriptionRequired: true
    // Databricks external models and OpenAI SDKs send the key in the api-key header.
    subscriptionKeyParameterNames: { header: 'api-key', query: 'subscription-key' }
  }
}

resource modelOpPost 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = if (!empty(modelAccountName)) {
  parent: modelApi
  name: 'post-all'
  properties: { displayName: 'POST /*', method: 'POST', urlTemplate: '/*', responses: [] }
}

resource modelOpGet 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = if (!empty(modelAccountName)) {
  parent: modelApi
  name: 'get-all'
  properties: { displayName: 'GET /*', method: 'GET', urlTemplate: '/*', responses: [] }
}

resource modelPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = if (!empty(modelAccountName)) {
  parent: modelApi
  name: 'policy'
  properties: { format: 'rawxml', value: replace(policyModel, '__CLIENT_ID__', umi.properties.clientId) }
  dependsOn: [modelOpPost, modelOpGet]
}

resource modelSub 'Microsoft.ApiManagement/service/subscriptions@2024-05-01' = if (!empty(modelAccountName)) {
  parent: apim
  name: 'databricks-ai-gateway'
  properties: {
    displayName: 'Databricks external model (AI Gateway) -> Foundry'
    scope: '/apis/${modelApi.name}'
    state: 'active'
  }
}

// ---------- Logs ----------

resource diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'to-law'
  scope: apim
  properties: {
    workspaceId: law.id
    logAnalyticsDestinationType: 'Dedicated'
    logs: [{ category: 'GatewayLogs', enabled: true }]
    metrics: [{ category: 'AllMetrics', enabled: true }]
  }
}

// ---------- Foundry project connections (key-based custom MCP) ----------

resource foundry 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = if (createFoundryConnections) {
  name: createFoundryConnections ? foundryAccountName : 'none'
}

resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' existing = if (createFoundryConnections) {
  parent: foundry
  name: createFoundryConnections ? foundryProjectName : 'none'
}

resource foundryConnections 'Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01' = [for (a, i) in mcpApis: if (createFoundryConnections && a.keyRequired && !empty(a.foundryConnection)) {
  parent: foundryProject
  name: empty(a.foundryConnection) ? 'unused-${i}' : a.foundryConnection
  properties: {
    category: 'RemoteTool'
    target: 'https://${apim.name}.azure-api.net/${a.path}/mcp'
    authType: 'CustomKeys'
    isSharedToAll: true
    credentials: {
      keys: { 'Ocp-Apim-Subscription-Key': subs[i].listSecrets().primaryKey }
    }
    metadata: { type: 'custom_MCP' }
  }
}]

output apimName string = apim.name
output mcpUrl string = 'https://${apim.name}.azure-api.net/uc/mcp'
output genieMcpUrl string = empty(genieSpaceId) ? '' : 'https://${apim.name}.azure-api.net/genie/mcp'
output limitedMcpUrl string = enableLimitedApi ? 'https://${apim.name}.azure-api.net/uc-limited/mcp' : ''
output entraMcpUrl string = enableEntraApi ? 'https://${apim.name}.azure-api.net/uc-entra/mcp' : ''
output entraAudience string = enableEntraApi ? entraAudience : ''
output modelGatewayUrl string = empty(modelAccountName) ? '' : 'https://${apim.name}.azure-api.net/aoai'
output umiName string = umi.name
output umiClientId string = umi.properties.clientId
output umiPrincipalId string = umi.properties.principalId
output runtimeUmiName string = enableEntraApi ? runtimeUmi!.name : ''
output runtimeUmiClientId string = enableEntraApi ? runtimeUmi!.properties.clientId : ''
output logAnalyticsWorkspace string = law.name
output foundryConnectionNames array = [for a in mcpApis: (createFoundryConnections && a.keyRequired) ? a.foundryConnection : '']
