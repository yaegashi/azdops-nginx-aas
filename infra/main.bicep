targetScope = 'subscription'

@minLength(1)
@maxLength(64)
param environmentName string

@minLength(1)
param location string

param principalId string

param userAssignedIdentityName string = ''

param resourceGroupName string = ''

param keyVaultName string = ''

param storageAccountName string = ''

param logAnalyticsName string = ''

param applicationInsightsName string = ''

param applicationInsightsDashboardName string = ''

param appCertificateExists bool = false

param dnsZoneSubscriptionId string = subscription().subscriptionId

param dnsZoneResourceGroupName string = ''

param dnsZoneName string = ''

param dnsRecordName string = ''

param dnsWildcard bool = false

param dnsCertificateExists bool = false

param msTenantId string
param msClientId string
@secure()
param msClientSecret string
param msAllowedGroupId string = ''

var abbrs = loadJsonContent('./abbreviations.json')

var tags = {
  'azd-env-name': environmentName
}

#disable-next-line no-unused-vars
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location, rg.name))

var dnsEnable = !empty(dnsZoneResourceGroupName) && !empty(dnsZoneName) && !empty(dnsRecordName)
var dnsDomainName = !dnsEnable ? '' : dnsRecordName == '@' ? dnsZoneName : '${dnsRecordName}.${dnsZoneName}'

resource dnsZoneRG 'Microsoft.Resources/resourceGroups@2021-04-01' existing = if (dnsEnable && !appCertificateExists) {
  scope: subscription(dnsZoneSubscriptionId)
  name: dnsZoneResourceGroupName
}

module dnsTXT './app/dns-txt.bicep' = if (dnsEnable && !appCertificateExists) {
  name: 'dnsTXT'
  scope: dnsZoneRG
  params: {
    dnsZoneName: dnsZoneName
    dnsRecordName: dnsRecordName == '@' ? 'asuid' : 'asuid.${dnsRecordName}'
    txt: toLower(appPrep1.outputs.customDomainVerificationId)
  }
}

module dnsCNAME './app/dns-cname.bicep' = if (dnsEnable && !appCertificateExists && dnsRecordName != '@') {
  name: 'dnsCNAME'
  scope: dnsZoneRG
  params: {
    dnsZoneName: dnsZoneName
    dnsRecordName: dnsRecordName
    cname: appPrep1.outputs.fqdn
  }
}

module dnsCNAMEWildcard './app/dns-cname.bicep' = if (dnsEnable && !appCertificateExists && dnsRecordName != '@' && dnsWildcard) {
  name: 'dnsCNAMEWildcard'
  scope: dnsZoneRG
  params: {
    dnsZoneName: dnsZoneName
    dnsRecordName: '*.${dnsRecordName}'
    cname: appPrep1.outputs.fqdn
  }
}

module dnsA './app/dns-a.bicep' = if (dnsEnable && !appCertificateExists && dnsRecordName == '@') {
  name: 'dnsA'
  scope: dnsZoneRG
  params: {
    dnsZoneName: dnsZoneName
    dnsRecordName: dnsRecordName
    a: appPrep1.outputs.staticIp
  }
}

module dnsAWildcard './app/dns-a.bicep' = if (dnsEnable && !appCertificateExists && dnsRecordName == '@' && dnsWildcard) {
  name: 'dnsAWildcard'
  scope: dnsZoneRG
  params: {
    dnsZoneName: dnsZoneName
    dnsRecordName: '*'
    a: appPrep1.outputs.staticIp
  }
}

module dnsAccess './app/dns-access.bicep' = if (dnsEnable) {
  dependsOn: [keyVaultAccessUserAssignedIdentity] // Insert delay
  name: 'dnsAccess'
  scope: dnsZoneRG
  params: {
    dnsZoneName: dnsZoneName
    principalId: userAssignedIdentity.outputs.principalId
  }
}

resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

module userAssignedIdentity './app/identity.bicep' = {
  name: 'userAssignedIdentity'
  scope: rg
  params: {
    name: !empty(userAssignedIdentityName)
      ? userAssignedIdentityName
      : '${abbrs.managedIdentityUserAssignedIdentities}${resourceToken}'
    location: location
    tags: tags
  }
}

module keyVault './core/security/keyvault.bicep' = {
  name: 'keyVault'
  scope: rg
  params: {
    name: !empty(keyVaultName) ? keyVaultName : '${abbrs.keyVaultVaults}${resourceToken}'
    location: location
    tags: tags
  }
}

module keyVaultAccessUserAssignedIdentity './core/security/keyvault-access.bicep' = {
  name: 'keyVaultAccessUserAssignedIdentity'
  scope: rg
  params: {
    keyVaultName: keyVault.outputs.name
    principalId: userAssignedIdentity.outputs.principalId
    permissions: {
      secrets: ['list', 'get']
      certificates: ['list', 'get', 'import']
    }
  }
}

// https://learn.microsoft.com/en-us/azure/app-service/configure-ssl-certificate#import-a-certificate-from-key-vault
module msGraphPrincipal1 './app/msgraph-principal.bicep' = {
  name: 'msGraphPrincipal1'
  scope: rg
  params: {
    appId: 'abfa0a7c-a6b6-4736-8310-5855508787cd' // "Microsoft App Service"
  }
}

module msGraphPrincipal2 './app/msgraph-principal.bicep' = {
  name: 'msGraphPrincipal2'
  scope: rg
  params: {
    appId: 'f3c21649-0979-4721-ac85-b0216b2cf413' // "Microsoft.Azure.CertificateRegistration"
  }
}

