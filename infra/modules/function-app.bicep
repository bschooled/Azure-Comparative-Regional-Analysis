@description('Function App name.')
param functionAppName string

@description('Azure location for deployed resources.')
param location string

@description('CORS origins allowed to call the Function endpoint directly when needed.')
param allowedCorsOrigins array = []

@description('Backing storage account name.')
param storageAccountName string

@description('Blob service URI used for identity-based host storage.')
param storageBlobServiceUri string

@description('Queue service URI used for identity-based host storage.')
param storageQueueServiceUri string

@description('Table service URI used for identity-based host storage.')
param storageTableServiceUri string

@description('Application Insights connection string.')
param applicationInsightsConnectionString string

@description('Application Insights resource ID.')
param applicationInsightsId string

@description('Log Analytics workspace resource ID that receives platform diagnostics.')
param logAnalyticsWorkspaceId string

@description('Globally unique Azure Container Registry name used for the Function container image.')
param containerRegistryName string

@description('Container repository name used for the Function image inside ACR.')
param containerImageName string = 'function-app'

@description('Existing production Function container image preserved during infrastructure upgrades.')
param containerImageReference string = ''

@description('Subscription ID queried by the hosted comparison refresh.')
param analysisSubscriptionId string

@description('Microsoft Entra application client ID used to protect the Function App HTTP endpoints.')
param authClientId string = ''

@description('Microsoft Entra tenant ID used to validate tokens for the Function App HTTP endpoints.')
param authTenantId string

@description('Object IDs allowed to call the protected Function App HTTP endpoints.')
param authAllowedPrincipalIds array = []

@description('Default source region used for seeded comparison refreshes.')
param defaultSourceRegion string

@description('Default target region used for seeded comparison refreshes.')
param defaultTargetRegion string

@description('Azure cloud environment used by the hosted Function App.')
param cloudEnvironment string = 'AzureCloud'

@description('Azure Resource Manager endpoint used by the hosted Function App.')
param armEndpoint string = environment().resourceManager

@description('OAuth scope used by the hosted Function App when requesting ARM tokens.')
param managementScope string = '${environment().resourceManager}/.default'

@description('Authority host used by the hosted Function App credential chain.')
param azureAuthorityHost string = environment().authentication.loginEndpoint

@description('Subnet resource ID used for regional VNet integration.')
param functionIntegrationSubnetId string

@description('azd service name tag applied to the Function App.')
param serviceName string = 'api'

@description('Tags applied to resources.')
param tags object = {}

var premiumPlanName = '${functionAppName}-plan'
var bootstrapImage = 'mcr.microsoft.com/azure-functions/python:4-python3.12@sha256:852c8bb1914e740fcefb3141cfe017a9a9aaec3fe0d4844117119b7b89cc2c01'
var functionAuthResource = empty(authClientId) ? '' : 'api://${authClientId}'
var applicationInsightsName = last(split(applicationInsightsId, '/'))
var functionAuthValidation = empty(functionAuthResource)
  ? null
  : union({
      allowedAudiences: [
        functionAuthResource
      ]
    }, length(authAllowedPrincipalIds) > 0
      ? {
          defaultAuthorizationPolicy: {
            allowedPrincipals: {
              identities: authAllowedPrincipalIds
            }
          }
        }
      : {})

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${functionAppName}-uami'
  location: location
  tags: tags
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: containerRegistryName
  location: location
  sku: {
    name: 'Basic'
  }
  tags: tags
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Enabled'
  }
}

resource plan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: premiumPlanName
  location: location
  kind: 'elastic'
  sku: {
    name: 'EP1'
    tier: 'ElasticPremium'
    family: 'EP'
  }
  tags: tags
  properties: {
    maximumElasticWorkerCount: 20
    reserved: true
  }
}

resource app 'Microsoft.Web/sites@2024-04-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux,container'
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentity.id}': {}
    }
  }
  tags: union(tags, {
    'azd-service-name': serviceName
  })
  properties: {
    clientAffinityEnabled: false
    reserved: true
    publicNetworkAccess: 'Enabled'
    serverFarmId: plan.id
    httpsOnly: true
    vnetRouteAllEnabled: true
  }
}

resource webConfig 'Microsoft.Web/sites/config@2024-04-01' = {
  name: 'web'
  parent: app
  properties: {
    acrUseManagedIdentityCreds: true
    alwaysOn: true
    cors: {
      allowedOrigins: allowedCorsOrigins
      supportCredentials: false
    }
    ftpsState: 'Disabled'
    ipSecurityRestrictionsDefaultAction: 'Allow'
    http20Enabled: true
    linuxFxVersion: 'DOCKER|${empty(containerImageReference) ? bootstrapImage : containerImageReference}'
    minTlsVersion: '1.2'
    scmIpSecurityRestrictionsDefaultAction: 'Allow'
    scmIpSecurityRestrictionsUseMain: false
  }
}

