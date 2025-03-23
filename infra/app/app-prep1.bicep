param name string
param location string = resourceGroup().location
param tags object = {}
param appServicePlanId string
param appImage string

resource app 'Microsoft.Web/sites@2024-04-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    siteConfig: {
      linuxFxVersion: 'DOCKER|${appImage}'
      alwaysOn: true
      azureStorageAccounts: {}
    }
    serverFarmId: appServicePlanId
  }
}

output appId string = app.id
output fqdn string = app.properties.defaultHostName
output staticIp string = app.properties.outboundIpAddresses
output customDomainVerificationId string = app.properties.customDomainVerificationId
