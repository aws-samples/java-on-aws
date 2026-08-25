#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_suite-lib.sh
source "${SCRIPT_DIR}/_suite-lib.sh"

ROTATE=false
if [[ "${1:-}" == "--rotate-passwords" ]]; then ROTATE=true; shift; fi
(($# == 0)) || die "Usage: 05-security.sh [--rotate-passwords]"
print_prerequisites "Cognito administrative access and IDE_PASSWORD for missing users"
init_context

POOL_NAME="aiagent-user-pool"
CLIENT_NAME="aiagent-client"
USER_POOL_ID=$(aws_cli cognito-idp list-user-pools --max-results 60 \
  --query "UserPools[?Name=='${POOL_NAME}'].Id | [0]" --output text)
if is_none "${USER_POOL_ID}"; then
  USER_POOL_ID=$(aws_cli cognito-idp create-user-pool --pool-name "${POOL_NAME}" \
    --policies '{"PasswordPolicy":{"MinimumLength":8,"RequireUppercase":true,"RequireLowercase":true,"RequireNumbers":true,"RequireSymbols":false}}' \
    --auto-verified-attributes email --username-configuration '{"CaseSensitive":false}' \
    --user-pool-tags "suite=${SUITE_OWNER}" --query 'UserPool.Id' --output text)
  state_set COGNITO_POOL_CREATED true
else
  [[ -n "${COGNITO_POOL_CREATED:-}" ]] || state_set COGNITO_POOL_CREATED false
  pool=$(aws_cli cognito-idp describe-user-pool --user-pool-id "${USER_POOL_ID}" --query UserPool)
  compatible=$(jq -r '(.Policies.PasswordPolicy.MinimumLength >= 8) and .Policies.PasswordPolicy.RequireUppercase and .Policies.PasswordPolicy.RequireLowercase and .Policies.PasswordPolicy.RequireNumbers' <<<"${pool}")
  [[ "${compatible}" == true ]] || die "Existing ${POOL_NAME} has an incompatible password policy; refusing to replace unrelated settings"
fi
state_set COGNITO_USER_POOL_ID "${USER_POOL_ID}"

CLIENT_ID=$(aws_cli cognito-idp list-user-pool-clients --user-pool-id "${USER_POOL_ID}" \
  --query "UserPoolClients[?ClientName=='${CLIENT_NAME}'].ClientId | [0]" --output text)
DESIRED_FLOWS='["ALLOW_USER_PASSWORD_AUTH","ALLOW_USER_SRP_AUTH","ALLOW_REFRESH_TOKEN_AUTH"]'
if is_none "${CLIENT_ID}"; then
  CLIENT_ID=$(aws_cli cognito-idp create-user-pool-client --user-pool-id "${USER_POOL_ID}" \
    --client-name "${CLIENT_NAME}" --no-generate-secret \
    --explicit-auth-flows ALLOW_USER_PASSWORD_AUTH ALLOW_USER_SRP_AUTH ALLOW_REFRESH_TOKEN_AUTH \
    --query 'UserPoolClient.ClientId' --output text)
  state_set COGNITO_CLIENT_CREATED true
else
  [[ -n "${COGNITO_CLIENT_CREATED:-}" ]] || state_set COGNITO_CLIENT_CREATED false
  current_client=$(aws_cli cognito-idp describe-user-pool-client --user-pool-id "${USER_POOL_ID}" \
    --client-id "${CLIENT_ID}" --query UserPoolClient)
  [[ "$(jq -r 'has("ClientSecret")' <<<"${current_client}")" != true ]] || \
    die "Existing ${CLIENT_NAME} has a client secret; refusing to persist or replace secret-bearing client configuration"
  current_input=$(jq -c --arg pool "${USER_POOL_ID}" '{UserPoolId:$pool,ClientId,ClientName,RefreshTokenValidity,AccessTokenValidity,IdTokenValidity,TokenValidityUnits,ReadAttributes,WriteAttributes,ExplicitAuthFlows,SupportedIdentityProviders,CallbackURLs,LogoutURLs,DefaultRedirectURI,AllowedOAuthFlows,AllowedOAuthScopes,AllowedOAuthFlowsUserPoolClient,AnalyticsConfiguration,PreventUserExistenceErrors,EnableTokenRevocation,EnablePropagateAdditionalUserContextData,AuthSessionValidity,RefreshTokenRotation} | with_entries(select(.value != null))' <<<"${current_client}")
  current_flows=$(jq -c '.ExplicitAuthFlows // [] | sort' <<<"${current_input}")
  if [[ "${current_flows}" != "$(jq -c 'sort' <<<"${DESIRED_FLOWS}")" ]]; then
    [[ -n "${COGNITO_CLIENT_ORIGINAL_CONFIG_B64:-}" ]] || state_set COGNITO_CLIENT_ORIGINAL_CONFIG_B64 "$(encode_b64 "${current_input}")"
    desired_input=$(jq -c --argjson flows "${DESIRED_FLOWS}" '.ExplicitAuthFlows=$flows' <<<"${current_input}")
    aws_cli cognito-idp update-user-pool-client --cli-input-json "${desired_input}" >/dev/null
  fi
fi
state_set COGNITO_CLIENT_ID "${CLIENT_ID}"
ISSUER_URI="https://cognito-idp.${AWS_REGION}.amazonaws.com/${USER_POOL_ID}"
state_set COGNITO_ISSUER_URI "${ISSUER_URI}"

created_users="${COGNITO_CREATED_USERS:-}"
append_created_user() {
  local user="$1"
  case ",${created_users}," in
    *",${user},"*) ;;
    *) created_users="${created_users:+${created_users},}${user}" ;;
  esac
}
for user in admin alice bob; do
  if aws_cli cognito-idp admin-get-user --user-pool-id "${USER_POOL_ID}" --username "${user}" >/dev/null 2>&1; then
    if [[ "${ROTATE}" == true ]]; then
      [[ -n "${IDE_PASSWORD:-}" ]] || die "IDE_PASSWORD is required with --rotate-passwords"
      aws_cli cognito-idp admin-set-user-password --user-pool-id "${USER_POOL_ID}" --username "${user}" \
        --password "${IDE_PASSWORD}" --permanent >/dev/null
    fi
  else
    [[ -n "${IDE_PASSWORD:-}" ]] || die "IDE_PASSWORD is required to create missing Cognito user ${user}"
    aws_cli cognito-idp admin-create-user --user-pool-id "${USER_POOL_ID}" --username "${user}" \
      --temporary-password "${IDE_PASSWORD}" --message-action SUPPRESS >/dev/null
    aws_cli cognito-idp admin-set-user-password --user-pool-id "${USER_POOL_ID}" --username "${user}" \
      --password "${IDE_PASSWORD}" --permanent >/dev/null
    append_created_user "${user}"
  fi
done
state_set COGNITO_CREATED_USERS "${created_users}"

mkdir -p "${AIAGENT_DIR}/src/main/resources/static"
cat > "${AIAGENT_DIR}/src/main/resources/static/config.json" <<EOF
{
  "userPoolId": "${USER_POOL_ID}",
  "clientId": "${CLIENT_ID}",
  "region": "${AWS_REGION}",
  "apiEndpoint": "invocations"
}
EOF
log "Cognito pool, public client, and users reconciled. Existing passwords were not changed unless --rotate-passwords was supplied."
