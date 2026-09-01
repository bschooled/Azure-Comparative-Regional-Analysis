@description('Azure Container Registry name that receives the role assignment.')
param containerRegistryName string

@description('Principal ID granted access to the registry.')
param principalId string

@description('Role definition ID assigned to the principal.')
param roleDefinitionId string

@description('Stable seed used to derive the role assignment name.')
param assignmentSeed string

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: containerRegistryName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.id, principalId, assignmentSeed)
  scope: containerRegistry
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: roleDefinitionId
  }
}
