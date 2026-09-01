@description('Storage account name that receives the role assignment.')
param storageAccountName string

@description('Principal ID granted access to the storage account.')
param principalId string

@description('Role definition ID assigned to the principal.')
param roleDefinitionId string

@description('Stable seed used to derive the role assignment name.')
param assignmentSeed string

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, principalId, assignmentSeed)
  scope: storageAccount
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: roleDefinitionId
  }
}