module keyVaultAccessAppService1 './core/security/keyvault-access.bicep' = {
  name: 'keyVaultAccessAppService1'
  scope: rg
  params: {
    keyVaultName: keyVault.outputs.name
    principalId: msGraphPrincipal1.outputs.principalId
    permissions: {
      secrets: ['get']
      certificates: ['get']
    }
  }
}

module keyVaultAccessAppService2 './core/security/keyvault-access.bicep' = {
  name: 'keyVaultAccessAppService2'
  scope: rg
  params: {
    keyVaultName: keyVault.outputs.name
    principalId: msGraphPrincipal2.outputs.principalId
    permissions: {
      secrets: ['get']
      certificates: ['get']
    }
  }
}

module keyVaultAccessDeployment './core/security/keyvault-access.bicep' = {
  name: 'keyVaultAccessDeployment'
  scope: rg
  params: {
    keyVaultName: keyVault.outputs.name
    principalId: principalId
    permissions: {
      secrets: ['list', 'get', 'set']
      certificates: ['list', 'get', 'import']
    }
  }
}

module keyVaultSecretMsClientSecret './core/security/keyvault-secret.bicep' = {
  name: 'keyVaultSecretMsClientSecret'
  scope: rg
  params: {
    name: 'MS-CLIENT-SECRET'
    tags: tags
    keyVaultName: keyVault.outputs.name
    secretValue: msClientSecret
  }
}

module storageAccount './core/storage/storage-account.bicep' = {
  name: 'storageAccount'
  scope: rg
  params: {
    location: location
    tags: tags
    name: !empty(storageAccountName) ? storageAccountName : '${abbrs.storageStorageAccounts}${resourceToken}'
  }
}

module storageAccess './app/storage-access.bicep' = {
  name: 'storageAccess'
  scope: rg
  params: {
    storageAccountName: storageAccount.outputs.name
    principalId: principalId
  }
}

module monitoring './core/monitor/monitoring.bicep' = {
  name: 'monitoring'
  scope: rg
  params: {
    location: location
    tags: tags
    logAnalyticsName: !empty(logAnalyticsName)
      ? logAnalyticsName
      : '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    applicationInsightsName: !empty(applicationInsightsName)
      ? applicationInsightsName
      : '${abbrs.insightsComponents}${resourceToken}'
    applicationInsightsDashboardName: !empty(applicationInsightsDashboardName)
      ? applicationInsightsDashboardName
      : '${abbrs.portalDashboards}${resourceToken}'
  }
}
module asp './core/host/appserviceplan.bicep' = {
  name: 'asp'
  scope: rg
  params: {
    location: location
    tags: tags
    name: '${abbrs.webServerFarms}${resourceToken}'
    sku: { name: 'B1' }
    kind: 'Linux'
  }
}

module appPrep1 './app/app-prep1.bicep' = if (dnsEnable && !appCertificateExists) {
  name: 'appPrep1'
  scope: rg
  params: {
    location: location
    tags: tags
    name: '${abbrs.webSitesAppService}${resourceToken}'
    appServicePlanId: asp.outputs.id
  }
}

module appPrep2 './app/app-prep2.bicep' = if (dnsEnable && !appCertificateExists) {
  dependsOn: [dnsTXT]
  name: 'appPrep2'
  scope: rg
  params: {
    name: '${abbrs.webSitesAppService}${resourceToken}'
    dnsDomainName: dnsDomainName
    dnsWildcard: dnsWildcard
  }
}

module app './app/app.bicep' = {
  dependsOn: [dnsCNAME, dnsA, appPrep2]
  name: 'app'
  scope: rg
  params: {
    location: location
    tags: tags
    name: '${abbrs.webSitesAppService}${resourceToken}'
    appServicePlanId: asp.outputs.id
    applicationInsightsName: monitoring.outputs.applicationInsightsName
    logAnalyticsWorkspaceName: monitoring.outputs.logAnalyticsWorkspaceName
    storageAccountName: storageAccount.outputs.name
    userAssignedIdentityName: userAssignedIdentity.outputs.name
    dnsDomainName: dnsDomainName
    dnsWildcard: dnsWildcard
    dnsRecordType: dnsRecordName == '@' ? 'A' : 'CName'
    dnsCertificateKeyVaultId: dnsCertificateExists ? keyVault.outputs.id : ''
    dnsCertificateKeyVaultSecretName: dnsCertificateExists ? 'DNS-CERTIFICATE' : ''
    msTenantId: msTenantId
    msClientId: msClientId
    msClientSecretKV: '${keyVault.outputs.endpoint}secrets/MS-CLIENT-SECRET'
    msAllowedGroupId: msAllowedGroupId
  }
}

output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_SUBSCRIPTION_ID string = subscription().subscriptionId
output AZURE_PRINCIPAL_ID string = principalId
output AZURE_RESOURCE_GROUP_NAME string = rg.name
output AZURE_APP_NAME string = app.outputs.name
output AZURE_KEY_VAULT_NAME string = keyVault.outputs.name
output AZURE_KEY_VAULT_ENDPOINT string = keyVault.outputs.endpoint
output AZURE_STORAGE_ACCOUNT_NAME string = storageAccount.outputs.name
output APP_CERTIFICATE_EXISTS bool = !empty(dnsDomainName)