resource appSettings 'Microsoft.Web/sites/config@2024-04-01' = {
  name: 'appsettings'
  parent: app
  properties: {
    AzureWebJobsStorage__blobServiceUri: storageBlobServiceUri
    AzureWebJobsStorage__clientId: userAssignedIdentity.properties.clientId
    AzureWebJobsStorage__queueServiceUri: storageQueueServiceUri
    AzureWebJobsStorage__tableServiceUri: storageTableServiceUri
    AzureWebJobsStorage__credential: 'managedidentity'
    AzureWebJobsStorage__accountName: storageAccountName
    AZURE_CLIENT_ID: userAssignedIdentity.properties.clientId
    DOCKER_REGISTRY_SERVER_URL: 'https://${containerRegistry.properties.loginServer}'
    WEBSITE_DNS_SERVER: '168.63.129.16'
    WEBSITES_ENABLE_APP_SERVICE_STORAGE: 'false'
    FUNCTIONS_WORKER_RUNTIME: 'python'
    FUNCTIONS_EXTENSION_VERSION: '~4'
    PYTHON_ISOLATE_WORKER_DEPENDENCIES: '1'
    BLOB_STORAGE__blobServiceUri: storageBlobServiceUri
    DATA_STORAGE__tableServiceUri: storageTableServiceUri
    APPLICATIONINSIGHTS_CONNECTION_STRING: applicationInsightsConnectionString
    APPLICATIONINSIGHTS_AUTHENTICATION_STRING: 'Authorization=AAD;ClientId=${userAssignedIdentity.properties.clientId}'
    ANALYSIS_SUBSCRIPTION_ID: analysisSubscriptionId
    ANALYSIS_SOURCE_REGION: defaultSourceRegion
    ANALYSIS_TARGET_REGION: defaultTargetRegion
    AZURE_CLOUD_ENVIRONMENT: cloudEnvironment
    CLOUD_ENVIRONMENT: cloudEnvironment
    ARM_ENDPOINT: armEndpoint
    MANAGEMENT_SCOPE: managementScope
    AZURE_AUTHORITY_HOST: azureAuthorityHost
    PRICING_CONTAINER_NAME: 'pricing-cache'
    COMPARISON_TABLE_NAME: 'CurrentComparisons'
    RUNS_TABLE_NAME: 'RefreshRuns'
    DETAILS_CONTAINER_NAME: 'comparison-details'
    REFRESH_SCHEDULE: '0 0 4 * * *'
  }
}

resource authSettings 'Microsoft.Web/sites/config@2022-09-01' = if (!empty(authClientId)) {
  name: 'authsettingsV2'
  parent: app
  properties: {
    platform: {
      enabled: true
      runtimeVersion: '~1'
    }
    globalValidation: {
      requireAuthentication: true
      unauthenticatedClientAction: 'Return401'
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: {
          clientId: authClientId
          openIdIssuer: uri(environment().authentication.loginEndpoint, '${authTenantId}/v2.0')
        }
        validation: functionAuthValidation
      }
    }
  }
}

resource networkConfig 'Microsoft.Web/sites/networkConfig@2024-04-01' = {
  name: 'virtualNetwork'
  parent: app
  properties: {
    subnetResourceId: functionIntegrationSubnetId
    swiftSupported: true
  }
}

module storageBlobDataContributor './storage-role-assignment.bicep' = {
  name: 'storageBlobDataContributor'
  params: {
    storageAccountName: storageAccountName
    principalId: userAssignedIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    assignmentSeed: 'Storage Blob Data Contributor'
  }
}

module storageBlobDataOwner './storage-role-assignment.bicep' = {
  name: 'storageBlobDataOwner'
  params: {
    storageAccountName: storageAccountName
    principalId: userAssignedIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
    assignmentSeed: 'Storage Blob Data Owner'
  }
}

module storageQueueDataContributor './storage-role-assignment.bicep' = {
  name: 'storageQueueDataContributor'
  params: {
    storageAccountName: storageAccountName
    principalId: userAssignedIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '974c5e8b-45b9-4653-ba55-5f855dd0fb88')
    assignmentSeed: 'Storage Queue Data Contributor'
  }
}

module storageTableDataContributor './storage-role-assignment.bicep' = {
  name: 'storageTableDataContributor'
  params: {
    storageAccountName: storageAccountName
    principalId: userAssignedIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
    assignmentSeed: 'Storage Table Data Contributor'
  }
}

module monitoringMetricsPublisher './application-insights-role-assignment.bicep' = {
  name: 'monitoringMetricsPublisher'
  params: {
    applicationInsightsId: applicationInsightsId
    applicationInsightsName: applicationInsightsName
    principalId: userAssignedIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '3913510d-42f4-4e42-8a64-420c390055eb')
    assignmentSeed: 'Monitoring Metrics Publisher'
  }
}

module acrPull './container-registry-role-assignment.bicep' = {
  name: 'acrPull'
  params: {
    containerRegistryName: containerRegistryName
    principalId: app.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    assignmentSeed: 'AcrPull'
  }
}

module acrPullUserAssigned './container-registry-role-assignment.bicep' = {
  name: 'acrPullUserAssigned'
  params: {
    containerRegistryName: containerRegistryName
    principalId: userAssignedIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    assignmentSeed: 'AcrPull user assigned'
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${functionAppName}-diagnostics'
  scope: app
  properties: {
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
    workspaceId: logAnalyticsWorkspaceId
  }
}

resource containerRegistryDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${containerRegistryName}-diagnostics'
  scope: containerRegistry
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output functionAppName string = app.name
output functionAppId string = app.id
output functionAppBaseUrl string = 'https://${app.properties.defaultHostName}'
output principalId string = app.identity.principalId
output userAssignedPrincipalId string = userAssignedIdentity.properties.principalId
output userAssignedClientId string = userAssignedIdentity.properties.clientId
output containerRegistryName string = containerRegistry.name
output containerRegistryLoginServer string = containerRegistry.properties.loginServer
output containerImageName string = containerImageName
output diagnosticSettingId string = diagnostics.id
output containerRegistryDiagnosticSettingId string = containerRegistryDiagnostics.id
