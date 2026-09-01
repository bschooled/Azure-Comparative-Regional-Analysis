@description('Workbook display name.')
param workbookDisplayName string

@description('Workbook serialized JSON content.')
param workbookJson string

@description('Azure location for the workbook resource.')
param location string

@description('Azure resource ID used as workbook source.')
param sourceId string

@description('Tags applied to the workbook.')
param tags object = {}

resource workbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: guid(resourceGroup().id, 'Microsoft.Insights/workbooks', workbookDisplayName)
  location: location
  kind: 'shared'
  tags: tags
  properties: {
    category: 'workbook'
    displayName: workbookDisplayName
    serializedData: workbookJson
    sourceId: sourceId
    version: 'Notebook/1.0'
  }
}

output workbookId string = workbook.id
