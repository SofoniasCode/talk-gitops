/**
 * Emits Talk identity claims for oauth2-proxy to forward as X-Talk-* headers.
 *
 * Flow: Complement token
 * Triggers: Pre Userinfo creation, Pre access token creation
 *
 * @param ctx
 * @param api
 */
function talk_roles_claim(ctx, api) {
  const grants = (ctx.v1.user.grants && ctx.v1.user.grants.grants) || [];
  if (grants.length === 0) {
    return;
  }

  const roles = [];
  const organizationIds = [];
  grants.forEach((grant) => {
    grant.roles.forEach((role) => {
      roles.push(role);
    });
    const organizationId = grant.grantedOrgId || grant.orgId || grant.userResourceOwner;
    if (organizationId) {
      organizationIds.push(organizationId);
    }
  });

  const uniqueRoles = [...new Set(roles)].sort();
  if (uniqueRoles.length > 0) {
    api.v1.claims.setClaim("urn:talk:roles", uniqueRoles);
    api.v1.claims.setClaim("groups", uniqueRoles);
  }

  const uniqueOrganizationIds = [...new Set(organizationIds)].sort();
  if (uniqueOrganizationIds.length > 0) {
    api.v1.claims.setClaim("urn:talk:organization_id", uniqueOrganizationIds[0]);
  }
}
