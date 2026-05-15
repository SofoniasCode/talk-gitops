{{/*
Chart name, truncated to 63 chars.
*/}}
{{- define "talk.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified release name, truncated to 63 chars.
*/}}
{{- define "talk.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Common labels applied to every resource.
*/}}
{{- define "talk.labels" -}}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: talk
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
{{- end }}

{{/*
Key Vault secret key helper.
Generates keys like: talk-dev-zitadel-masterkey
Usage: {{ include "talk.kvKey" (list $ "zitadel" "masterkey") }}
*/}}
{{- define "talk.kvKey" -}}
{{- $root := index . 0 -}}
{{- $component := index . 1 -}}
{{- $key := index . 2 -}}
talk-{{ $root.Values.global.environment }}-{{ $component }}-{{ $key }}
{{- end }}
