// Custom agent runtime for the UC agent gateway: an Azure Container Apps job that runs the Python MCP client
// with its own managed identity and calls APIM /uc-entra/mcp with an Entra token (no key anywhere).
// Stands in for the AKS runtime in Yun's diagram; on AKS the same client uses --auth workload.
targetScope = 'resourceGroup'

param location string = resourceGroup().location
param prefix string = 'imh-uc'
@description('Outputs of main.bicep')
param apimName string
param logAnalyticsWorkspaceName string
param runtimeUmiName string
@description('Audience APIM validates on /uc-entra (main.bicep output entraAudience).')
param gatewayAudience string
param facility string = 'SLC'
@description('Any image with python3 on PATH. The client is standard-library only.')
param image string = 'mcr.microsoft.com/azurelinux/base/python:3.12'

var clientB64 = loadFileAsBase64('../../clients/python_mcp_client.py')

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource runtimeUmi 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: runtimeUmiName
}

resource env 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: 'cae-${prefix}-runtime'
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: law.properties.customerId
        sharedKey: law.listKeys().primarySharedKey
      }
    }
    workloadProfiles: [{ name: 'Consumption', workloadProfileType: 'Consumption' }]
  }
}

resource job 'Microsoft.App/jobs@2024-03-01' = {
  name: 'job-${prefix}-agent'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${runtimeUmi.id}': {} }
  }
  properties: {
    environmentId: env.id
    workloadProfileName: 'Consumption'
    configuration: {
      triggerType: 'Manual'
      replicaTimeout: 300
      replicaRetryLimit: 0
      manualTriggerConfig: { parallelism: 1, replicaCompletionCount: 1 }
    }
    template: {
      containers: [
        {
          name: 'uc-agent'
          image: image
          command: ['python3', '-c', 'import base64,os,sys;sys.argv=["client"]+os.environ.get("CLIENT_ARGS","").split();exec(compile(base64.b64decode(os.environ["CLIENT_B64"]),"python_mcp_client.py","exec"))']
          env: [
            { name: 'CLIENT_B64', value: clientB64 }
            { name: 'CLIENT_ARGS', value: '--facility ${facility}' }
            { name: 'APIM_MCP_URL', value: 'https://${apimName}.azure-api.net/uc-entra/mcp' }
            { name: 'APIM_AUTH', value: 'mi' }
            { name: 'APIM_AUDIENCE', value: gatewayAudience }
            { name: 'AZURE_CLIENT_ID', value: runtimeUmi.properties.clientId }
            { name: 'PYTHONUNBUFFERED', value: '1' }
          ]
          resources: { cpu: json('0.25'), memory: '0.5Gi' }
        }
      ]
    }
  }
}

output jobName string = job.name
output environmentName string = env.name
