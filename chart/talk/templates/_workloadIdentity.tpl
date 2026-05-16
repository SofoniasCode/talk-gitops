{{/*
Workload-identity helpers — render the cloud-appropriate annotations on a
ServiceAccount, and the cloud-appropriate label on the workload Pod so the
mutating webhook injects the right token volume.

Centralising these here means an AWS port only needs to fill in the eks.*
branches; every consumer of these helpers stays as-is.

Usage:

  metadata:
    annotations:
      {{- include "talk.workloadIdentityAnnotations" (list $ .Values.foo.workloadIdentity) | nindent 6 }}
    labels:
      {{- include "talk.workloadIdentitySaLabels" $ | nindent 6 }}

  template:
    metadata:
      labels:
        {{- include "talk.workloadIdentityPodLabels" $ | nindent 8 }}

The second argument to talk.workloadIdentityAnnotations is a values map with
the shape: { clientId: "...", tenantId: "..." } for Azure, or
{ roleArn: "..." } for AWS.
*/}}

{{- define "talk.workloadIdentityAnnotations" -}}
{{- $root := index . 0 -}}
{{- $cfg := index . 1 -}}
{{- if eq $root.Values.cloud "azure" -}}
azure.workload.identity/client-id: {{ $cfg.clientId | quote }}
azure.workload.identity/tenant-id: {{ $cfg.tenantId | quote }}
{{- else if eq $root.Values.cloud "aws" -}}
eks.amazonaws.com/role-arn: {{ required "AWS workload identity requires roleArn" $cfg.roleArn | quote }}
{{- else -}}
{{- fail (printf "Unsupported cloud %q (expected azure | aws)" $root.Values.cloud) -}}
{{- end -}}
{{- end -}}

{{/*
SA-level label. Azure Workload Identity uses a ServiceAccount label
(azure.workload.identity/use=true) in addition to the namespace label.
IRSA needs nothing. Returns an empty string on AWS so it nindent-s clean.
*/}}
{{- define "talk.workloadIdentitySaLabels" -}}
{{- $root := . -}}
{{- if eq $root.Values.cloud "azure" -}}
azure.workload.identity/use: "true"
{{- end -}}
{{- end -}}

{{/*
Pod-template label. Same idea as above but applied to the Pod, which is
what the mutating webhook actually keys on.
*/}}
{{- define "talk.workloadIdentityPodLabels" -}}
{{- $root := . -}}
{{- if eq $root.Values.cloud "azure" -}}
azure.workload.identity/use: "true"
{{- end -}}
{{- end -}}

{{/*
Name of the ClusterSecretStore that every ExternalSecret points at.
One per cloud — both ClusterSecretStore templates and ExternalSecret
consumers use this helper so a future rename is a one-line change.
*/}}
{{- define "talk.secretStoreName" -}}
{{- if eq .Values.cloud "azure" -}}
talk-azure-key-vault
{{- else if eq .Values.cloud "aws" -}}
talk-aws-secrets-manager
{{- else -}}
{{- fail (printf "Unsupported cloud %q" .Values.cloud) -}}
{{- end -}}
{{- end -}}
