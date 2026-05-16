# Regenerating `values-<env>.yaml`

`chart/values-<env>.yaml` is the per-environment input to the Helm chart.
It is hand-written for `dev` today, and **regenerated from Terraform** for
every new environment or customer.

## Generate

```sh
cd ../talk-infra/terraform
./scripts/tf-init.sh <env-or-customer>
terraform apply -var-file=terraform.tfvars
terraform output -raw helm_values_yaml > ../../talk-gitops/chart/values-<env>.yaml
```

Replace `<env>` with `dev` | `stg` | `prod` | `customer-<slug>`.

## Then fill in two values Terraform cannot know

1. **`oauth2Proxy.hostAliases[0].ip`** — the Envoy Gateway data-plane
   ClusterIP. Until you set this, oauth2-proxy times out on Zitadel OIDC
   discovery due to AKS hairpin routing.

   ```sh
   kubectl -n envoy-gateway-system get svc \
     -l gateway.envoyproxy.io/owning-gateway-name=talk-gateway \
     -o jsonpath='{.items[0].spec.clusterIP}'
   ```

2. **`oauth2Proxy.console.ipAllowlist`** — list of CIDRs allowed to reach
   the console subdomain. Defaults to `[]` (open) in dev; tighten before
   exposing console publicly in stg/prod.

## Image tags

`apps.*.image.tag` and `services.*.image.tag` default to `latest` in the
generated file. CI rewrites them to the build SHA on every push to a
deploy branch (see `.github/workflows/build-and-push.yml` in the `talk`
repo). Don't hand-edit these — they'll be overwritten.

## Why `values-stg.yaml` / `values-prod.yaml` aren't committed

There is no live stg or prod cluster today. When one is provisioned,
regenerate its `values-<env>.yaml` from Terraform — committing stale
stubs in the meantime invites them to drift out of schema with the chart.
