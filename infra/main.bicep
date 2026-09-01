targetScope = 'resourceGroup'

@description('Base name used for Azure resources in this deployment.')
@minLength(1)
param namePrefix string = 'azcomparereg'

@description('Azure location for all regional resources.')
param location string = resourceGroup().location

@description('Deployment environment label.')
@allowed([
  'dev'
  'test'
  'prod'
])
param environment string = 'dev'

@description('Short alphanumeric suffix appended to hosted site names to avoid global name collisions.')
@maxLength(4)
param siteSuffix string = ''

@description('Globally unique storage account name.')
@minLength(3)
@maxLength(24)
param storageAccountName string = toLower('${take(replace(namePrefix, '-', ''), 8)}${take(environment, 3)}${uniqueString(resourceGroup().id)}')

@description('Globally unique deployment package storage account name.')
@minLength(3)
@maxLength(24)
param deploymentStorageAccountName string = toLower('${take(replace(namePrefix, '-', ''), 6)}pkg${take(environment, 3)}${take(uniqueString(resourceGroup().id, 'deploy'), 10)}')

@description('Function App name.')
param functionAppName string = empty(siteSuffix) ? '${namePrefix}-${environment}-func' : '${namePrefix}-${environment}-func-${siteSuffix}'

@description('Public Web App name.')
param webAppName string = empty(siteSuffix) ? '${namePrefix}-${environment}-web' : '${namePrefix}-${environment}-web-${siteSuffix}'

@description('Globally unique Azure Container Registry name for the hosted Function image.')
@minLength(5)
@maxLength(50)
param containerRegistryName string = toLower('${take(replace(namePrefix, '-', ''), 10)}${take(environment, 3)}acr${take(uniqueString(resourceGroup().id, 'acr'), 10)}')

@description('Microsoft Entra application client ID for the public web app.')
param webAuthClientId string = ''

@description('Microsoft Entra tenant ID for the public web app.')
param webAuthTenantId string = subscription().tenantId

@description('App setting name that stores the Microsoft Entra client secret for App Service auth. Leave empty to avoid configuring a client secret.')
param webAuthClientCredentialSettingName string = ''

@description('Microsoft Entra application client ID used to protect the Function App API.')
param functionAuthClientId string = ''

@description('Microsoft Entra tenant ID used to validate Function App API tokens.')
param functionAuthTenantId string = subscription().tenantId

@description('Existing production Function container image preserved during infrastructure upgrades.')
param functionContainerImage string = ''

@description('Subscription ID queried by the hosted refresh function.')
param analysisSubscriptionId string = subscription().subscriptionId

@description('Default source region for seeded comparison refreshes.')
param defaultSourceRegion string = location

@description('Default target region for seeded comparison refreshes.')
param defaultTargetRegion string = 'eastus'

@description('Azure cloud environment passed to deployed application runtimes.')
param cloudEnvironment string = 'AzureCloud'

@description('Azure Resource Manager endpoint used by deployed application runtimes.')
param armEndpoint string = az.environment().resourceManager

@description('OAuth scope used for ARM tokens inside deployed application runtimes.')
param managementScope string = '${az.environment().resourceManager}/.default'

@description('Authority host used by SDK credentials inside deployed application runtimes.')
param azureAuthorityHost string = az.environment().authentication.loginEndpoint

@description('Virtual network name for the isolated app network.')
param virtualNetworkName string = '${namePrefix}-${environment}-vnet'

@description('Address prefix for the isolated app virtual network.')
param virtualNetworkAddressPrefix string = '10.240.0.0/24'

@description('Subnet name used for Function App regional VNet integration.')
param functionIntegrationSubnetName string = 'functions-integration'

@description('Address prefix used for Function App regional VNet integration.')
param functionIntegrationSubnetPrefix string = '10.240.0.0/26'

@description('Subnet name used for storage private endpoints.')
param privateEndpointSubnetName string = 'private-endpoints'

@description('Subnet name used for Web App regional VNet integration.')
param webIntegrationSubnetName string = 'web-integration'

@description('Address prefix used for Web App regional VNet integration.')
param webIntegrationSubnetPrefix string = '10.240.0.128/26'

@description('Address prefix used for storage private endpoints.')
param privateEndpointSubnetPrefix string = '10.240.0.64/26'

@description('CORS origins allowed to call the Function endpoint directly when needed.')
param allowedCorsOrigins array = [
  'https://portal.azure.com'
  'https://ms.portal.azure.com'
]

@description('Optional tags applied to deployed resources.')
param tags object = {
  application: 'azure-comparative-regional-analysis'
  environment: environment
}

var storageDnsSuffix = az.environment().suffixes.storage
var blobPrivateDnsZoneName = 'privatelink.blob.${storageDnsSuffix}'
var queuePrivateDnsZoneName = 'privatelink.queue.${storageDnsSuffix}'
var tablePrivateDnsZoneName = 'privatelink.table.${storageDnsSuffix}'
var functionAuthResource = empty(functionAuthClientId) ? '' : 'api://${functionAuthClientId}'
var logAnalyticsWorkspaceName = take('${namePrefix}-${environment}-law', 63)
var applicationInsightsName = take('${storageAccountName}-appi', 255)

