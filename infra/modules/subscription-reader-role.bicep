targetScope = 'subscription'

@description('Principal ID to grant Reader access at subscription scope.')
param principalId string

@description('Stable name seed for the role assignment.')
param assignmentSeed string

resource subscriptionReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, assignmentSeed, 'Reader')
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
  }
}
