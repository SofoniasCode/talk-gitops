# Envoy Gateway Routes

The browser-facing contract is path based:

- `/console/*` routes to the staff Citadel console frontend.
- `/admin/*` routes to the customer admin frontend.
- `/console-api/*` routes to the internal `console-api` service.
- `/identity-sync/*` routes to `identity-sync` for external webhook delivery and rewrites the prefix away.
- `/oauth2/*` is owned by `oauth2-proxy` for sign-in callbacks and session handling.

The frontend apps call `console-api` through `/console-api`, so the same public path works in
local Vite development and behind Envoy Gateway in deployed environments.

Envoy Gateway must be installed before applying these manifests. The base defines a
`GatewayClass` named `talk-envoy` with controller name
`gateway.envoyproxy.io/gatewayclass-controller`.

## Identity Headers

`console-api` expects the gateway-auth layer to validate the caller and forward trusted identity
headers. Public callers must not be allowed to provide these headers directly.

- `X-Talk-Subject-Id`: stable user or service subject id.
- `X-Talk-Organization-Id`: organization context for organization-scoped access.
- `X-Talk-Roles`: comma-separated role ids such as `citadel.viewer` or `organization.viewer`.

The browser and `console-api` routes go through `oauth2-proxy`. Public callers do not reach those
upstreams directly; `oauth2-proxy` performs the Zitadel OIDC flow, strips/replaces the trusted
headers, and injects `X-Talk-*` from validated session claims.

The Zitadel webhook route intentionally does not use browser OIDC. `identity-sync` validates
webhooks with `ZITADEL-Signature` and `ZITADEL_WEBHOOK_SECRET`.

## Zitadel Claim Mapping

`oauth2-proxy` uses alpha header injection and maps these claims:

- `sub` through the session `user` claim -> `X-Talk-Subject-Id`
- `urn:talk:organization_id` -> `X-Talk-Organization-Id`
- `urn:talk:roles` -> `X-Talk-Roles`

The environment overlays create `oauth2-proxy-oidc` through External Secrets Operator. If Zitadel
emits roles under another claim, update `oauth2-proxy-config` so `X-Talk-Roles` receives the role
ids expected by `authz`, for example
`citadel.viewer`, `citadel.operator`, `organization.viewer`, or `organization.owner`.

Official docs used for this contract:

- Envoy Gateway Helm install: https://gateway.envoyproxy.io/latest/install/install-helm/
- oauth2-proxy alpha configuration: https://github.com/oauth2-proxy/oauth2-proxy/blob/v7.15.2/docs/docs/configuration/alpha_config.md
- ZITADEL oauth2-proxy integration: https://zitadel.com/docs/examples/identity-proxy/oauth2-proxy
- ZITADEL token actions: https://zitadel.com/docs/apis/actions/complement-token
- ZITADEL role claims: https://zitadel.com/docs/guides/integrate/retrieve-user-roles
- ZITADEL reserved scopes: https://zitadel.com/docs/apis/openidoauth/scopes
