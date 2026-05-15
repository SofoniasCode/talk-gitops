#!/usr/bin/env python3
"""Provision Talk management resources in Zitadel.

The script is intentionally dependency-free so it can run from a local shell,
CI, or a bootstrap container with only Python available.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


ROOT_DIR = Path(__file__).resolve().parents[1]
DEFAULT_ROLES = (
    ("organization.viewer", "Organization Viewer", "organization"),
    ("organization.admin", "Organization Admin", "organization"),
    ("organization.owner", "Organization Owner", "organization"),
    ("citadel.viewer", "Citadel Viewer", "citadel"),
    ("citadel.operator", "Citadel Operator", "citadel"),
    ("citadel.admin", "Citadel Admin", "citadel"),
)


class ZitadelError(RuntimeError):
    pass


class ZitadelClient:
    def __init__(self, base_url: str, token: str, host_header: str | None = None) -> None:
        self.base_url = base_url.rstrip("/")
        self.token = token
        self.host_header = host_header

    def request(self, method: str, path: str, payload: dict[str, Any] | None = None) -> dict[str, Any]:
        url = f"{self.base_url}{path}"
        body = None if payload is None else json.dumps(payload).encode("utf-8")
        request = urllib.request.Request(url, data=body, method=method)
        request.add_header("Authorization", f"Bearer {self.token}")
        request.add_header("Content-Type", "application/json")
        request.add_header("Accept", "application/json")
        request.add_header("Connect-Protocol-Version", "1")
        if self.host_header:
            request.add_header("Host", self.host_header)

        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                content = response.read().decode("utf-8")
        except urllib.error.HTTPError as exc:
            details = exc.read().decode("utf-8", errors="replace")
            raise ZitadelError(f"{method} {path} failed with {exc.code}: {details}") from exc
        except urllib.error.URLError as exc:
            raise ZitadelError(f"{method} {path} failed: {exc}") from exc

        return json.loads(content) if content else {}


def env(name: str, default: str) -> str:
    return os.environ.get(name, default)


def env_bool(name: str, default: bool) -> bool:
    value = os.environ.get(name)
    if value is None:
        return default
    return value.lower() in {"1", "true", "yes", "on"}


def csv_env(name: str, default: str) -> list[str]:
    return [part.strip() for part in env(name, default).split(",") if part.strip()]


def run(command: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, check=False, capture_output=True, text=True)


def discover_local_admin_pat(namespace: str) -> str | None:
    if token := os.environ.get("TALK_ZITADEL_ADMIN_PAT"):
        return token

    command = [
        "kubectl",
        "-n",
        namespace,
        "exec",
        "deploy/zitadel",
        "-c",
        "login",
        "--",
        "sh",
        "-c",
        "cat /zitadel/bootstrap/admin-service.pat 2>/dev/null",
    ]
    result = run(command)
    token = result.stdout.strip()
    return token or None


def read_vault_secret(path: str) -> dict[str, Any]:
    vault_addr = env("VAULT_ADDR", "http://127.0.0.1:8200").rstrip("/")
    vault_token = env("VAULT_TOKEN", "root")
    request = urllib.request.Request(f"{vault_addr}/v1/secret/data/{path}", method="GET")
    request.add_header("X-Vault-Token", vault_token)
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            payload = json.loads(response.read().decode("utf-8"))
            return payload.get("data", {}).get("data", {})
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            return {}
        raise


def write_vault_secret(path: str, data: dict[str, str]) -> None:
    vault_addr = env("VAULT_ADDR", "http://127.0.0.1:8200").rstrip("/")
    vault_token = env("VAULT_TOKEN", "root")
    request = urllib.request.Request(
        f"{vault_addr}/v1/secret/data/{path}",
        data=json.dumps({"data": data}).encode("utf-8"),
        method="POST",
    )
    request.add_header("X-Vault-Token", vault_token)
    request.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(request, timeout=10):
        return


def sync_local_kubernetes(namespace: str) -> None:
    commands = [
        [
            "kubectl",
            "-n",
            namespace,
            "annotate",
            "externalsecret",
            "oauth2-proxy-oidc",
            f"force-sync={os.getpid()}",
            "--overwrite",
        ],
        [
            "kubectl",
            "-n",
            namespace,
            "annotate",
            "externalsecret",
            "console-api-zitadel-admin",
            f"force-sync={os.getpid()}",
            "--overwrite",
        ],
        ["kubectl", "-n", namespace, "rollout", "restart", "deploy/oauth2-proxy"],
        ["kubectl", "-n", namespace, "rollout", "status", "deploy/oauth2-proxy", "--timeout=180s"],
        ["kubectl", "-n", namespace, "rollout", "restart", "deploy/console-api"],
        ["kubectl", "-n", namespace, "rollout", "status", "deploy/console-api", "--timeout=180s"],
    ]
    for command in commands:
        result = run(command)
        if result.returncode != 0:
            raise RuntimeError(result.stderr.strip() or result.stdout.strip())


def select_organization(client: ZitadelClient, organization_id: str | None, organization_name: str) -> str:
    if organization_id:
        return organization_id

    response = client.request(
        "POST",
        "/v2/organizations/_search",
        {"pagination": {"limit": 100, "asc": True}},
    )
    organizations = response.get("result", [])
    matches = [org for org in organizations if org.get("name") == organization_name]
    if len(matches) == 1:
        return matches[0]["id"]
    if len(organizations) == 1:
        return organizations[0]["id"]

    names = ", ".join(sorted(org.get("name", "<unnamed>") for org in organizations)) or "<none>"
    raise ZitadelError(
        "Set TALK_ZITADEL_ORGANIZATION_ID; unable to choose a unique organization "
        f"from: {names}"
    )


def ensure_project(
    client: ZitadelClient,
    organization_id: str,
    project_name: str,
    dry_run: bool,
) -> str:
    response = client.request(
        "POST",
        "/zitadel.project.v2.ProjectService/ListProjects",
        {
            "pagination": {"limit": 100, "asc": True},
            "sortingColumn": "PROJECT_FIELD_NAME_NAME",
            "filters": [{"organizationIdFilter": {"organizationId": organization_id}}],
        },
    )
    for project in response.get("projects", []):
        if project.get("name") == project_name:
            project_id = project["projectId"]
            ensure_project_role_assertion(client, project_id, dry_run)
            print(f"found project: {project_name} ({project_id})")
            return project_id

    if dry_run:
        print(f"would create project: {project_name}")
        return "<dry-run-project-id>"

    response = client.request(
        "POST",
        "/zitadel.project.v2.ProjectService/CreateProject",
        {
            "organizationId": organization_id,
            "name": project_name,
            "projectRoleAssertion": True,
            "authorizationRequired": False,
            "projectAccessRequired": False,
        },
    )
    project_id = response["projectId"]
    print(f"created project: {project_name} ({project_id})")
    return project_id


def ensure_project_role_assertion(client: ZitadelClient, project_id: str, dry_run: bool) -> None:
    if dry_run:
        print(f"would enable project role assertion: {project_id}")
        return
    try:
        client.request(
            "POST",
            "/zitadel.project.v2.ProjectService/UpdateProject",
            {
                "projectId": project_id,
                "projectRoleAssertion": True,
            },
        )
        print(f"enabled project role assertion: {project_id}")
    except ZitadelError as exc:
        if "no changes" not in str(exc).lower():
            raise
        print(f"project role assertion already enabled: {project_id}")


def ensure_roles(client: ZitadelClient, project_id: str, dry_run: bool) -> None:
    response = client.request(
        "POST",
        "/zitadel.project.v2.ProjectService/ListProjectRoles",
        {"projectId": project_id},
    )
    existing = {role.get("key") for role in response.get("projectRoles", [])}

    for role_key, display_name, group in DEFAULT_ROLES:
        if role_key in existing:
            print(f"found role: {role_key}")
            continue
        if dry_run:
            print(f"would create role: {role_key}")
            continue
        client.request(
            "POST",
            "/zitadel.project.v2.ProjectService/AddProjectRole",
            {
                "projectId": project_id,
                "roleKey": role_key,
                "displayName": display_name,
                "group": group,
            },
        )
        print(f"created role: {role_key}")


def ensure_application(
    client: ZitadelClient,
    project_id: str,
    app_name: str,
    redirect_uris: list[str],
    post_logout_uris: list[str],
    development_mode: bool,
    dry_run: bool,
) -> tuple[str, str | None]:
    response = client.request(
        "POST",
        "/zitadel.application.v2.ApplicationService/ListApplications",
        {
            "pagination": {"limit": 100, "asc": True},
            "sortingColumn": "APPLICATION_SORTING_APP_NAME",
            "filters": [{"projectIdFilter": {"projectId": project_id}}],
        },
    )
    for app in response.get("applications", []):
        if app.get("name") == app_name:
            config = app.get("oidcConfig") or app.get("oidcConfiguration") or {}
            client_id = config.get("clientId")
            if not client_id:
                raise ZitadelError(f"existing application {app_name!r} has no OIDC clientId")
            ensure_application_assertions(client, project_id, app["applicationId"], development_mode, dry_run)
            if env_bool("TALK_ZITADEL_REGENERATE_CLIENT_SECRET", False):
                response = client.request(
                    "POST",
                    "/zitadel.application.v2.ApplicationService/GenerateClientSecret",
                    {"projectId": project_id, "applicationId": app["applicationId"]},
                )
                print(f"regenerated OIDC client secret: {app_name} ({client_id})")
                return client_id, response["clientSecret"]
            print(f"found OIDC application: {app_name} ({client_id})")
            return client_id, None

    if dry_run:
        print(f"would create OIDC application: {app_name}")
        return "<dry-run-client-id>", None

    response = client.request(
        "POST",
        "/zitadel.application.v2.ApplicationService/CreateApplication",
        {
            "projectId": project_id,
            "name": app_name,
            "oidcConfiguration": {
                "redirectUris": redirect_uris,
                "responseTypes": ["OIDC_RESPONSE_TYPE_CODE"],
                "grantTypes": ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"],
                "applicationType": "OIDC_APPLICATION_TYPE_WEB",
                "authMethodType": "OIDC_AUTH_METHOD_TYPE_BASIC",
                "postLogoutRedirectUris": post_logout_uris,
                "version": "OIDC_VERSION_1_0",
                "developmentMode": development_mode,
                "accessTokenType": "OIDC_TOKEN_TYPE_BEARER",
                "idTokenUserinfoAssertion": True,
            },
        },
    )
    config = response.get("oidcConfiguration", {})
    client_id = config["clientId"]
    client_secret = config["clientSecret"]
    print(f"created OIDC application: {app_name} ({client_id})")
    return client_id, client_secret


def ensure_application_assertions(
    client: ZitadelClient,
    project_id: str,
    application_id: str,
    development_mode: bool,
    dry_run: bool,
) -> None:
    if dry_run:
        print(f"would enable OIDC application role assertions: {application_id}")
        return
    try:
        client.request(
            "POST",
            "/zitadel.application.v2.ApplicationService/UpdateApplication",
            {
                "projectId": project_id,
                "applicationId": application_id,
                "oidcConfiguration": {
                    "developmentMode": development_mode,
                    "accessTokenType": "OIDC_TOKEN_TYPE_BEARER",
                    "accessTokenRoleAssertion": True,
                    "idTokenRoleAssertion": True,
                    "idTokenUserinfoAssertion": True,
                },
            },
        )
        print(f"enabled OIDC application role assertions: {application_id}")
    except ZitadelError as exc:
        if "no changes" not in str(exc).lower():
            raise
        print(f"OIDC application role assertions already enabled: {application_id}")


def ensure_action(client: ZitadelClient, action_name: str, script: str, dry_run: bool) -> str:
    response = client.request("POST", "/management/v1/actions/_search", {})
    for action in response.get("result", []):
        if action.get("name") != action_name:
            continue
        action_id = action["id"]
        if action.get("script") != script:
            if dry_run:
                print(f"would update action: {action_name} ({action_id})")
            else:
                client.request("PUT", f"/management/v1/actions/{action_id}", {"name": action_name, "script": script})
                print(f"updated action: {action_name} ({action_id})")
        else:
            print(f"found action: {action_name} ({action_id})")
        return action_id

    if dry_run:
        print(f"would create action: {action_name}")
        return "<dry-run-action-id>"

    response = client.request("POST", "/management/v1/actions", {"name": action_name, "script": script})
    action_id = response["id"]
    print(f"created action: {action_name} ({action_id})")
    return action_id


def ensure_action_triggers(client: ZitadelClient, action_id: str, dry_run: bool) -> None:
    if dry_run:
        print("would attach action to complement token triggers 4 and 5")
        return

    try:
        flow = client.request("GET", "/management/v1/flows/2").get("flow", {})
    except ZitadelError:
        flow = {}

    existing_by_trigger: dict[str, list[str]] = {}
    for trigger in flow.get("triggerActions", []):
        trigger_id = str(trigger.get("triggerType", {}).get("id"))
        existing_by_trigger[trigger_id] = [action["id"] for action in trigger.get("actions", [])]

    for trigger_id in ("4", "5"):
        action_ids = existing_by_trigger.get(trigger_id, [])
        if action_id not in action_ids:
            action_ids.append(action_id)
        try:
            client.request("POST", f"/management/v1/flows/2/trigger/{trigger_id}", {"actionIds": action_ids})
        except ZitadelError as exc:
            if "No Changes" not in str(exc):
                raise
        print(f"attached action to complement token trigger {trigger_id}")


def write_local_vault(
    client_id: str,
    client_secret: str | None,
    redirect_uris: list[str],
    post_logout_uris: list[str],
    project_id: str,
    admin_token: str,
) -> None:
    path = "talk/local/oauth2-proxy/oidc"
    existing = read_vault_secret(path)
    secret = client_secret or os.environ.get("TALK_ZITADEL_CLIENT_SECRET") or existing.get("client-secret")
    if not secret:
        raise RuntimeError(
            "Zitadel does not reveal an existing app client secret. Set TALK_ZITADEL_CLIENT_SECRET "
            "or recreate the app to capture a new secret."
        )

    data = {
        "issuer-url": env("TALK_OAUTH2_PROXY_ISSUER_URL", env("TALK_ZITADEL_ISSUER", "http://zitadel.localhost")),
        "client-id": client_id,
        "client-secret": secret,
        "cookie-secret": env("TALK_OAUTH2_PROXY_COOKIE_SECRET", existing.get("cookie-secret", "LocalDevOauth2ProxyCookieSecretX")),
        "redirect-url": env("TALK_OAUTH2_PROXY_REDIRECT_URL", redirect_uris[0]),
        "cookie-domain": env("TALK_OAUTH2_PROXY_COOKIE_DOMAIN", existing.get("cookie-domain", "talk.localhost")),
        "whitelist-domain": env("TALK_OAUTH2_PROXY_WHITELIST_DOMAIN", existing.get("whitelist-domain", ".localhost")),
        "cookie-secure": env("TALK_OAUTH2_PROXY_COOKIE_SECURE", existing.get("cookie-secure", "false")),
        "insecure-skip-issuer-verification": env(
            "TALK_OAUTH2_PROXY_INSECURE_SKIP_ISSUER_VERIFICATION",
            existing.get("insecure-skip-issuer-verification", "false"),
        ),
    }
    if post_logout_uris:
        data["post-logout-url"] = post_logout_uris[0]
    write_vault_secret(path, data)
    print(f"wrote local Vault secret: secret/{path}")

    console_api_path = "talk/local/console-api/zitadel-admin"
    console_api_data = {
        "base-url": env("TALK_CONSOLE_API_ZITADEL_BASE_URL", env("TALK_ZITADEL_ISSUER", "http://zitadel.localhost")),
        "admin-token": env("TALK_CONSOLE_API_ZITADEL_ADMIN_TOKEN", admin_token),
        "api-host-header": env("TALK_CONSOLE_API_ZITADEL_API_HOST_HEADER", ""),
        "project-id": env("TALK_CONSOLE_API_ZITADEL_PROJECT_ID", project_id),
    }
    write_vault_secret(console_api_path, console_api_data)
    print(f"wrote local Vault secret: secret/{console_api_path}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write-local-vault", action="store_true", help="write oauth2-proxy OIDC values to local Vault")
    parser.add_argument("--sync-local-k8s", action="store_true", help="sync ExternalSecret and restart local oauth2-proxy")
    parser.add_argument("--dry-run", action="store_true", help="print intended changes without writing to Zitadel")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    namespace = env("TALK_K8S_NAMESPACE", "talk-local")
    token = discover_local_admin_pat(namespace)
    if not token:
        print(
            "Missing Zitadel admin PAT. Set TALK_ZITADEL_ADMIN_PAT or use a clean local "
            "Zitadel boot that creates /zitadel/bootstrap/admin-service.pat.",
            file=sys.stderr,
        )
        return 2

    client = ZitadelClient(
        env("TALK_ZITADEL_API_URL", env("TALK_ZITADEL_ISSUER", "http://zitadel.localhost")),
        token,
        os.environ.get("TALK_ZITADEL_API_HOST_HEADER"),
    )
    organization_id = select_organization(
        client,
        os.environ.get("TALK_ZITADEL_ORGANIZATION_ID"),
        env("TALK_ZITADEL_ORGANIZATION_NAME", "ZITADEL"),
    )
    print(f"using organization: {organization_id}")

    project_id = ensure_project(
        client,
        organization_id,
        env("TALK_ZITADEL_PROJECT_NAME", "Talk Management"),
        args.dry_run,
    )
    if project_id != "<dry-run-project-id>":
        ensure_roles(client, project_id, args.dry_run)

    redirect_uris = csv_env("TALK_ZITADEL_REDIRECT_URIS", "http://talk.localhost/oauth2/callback")
    post_logout_uris = csv_env("TALK_ZITADEL_POST_LOGOUT_URIS", "http://talk.localhost/")
    client_id, client_secret = ensure_application(
        client,
        project_id,
        env("TALK_ZITADEL_OAUTH2_PROXY_APP_NAME", "oauth2-proxy-local"),
        redirect_uris,
        post_logout_uris,
        env_bool("TALK_ZITADEL_OIDC_DEVELOPMENT_MODE", True),
        args.dry_run,
    )

    action_script = Path(env("TALK_ZITADEL_ACTION_SCRIPT", str(ROOT_DIR / "zitadel/actions/talk_roles_claim.js"))).read_text()
    action_id = ensure_action(client, env("TALK_ZITADEL_ACTION_NAME", "talk_roles_claim"), action_script, args.dry_run)
    ensure_action_triggers(client, action_id, args.dry_run)

    if args.write_local_vault and not args.dry_run:
        write_local_vault(client_id, client_secret, redirect_uris, post_logout_uris, project_id, token)

    if args.sync_local_k8s and not args.dry_run:
        sync_local_kubernetes(namespace)

    print("Zitadel management provisioning complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
