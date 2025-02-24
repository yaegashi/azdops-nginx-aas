param name string
param dnsDomainName string
param dnsWildcard bool = false

resource app 'Microsoft.Web/sites@2022-03-01' existing = {
  name: name
}

resource appHostNameBinding 'Microsoft.Web/sites/hostNameBindings@2024-04-01' = {
  parent: app
  name: dnsDomainName
  properties: {
    siteName: app.name
  }
}

resource appHostNameBindigWildcard 'Microsoft.Web/sites/hostNameBindings@2024-04-01' = if (dnsWildcard) {
  dependsOn: [appHostNameBinding]
  parent: app
  name: '*.${dnsDomainName}'
  properties: {
    siteName: app.name
  }
}
