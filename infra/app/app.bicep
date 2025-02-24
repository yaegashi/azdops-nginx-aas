param name string
param location string = resourceGroup().location
param tags object = {}
param appServicePlanId string
param applicationInsightsName string = ''
param logAnalyticsWorkspaceName string
param dnsDomainName string = ''
param dnsWildcard bool = false
@allowed(['CName', 'A'])
param dnsRecordType string = 'CName'
param dnsCertificateKeyVaultId string = ''
param dnsCertificateKeyVaultSecretName string = ''
param msClientId string
param msTenantId string
param msClientSecretKV string
param msAllowedGroupId string = ''
param storageAccountName string
param userAssignedIdentityName string

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: userAssignedIdentityName
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource storage 'Microsoft.Storage/storageAccounts@2022-05-01' existing = {
  name: storageAccountName
  resource fileService 'fileServices' = {
    name: 'default'
    resource nginx 'shares' = {
      name: 'nginx'
    }
  }
}

resource appCertificate 'Microsoft.Web/certificates@2024-04-01' = if (!empty(dnsDomainName)) {
  name: 'app-cert-${dnsDomainName}'
  location: location
  tags: tags
  properties: {
    canonicalName: dnsDomainName
    serverFarmId: appServicePlanId
  }
}

resource dnsCertificate 'Microsoft.Web/certificates@2024-04-01' = if (!empty(dnsCertificateKeyVaultId)) {
  name: 'dns-cert-${dnsDomainName}'
  location: location
  tags: tags
  properties: {
    hostNames: ['*.${dnsDomainName}']
    keyVaultId: dnsCertificateKeyVaultId
    keyVaultSecretName: dnsCertificateKeyVaultSecretName
    serverFarmId: appServicePlanId
  }
}

resource app 'Microsoft.Web/sites@2024-04-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    siteConfig: {
      linuxFxVersion: 'DOCKER|ghcr.io/yaegashi/azdops-nginx-aas/nginx:latest'
      alwaysOn: true
      azureStorageAccounts: {}
    }
    serverFarmId: appServicePlanId
    keyVaultReferenceIdentity: userAssignedIdentity.id
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentity.id}': {}
    }
  }
}

resource appHostNameBinding 'Microsoft.Web/sites/hostNameBindings@2024-04-01' = {
  parent: app
  name: dnsDomainName
  properties: {
    azureResourceName: app.name
    azureResourceType: 'Website'
    siteName: app.name
    sslState: 'SniEnabled'
    thumbprint: appCertificate.properties.thumbprint
    customHostNameDnsRecordType: dnsRecordType
  }
}

resource appHostNameBindingWildcard 'Microsoft.Web/sites/hostNameBindings@2024-04-01' = if (dnsWildcard) {
  dependsOn: [appHostNameBinding]
  parent: app
  name: '*.${dnsDomainName}'
  properties: {
    azureResourceName: app.name
    azureResourceType: 'Website'
    siteName: app.name
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = if (!empty(applicationInsightsName)) {
  name: applicationInsightsName
}

resource configAppSettings 'Microsoft.Web/sites/config@2024-04-01' = {
  name: 'appsettings'
  parent: app
  properties: {
    WEBSITES_ENABLE_APP_SERVICE_STORAGE: 'true'
    APPLICATIONINSIGHTS_CONNECTION_STRING: applicationInsights.properties.ConnectionString
    MICROSOFT_PROVIDER_AUTHENTICATION_SECRET: '@Microsoft.KeyVault(SecretUri=${msClientSecretKV})'
    NGINX_HOST: empty(dnsDomainName) ? app.properties.defaultHostName : dnsDomainName
    NGINX_PORT: '80'
  }
}

resource configLogs 'Microsoft.Web/sites/config@2024-04-01' = {
  dependsOn: [configAppSettings]
  name: 'logs'
  parent: app
  properties: {
    applicationLogs: { fileSystem: { level: 'Verbose' } }
    detailedErrorMessages: { enabled: true }
    failedRequestsTracing: { enabled: true }
    httpLogs: { fileSystem: { enabled: true, retentionInDays: 1, retentionInMb: 35 } }
  }
}

resource configAuthSettingsV2 'Microsoft.Web/sites/config@2024-04-01' = {
  dependsOn: [configLogs]
  name: 'authsettingsV2'
  parent: app
  properties: {
    globalValidation: {
      requireAuthentication: true
      unauthenticatedClientAction: 'RedirectToLoginPage'
      redirectToProvider: 'azureActiveDirectory'
    }
    identityProviders: {
      azureActiveDirectory: {
        registration: {
          clientId: msClientId
          clientSecretSettingName: 'MICROSOFT_PROVIDER_AUTHENTICATION_SECRET'
          openIdIssuer: 'https://sts.windows.net/${msTenantId}/v2.0'
        }
        validation: {
          allowedAudiences: [
            'api://${msClientId}'
          ]
          defaultAuthorizationPolicy: {
            allowedPrincipals: {
              groups: empty(msAllowedGroupId) ? null : [msAllowedGroupId]
            }
          }
        }
        login: {
          loginParameters: ['scope=openid profile email offline_access']
        }
      }
    }
    platform: {
      enabled: true
    }
    login: {
      tokenStore: {
        enabled: true
      }
    }
  }
}

resource configStorageMount 'Microsoft.Web/sites/config@2024-04-01' = {
  name: 'azurestorageaccounts'
  parent: app
  properties: {
    azureStorageAccounts: {
      type: 'AzureFiles'
      protocol: 'SMB'
      accountName: storage.name
      shareName: storage::fileService::nginx.name
      accessKey: storage.listKeys().keys[0].value
      mountPath: '/nginx'
    }
  }
}

resource logAnalytics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'logAnalytics'
  scope: app
  properties: {
    logs: [
      {
        category: 'AppServiceHTTPLogs'
        enabled: true
      }
      {
        category: 'AppServiceConsoleLogs'
        enabled: true
      }
      {
        category: 'AppServiceAppLogs'
        enabled: true
      }
      {
        category: 'AppServiceAuditLogs'
        enabled: true
      }
      {
        category: 'AppServiceIPSecAuditLogs'
        enabled: true
      }
      {
        category: 'AppServicePlatformLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
    workspaceId: logAnalyticsWorkspace.id
  }
}

output id string = app.id
output name string = app.name