module monitoring './modules/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    applicationInsightsName: applicationInsightsName
    location: location
    tags: tags
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: virtualNetworkName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        virtualNetworkAddressPrefix
      ]
    }
    subnets: [
      {
        name: functionIntegrationSubnetName
        properties: {
          addressPrefix: functionIntegrationSubnetPrefix
          delegations: [
            {
              name: 'web-serverfarms'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
      {
        name: privateEndpointSubnetName
        properties: {
          addressPrefix: privateEndpointSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        name: webIntegrationSubnetName
        properties: {
          addressPrefix: webIntegrationSubnetPrefix
          delegations: [
            {
              name: 'web-serverfarms-web'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
          serviceEndpoints: [
            {
              service: 'Microsoft.Web'
            }
          ]
        }
      }
    ]
  }
}

resource blobPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: blobPrivateDnsZoneName
  location: 'global'
  tags: tags
}

resource queuePrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: queuePrivateDnsZoneName
  location: 'global'
  tags: tags
}

resource tablePrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: tablePrivateDnsZoneName
  location: 'global'
  tags: tags
}

resource blobPrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: blobPrivateDnsZone
  name: '${virtualNetworkName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
}

resource queuePrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: queuePrivateDnsZone
  name: '${virtualNetworkName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
}

resource tablePrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: tablePrivateDnsZone
  name: '${virtualNetworkName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
}

module storage './modules/storage.bicep' = {
  name: 'storage'
  params: {
    storageAccountName: storageAccountName
    deploymentStorageAccountName: deploymentStorageAccountName
    location: location
    privateEndpointSubnetId: '${virtualNetwork.id}/subnets/${privateEndpointSubnetName}'
    privateDnsZoneIds: {
      blob: blobPrivateDnsZone.id
      queue: queuePrivateDnsZone.id
      table: tablePrivateDnsZone.id
    }
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    tags: tags
  }
}

module functionApp './modules/function-app.bicep' = {
  name: 'functionApp'
  params: {
    functionAppName: functionAppName
    location: location
    allowedCorsOrigins: allowedCorsOrigins
    storageAccountName: storage.outputs.storageAccountName
    storageBlobServiceUri: storage.outputs.blobServiceUri
    storageQueueServiceUri: storage.outputs.queueServiceUri
    storageTableServiceUri: storage.outputs.tableServiceUri
    applicationInsightsConnectionString: monitoring.outputs.applicationInsightsConnectionString
    applicationInsightsId: monitoring.outputs.applicationInsightsId
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    containerRegistryName: containerRegistryName
    containerImageReference: functionContainerImage
    authClientId: functionAuthClientId
    authTenantId: functionAuthTenantId
    analysisSubscriptionId: analysisSubscriptionId
    defaultSourceRegion: defaultSourceRegion
    defaultTargetRegion: defaultTargetRegion
    cloudEnvironment: cloudEnvironment
    armEndpoint: armEndpoint
    managementScope: managementScope
    azureAuthorityHost: azureAuthorityHost
    functionIntegrationSubnetId: '${virtualNetwork.id}/subnets/${functionIntegrationSubnetName}'
    serviceName: 'api'
    tags: tags
  }
}

module webApp './modules/web-app.bicep' = {
  name: 'webApp'
  params: {
    webAppName: webAppName
    location: location
    webIntegrationSubnetId: '${virtualNetwork.id}/subnets/${webIntegrationSubnetName}'
    functionAppBaseUrl: functionApp.outputs.functionAppBaseUrl
    functionAuthResource: functionAuthResource
    defaultSourceRegion: defaultSourceRegion
    defaultTargetRegion: defaultTargetRegion
    cloudEnvironment: cloudEnvironment
    azureAuthorityHost: azureAuthorityHost
    authClientId: webAuthClientId
    authTenantId: webAuthTenantId
    authClientCredentialSettingName: webAuthClientCredentialSettingName
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    enableBuiltInAuth: !empty(webAuthClientId) && webAuthClientId != '__ip_restrict__'
    tags: tags
  }
}

output functionAppName string = functionApp.outputs.functionAppName
output functionAppBaseUrl string = functionApp.outputs.functionAppBaseUrl
output functionAppPrincipalId string = functionApp.outputs.principalId
output functionAppUserAssignedPrincipalId string = functionApp.outputs.userAssignedPrincipalId
output functionAppUserAssignedClientId string = functionApp.outputs.userAssignedClientId
output containerRegistryName string = functionApp.outputs.containerRegistryName
output containerRegistryLoginServer string = functionApp.outputs.containerRegistryLoginServer
output containerImageName string = functionApp.outputs.containerImageName
output storageAccountName string = storage.outputs.storageAccountName
output deploymentStorageAccountName string = storage.outputs.deploymentStorageAccountName
output deploymentPackagesContainerName string = storage.outputs.deploymentPackagesContainerName
output deploymentBlobServiceUri string = storage.outputs.deploymentBlobServiceUri
output virtualNetworkName string = virtualNetwork.name
output webAppName string = webApp.outputs.webAppName
output webAppUrl string = webApp.outputs.webAppUrl
output webAppPrincipalId string = webApp.outputs.principalId

output logAnalyticsWorkspaceName string = monitoring.outputs.logAnalyticsWorkspaceName
output logAnalyticsWorkspaceId string = monitoring.outputs.logAnalyticsWorkspaceId
output logAnalyticsWorkspaceCustomerId string = monitoring.outputs.logAnalyticsWorkspaceCustomerId
output applicationInsightsName string = monitoring.outputs.applicationInsightsName
output applicationInsightsId string = monitoring.outputs.applicationInsightsId
output functionAppDiagnosticSettingId string = functionApp.outputs.diagnosticSettingId
output webAppDiagnosticSettingId string = webApp.outputs.diagnosticSettingId
output storageDiagnosticSettingIds array = storage.outputs.diagnosticSettingIds
output containerRegistryDiagnosticSettingId string = functionApp.outputs.containerRegistryDiagnosticSettingId
