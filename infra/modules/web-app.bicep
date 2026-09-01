@description('Web App name.')
param webAppName string

@description('Azure location for deployed resources.')
param location string

@description('Subnet resource ID used for regional VNet integration.')
param webIntegrationSubnetId string

@description('Function App base URL used by the proxy layer.')
param functionAppBaseUrl string

@description('Application ID URI used by the web app managed identity to request access tokens for the Function App.')
param functionAuthResource string = ''

@description('Default source region shown in the web app.')
param defaultSourceRegion string

@description('Default target region shown in the web app.')
param defaultTargetRegion string

@description('Azure cloud environment used by the hosted web app.')
param cloudEnvironment string = 'AzureCloud'

@description('Authority host used by the hosted web app credential chain.')
param azureAuthorityHost string = environment().authentication.loginEndpoint

@description('Microsoft Entra application client ID for built-in authentication.')
param authClientId string

@description('Microsoft Entra tenant ID used for built-in authentication.')
param authTenantId string

@description('App setting name that stores the Microsoft Entra client secret for App Service auth. Leave empty to avoid configuring a client secret.')
param authClientCredentialSettingName string = ''

@description('Log Analytics workspace resource ID that receives platform diagnostics.')
param logAnalyticsWorkspaceId string

@description('When true, built-in App Service authentication is enabled. Set to false for IP-restriction-only deployments.')
param enableBuiltInAuth bool = true

@description('Tags applied to resources.')
param tags object = {}

var appServicePlanName = '${webAppName}-plan'

resource plan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: appServicePlanName
  location: location
  kind: 'linux'
  sku: {
    name: 'S1'
    tier: 'Standard'
    size: 'S1'
    capacity: 1
  }
  tags: tags
  properties: {
    reserved: true
  }
}

resource app 'Microsoft.Web/sites@2024-04-01' = {
  name: webAppName
  location: location
  kind: 'app,linux'
  identity: {
    type: 'SystemAssigned'
  }
  tags: union(tags, {
    'azd-service-name': 'web'
  })
  properties: {
    clientAffinityEnabled: false
    reserved: true
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    serverFarmId: plan.id
    vnetRouteAllEnabled: false
  }
}

resource webConfig 'Microsoft.Web/sites/config@2024-04-01' = {
  name: 'web'
  parent: app
  properties: {
    appCommandLine: 'node server.js'
    alwaysOn: true
    ftpsState: 'Disabled'
    http20Enabled: true
    minTlsCipherSuite: 'TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384'
    linuxFxVersion: 'NODE|22-lts'
    minTlsVersion: '1.2'
  }
}

resource appSettings 'Microsoft.Web/sites/config@2024-04-01' = {
  name: 'appsettings'
  parent: app
  properties: {
    FUNCTION_BASE_URL: functionAppBaseUrl
    FUNCTION_AUTH_RESOURCE: functionAuthResource
    FUNCTION_API_KEY: ''
    DEFAULT_SOURCE_REGION: defaultSourceRegion
    DEFAULT_TARGET_REGION: defaultTargetRegion
    AZURE_CLOUD_ENVIRONMENT: cloudEnvironment
    CLOUD_ENVIRONMENT: cloudEnvironment
    AZURE_AUTHORITY_HOST: azureAuthorityHost
    CACHE_TTL_SECONDS: '120'
    RUN_CACHE_TTL_SECONDS: '600'
    WEBSITE_NODE_DEFAULT_VERSION: '~22'
  }
}

resource networkConfig 'Microsoft.Web/sites/networkConfig@2024-04-01' = {
  name: 'virtualNetwork'
  parent: app
  properties: {
    subnetResourceId: webIntegrationSubnetId
    swiftSupported: true
  }
}

resource authSettings 'Microsoft.Web/sites/config@2022-09-01' = if (enableBuiltInAuth) {
  name: 'authsettingsV2'
  parent: app
  properties: {
    platform: {
      enabled: true
      runtimeVersion: '~1'
    }
    globalValidation: {
      requireAuthentication: true
      unauthenticatedClientAction: 'RedirectToLoginPage'
      redirectToProvider: 'azureActiveDirectory'
    }
    login: {
      tokenStore: {
        enabled: true
      }
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: {
          clientId: authClientId
          openIdIssuer: uri(environment().authentication.loginEndpoint, '${authTenantId}/v2.0')
          clientSecretSettingName: empty(authClientCredentialSettingName) ? null : authClientCredentialSettingName
        }
      }
    }
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${webAppName}-diagnostics'
  scope: app
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

output webAppName string = app.name
output webAppId string = app.id
output webAppUrl string = 'https://${app.properties.defaultHostName}'
output principalId string = app.identity.principalId
output diagnosticSettingId string = diagnostics.id
