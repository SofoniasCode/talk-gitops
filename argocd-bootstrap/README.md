# argocd-bootstrap

A tiny Helm chart that emits exactly one Argo CD `Application` pointing at
the `chart/talk` workload chart for a specific environment. Replaces the
previous `argocd-applications/<env>/talk.yaml` manifest tree.

## Why a chart and not raw YAML

The previous layout had 12 hand-maintained Application YAMLs (4 per env)
with the GitHub repo URL hardcoded in each. Forking the gitops repo into a
different org was a 12-file `sed` job. With this chart it's a one-line
edit in `values-<env>.yaml`.

## Install

After the cluster is up and Argo CD is running:

```sh
helm template talk-bootstrap ./argocd-bootstrap \
  -f ./argocd-bootstrap/values-dev.yaml \
  | kubectl apply -f -
```

For a customer deployment, copy `values-dev.yaml` to
`values-customer-<slug>.yaml`, set `environment` and `gitopsRepo`, and run
the same command.

## Inputs

See [values.yaml](./values.yaml) for the full list. The only two values
you typically override per environment are:

- `environment` — drives the Application name and selects
  `chart/values-<env>.yaml`
- `gitopsRepo` — `<org>/<repo>`; the URL is composed as
  `https://github.com/<org>/<repo>.git`. Override `gitopsRepoUrl` directly
  to point at a non-GitHub mirror.
