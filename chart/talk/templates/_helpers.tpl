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

{{/*
Hostname helpers. Prefer the new global.domains map; fall back to the legacy
global.domain / global.zitadelDomain values during the migration so the chart
keeps rendering against pre-subdomain values files.

Usage: {{ include "talk.host" (list $ "admin") }}
*/}}
{{- define "talk.host" -}}
{{- $root := index . 0 -}}
{{- $key := index . 1 -}}
{{- $domains := dig "domains" (dict) $root.Values.global -}}
{{- $explicit := index $domains $key -}}
{{- if $explicit -}}
{{- $explicit -}}
{{- else if $root.Values.global.baseDomain -}}
{{- printf "%s.%s" $key $root.Values.global.baseDomain -}}
{{- else if eq $key "zitadel" -}}
{{- $root.Values.global.zitadelDomain -}}
{{- else -}}
{{- $root.Values.global.domain -}}
{{- end -}}
{{- end }}

{{/*
Wildcard SNI for the public Gateway listener. Uses the configured base domain
when present (so a single cert covers every product subdomain) and otherwise
falls back to the legacy single-host name.
*/}}
{{- define "talk.publicWildcardHostname" -}}
{{- if .Values.global.baseDomain -}}
*.{{ .Values.global.baseDomain }}
{{- else -}}
{{ .Values.global.domain }}
{{- end -}}
{{- end }}
