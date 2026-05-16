{{/*
Per-tier oauth2-proxy ConfigMap. Each tier owns its own `alpha-config.yaml`
that lists the upstream paths it terminates SSO for, plus the OIDC provider
that issues the session cookie.

Usage: {{- include "talk.oauth2Proxy.configmap" (dict "root" $ "tier" $tier "tierConfig" $tierConfig) }}
*/}}
{{- define "talk.oauth2Proxy.configmap" -}}
{{- $root := .root -}}
{{- $tier := .tier -}}
{{- $tierConfig := .tierConfig -}}
apiVersion: v1
kind: ConfigMap
metadata:
  name: oauth2-proxy-{{ $tier }}-config
  labels:
    app.kubernetes.io/name: oauth2-proxy
    app.kubernetes.io/component: {{ $tier }}
    {{- include "talk.labels" $root | nindent 4 }}
data:
  alpha-config.yaml: |
    server:
      bindAddress: 0.0.0.0:4180
    upstreamConfig:
      upstreams:
{{- range $tierConfig.upstreams }}
        - id: {{ .id }}
          path: {{ .path }}
          rewriteTarget: {{ .rewriteTarget }}
          uri: {{ .uri }}
{{- end }}
    providers:
      - id: zitadel
        provider: oidc
        clientID: "${OAUTH2_PROXY_CLIENT_ID}"
        clientSecret: "${OAUTH2_PROXY_CLIENT_SECRET}"
        scope: "openid email profile urn:zitadel:iam:user:resourceowner"
        oidcConfig:
          issuerURL: "${OAUTH2_PROXY_OIDC_ISSUER_URL}"
          insecureSkipIssuerVerification: ${OAUTH2_PROXY_INSECURE_SKIP_ISSUER_VERIFICATION}
          userIDClaim: sub
          groupsClaim: urn:talk:roles
        profileURL: "${OAUTH2_PROXY_OIDC_ISSUER_URL}/oidc/v1/userinfo"
        additionalClaims:
          - urn:talk:organization_id
          - urn:talk:roles
    injectRequestHeaders:
      - name: X-Talk-Subject-Id
        values:
          - claimSource:
              claim: user
      - name: X-Talk-Organization-Id
        values:
          - claimSource:
              claim: urn:talk:organization_id
      - name: X-Talk-Roles
        values:
          - claimSource:
              claim: groups
      - name: Authorization
        values:
          - claimSource:
              claim: access_token
              prefix: "Bearer "
{{- end }}

{{/*
Per-tier oauth2-proxy ExternalSecret. Pulls all OIDC + cookie config from
Key Vault under the talk-<env>-oauth2-proxy-<tier>-* prefix.

Usage: {{- include "talk.oauth2Proxy.externalSecret" (dict "root" $ "tier" $tier) }}
*/}}
{{- define "talk.oauth2Proxy.externalSecret" -}}
{{- $root := .root -}}
{{- $tier := .tier -}}
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: oauth2-proxy-{{ $tier }}-oidc
  labels:
    app.kubernetes.io/name: oauth2-proxy
    app.kubernetes.io/component: {{ $tier }}
    {{- include "talk.labels" $root | nindent 4 }}
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: talk-azure-key-vault
  target:
    name: oauth2-proxy-{{ $tier }}-oidc
    creationPolicy: Owner
  data:
    - secretKey: OAUTH2_PROXY_CLIENT_ID
      remoteRef:
        key: {{ include "talk.kvKey" (list $root (printf "oauth2-proxy-%s" $tier) "client-id") }}
    - secretKey: OAUTH2_PROXY_CLIENT_SECRET
      remoteRef:
        key: {{ include "talk.kvKey" (list $root (printf "oauth2-proxy-%s" $tier) "client-secret") }}
    - secretKey: OAUTH2_PROXY_COOKIE_SECRET
      remoteRef:
        key: {{ include "talk.kvKey" (list $root (printf "oauth2-proxy-%s" $tier) "cookie-secret") }}
    - secretKey: OAUTH2_PROXY_OIDC_ISSUER_URL
      remoteRef:
        key: {{ include "talk.kvKey" (list $root "zitadel" "issuer-url") }}
    - secretKey: OAUTH2_PROXY_COOKIE_DOMAIN
      remoteRef:
        key: {{ include "talk.kvKey" (list $root (printf "oauth2-proxy-%s" $tier) "cookie-domain") }}
    - secretKey: OAUTH2_PROXY_WHITELIST_DOMAIN
      remoteRef:
        key: {{ include "talk.kvKey" (list $root (printf "oauth2-proxy-%s" $tier) "whitelist-domain") }}
    - secretKey: OAUTH2_PROXY_COOKIE_SECURE
      remoteRef:
        key: {{ include "talk.kvKey" (list $root (printf "oauth2-proxy-%s" $tier) "cookie-secure") }}
    - secretKey: OAUTH2_PROXY_INSECURE_SKIP_ISSUER_VERIFICATION
      remoteRef:
        key: {{ include "talk.kvKey" (list $root (printf "oauth2-proxy-%s" $tier) "insecure-skip-issuer-verification") }}
{{- end }}

