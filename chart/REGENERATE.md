# Regenerating `values-<env>.yaml`

`chart/values-<env>.yaml` is the per-environment input to the Helm chart.
It is hand-written for `dev` today, and **regenerated from Terraform** for
every new environment or customer.

## Generate

```sh
cd ../talk-infra/terraform/azure
../../scripts/tf-init.sh <env-or-customer>
terraform apply -var-file=terraform.tfvars
```

The `local_file.helm_values` resource writes
`../../talk-gitops/chart/values-<env>.yaml` automatically — no `terraform
output` step needed.

Replace `<env>` with `dev` | `stg` | `prod` | `customer-<slug>`.

## Then fill in one value Terraform cannot know

**`oauth2Proxy.console.ipAllowlist`** — list of CIDRs allowed to reach
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
