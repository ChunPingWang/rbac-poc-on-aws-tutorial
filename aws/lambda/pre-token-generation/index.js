// =====================================================================
// Cognito Pre Token Generation trigger (event version V2_0)
//
// Keycloak protocol mappers → Cognito: Cognito access tokens do NOT carry
// custom attributes by default. This trigger copies the user's
// custom:tenant_id (plus profile claims used by user-service) into the
// ACCESS token so the Spring Boot resource servers keep working unchanged:
//   tenant_id, email, given_name, family_name
// Groups are already present as "cognito:groups".
// (The same code is embedded inline in 30-identity.yaml.)
// =====================================================================
exports.handler = async (event) => {
  const attrs = event.request?.userAttributes ?? {};
  const access = {};
  const id = {};

  if (attrs['custom:tenant_id']) {
    access.tenant_id = attrs['custom:tenant_id'];
    id.tenant_id = attrs['custom:tenant_id'];
  }
  for (const k of ['email', 'given_name', 'family_name']) {
    if (attrs[k]) access[k] = attrs[k];
  }

  event.response = {
    claimsAndScopeOverrideDetails: {
      accessTokenGeneration: { claimsToAddOrOverride: access },
      idTokenGeneration: { claimsToAddOrOverride: id },
    },
  };
  return event;
};