{{/*
Per-tier oauth2-proxy Deployment + Service. Uses --redirect-url derived from
the request Host so the same proxy can serve multiple subdomains in the
public tier (admin + agents) without rebuilding per host. Cookie name is
distinct per tier to keep sessions isolated.

Usage: {{- include "talk.oauth2Proxy.deployment" (dict "root" $ "tier" $tier "tierConfig" $tierConfig) }}
*/}}
{{- define "talk.oauth2Proxy.deployment" -}}
{{- $root := .root -}}
{{- $tier := .tier -}}
{{- $tierConfig := .tierConfig -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: oauth2-proxy-{{ $tier }}
  labels:
    app.kubernetes.io/name: oauth2-proxy
    app.kubernetes.io/component: {{ $tier }}
    {{- include "talk.labels" $root | nindent 4 }}
spec:
  {{- if not $root.Values.oauth2Proxy.autoscaling.enabled }}
  replicas: {{ $root.Values.oauth2Proxy.replicas }}
  {{- end }}
  selector:
    matchLabels:
      app.kubernetes.io/name: oauth2-proxy
      app.kubernetes.io/component: {{ $tier }}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: oauth2-proxy
        app.kubernetes.io/component: {{ $tier }}
      annotations:
        checksum/config: {{ printf "%s|%s" $tierConfig.cookieName (toYaml $tierConfig.upstreams) | sha256sum }}
    spec:
      {{- with $root.Values.oauth2Proxy.hostAliases }}
      # AKS hairpin workaround: pods can't dial back into the cluster's own
      # public LB IP, so resolve zitadel.<baseDomain> to the Envoy Gateway
      # data-plane Service ClusterIP. Auto-populated by `make post`.
      hostAliases:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      containers:
        - name: oauth2-proxy
          image: {{ $root.Values.oauth2Proxy.image.repository }}:{{ $root.Values.oauth2Proxy.image.tag }}
          imagePullPolicy: IfNotPresent
          resources:
            {{- toYaml $root.Values.oauth2Proxy.resources | nindent 12 }}
          args:
            - --alpha-config=/etc/oauth2-proxy/alpha-config.yaml
            - --proxy-prefix=/oauth2
            - --email-domain=*
            - --skip-provider-button=true
            - --reverse-proxy=true
            - --cookie-name={{ $tierConfig.cookieName }}
            - --cookie-secure=$(OAUTH2_PROXY_COOKIE_SECURE)
            - --cookie-secret=$(OAUTH2_PROXY_COOKIE_SECRET)
            - --cookie-samesite=lax
            - --cookie-domain=$(OAUTH2_PROXY_COOKIE_DOMAIN)
            - --whitelist-domain=$(OAUTH2_PROXY_WHITELIST_DOMAIN)
          ports:
            - name: http
              containerPort: 4180
          envFrom:
            - secretRef:
                name: oauth2-proxy-{{ $tier }}-oidc
          volumeMounts:
            - name: config
              mountPath: /etc/oauth2-proxy
              readOnly: true
          readinessProbe:
            httpGet:
              path: /ping
              port: http
            initialDelaySeconds: 10
          livenessProbe:
            httpGet:
              path: /ping
              port: http
            initialDelaySeconds: 60
      volumes:
        - name: config
          configMap:
            name: oauth2-proxy-{{ $tier }}-config
---
apiVersion: v1
kind: Service
metadata:
  name: oauth2-proxy-{{ $tier }}
  labels:
    app.kubernetes.io/name: oauth2-proxy
    app.kubernetes.io/component: {{ $tier }}
    {{- include "talk.labels" $root | nindent 4 }}
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: oauth2-proxy
    app.kubernetes.io/component: {{ $tier }}
  ports:
    - name: http
      port: 4180
      targetPort: http
{{- end }}
