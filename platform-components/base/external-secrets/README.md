# Azure External Secrets

This overlay resource set follows the External Secrets Operator `external-secrets.io/v1` API.

`talk-azure-key-vault` is a cluster-scoped `ClusterSecretStore` for Azure Key Vault using the
recommended referenced Workload Identity service account pattern. Replace these placeholders per
environment before applying to a real cluster:

- `vaultUrl`
- `azure.workload.identity/client-id`
- `azure.workload.identity/tenant-id`

Official docs:

- ExternalSecret API: https://external-secrets.io/main/api/spec/
- Azure Key Vault provider: https://external-secrets.io/latest/provider/azure-key-vault
