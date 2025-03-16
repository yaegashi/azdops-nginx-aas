// Retrieves the tenant-specific service principal ID for a globally defined application ID
// Notes:
// - You must have permissions to read all service principals in your tenant.
// - The application permission Application.ReadWrite.OwnedBy allows apps to read all service principals in the tenant.
// - This module uses the msgraph extension and should be kept separate from other deployments
//   as the Azure Portal does not show deployment details for deployments using the msgraph extension,
//   which can make troubleshooting more difficult
param appId string

extension msgraph

resource servicePrincipal 'Microsoft.Graph/servicePrincipals@v1.0' existing = {
  appId: appId
}

output principalId string = servicePrincipal.id
