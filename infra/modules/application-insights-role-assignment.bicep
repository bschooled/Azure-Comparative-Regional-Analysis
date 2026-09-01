@description('Application Insights resource ID that receives the role assignment.')
param applicationInsightsId string

@description('Application Insights component name that receives the role assignment.')
param applicationInsightsName string

@description('Principal ID granted access to the Application Insights component.')
param principalId string

@description('Role definition ID assigned to the principal.')
param roleDefinitionId string

@description('Stable seed used to derive the role assignment name.')
param assignmentSeed string

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: applicationInsightsName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(applicationInsightsId, principalId, assignmentSeed)
  scope: applicationInsights
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: roleDefinitionId
  }
}
