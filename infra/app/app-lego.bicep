param containerAppsEnvironmentName string
param containerAppName string
param location string
param tags object = {}
param storageAccountName string
param keyVaultName string
param dnsDomainName string
param legoEmail string
param legoServer string
param userAssignedIdentityName string

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: userAssignedIdentityName
}

resource storage 'Microsoft.Storage/storageAccounts@2022-05-01' existing = {
  name: storageAccountName
  resource fileService 'fileServices' = {
    name: 'default'
    resource lego 'shares' = {
      name: 'lego'
    }
  }
}

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-10-02-preview' existing = {
  name: containerAppsEnvironmentName
  resource lego 'storages' = {
    name: 'lego'
    properties: {
      azureFile: {
        accessMode: 'ReadWrite'
        accountName: storage.name
        accountKey: storage.listKeys().keys[0].value
        shareName: storage::fileService::lego.name
      }
    }
  }
}

resource appLego 'Microsoft.App/jobs@2024-10-02-preview' = {
  name: '${containerAppName}-lego'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentity.id}': {}
    }
  }
  properties: {
    environmentId: containerAppsEnvironment.id
    configuration: {
      replicaTimeout: 300
      triggerType: 'Schedule'
      scheduleTriggerConfig: {
        // Run at 00:00 UTC every day
        cronExpression: '0 0 * * *'
      }
      identitySettings: [
        {
          identity: userAssignedIdentity.id
          lifecycle: 'All'
        }
      ]
    }
    template: {
      volumes: [
        {
          name: 'lego'
          storageName: containerAppsEnvironment::lego.name
          storageType: 'AzureFile'
        }
      ]
      containers: [
        {
          name: 'legoaz'
          image: 'ghcr.io/yaegashi/azdops-nginx-aas/legoaz'
          command: [
            'sh'
            '-c'
          ]
          args: [
            'echo "$SCRIPT_BASE64" | base64 -d > /data/app-lego.sh && sh /data/app-lego.sh'
          ]
          env: [
            { name: 'AZURE_CLIENT_ID', value: userAssignedIdentity.properties.clientId }
            { name: 'AZURE_SUBSCRIPTION_ID', value: subscription().subscriptionId }
            { name: 'AZURE_KEY_VAULT_NAME', value: keyVaultName }
            { name: 'DNS_DOMAIN_NAME', value: dnsDomainName }
            { name: 'LEGO_PATH', value: '/data' }
            { name: 'LEGO_EMAIL', value: legoEmail }
            { name: 'LEGO_SERVER', value: legoServer }
            // The wildcard CNAME causes issues with LEGO's feature of following CNAME records.
            // https://go-acme.github.io/lego/usage/cli/options/#lego_disable_cname_support
            { name: 'LEGO_DISABLE_CNAME_SUPPORT', value: 'true' }
            { name: 'SCRIPT_BASE64', value: loadFileAsBase64('app-lego.sh') }
          ]
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          volumeMounts: [
            {
              volumeName: 'lego'
              subPath: 'data'
              mountPath: '/data'
            }
          ]
        }
      ]
    }
  }
}

output id string = appLego.id
output name string = appLego.name
