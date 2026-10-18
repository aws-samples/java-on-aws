#!/bin/bash
# Talk to the deployed AI agent on AgentCore Runtime as a Cognito user, for the terminal tests.
#
#   ask-runtime.sh ask PROMPT [SESSION]   sign in, send PROMPT, print the streamed answer as text
#   ask-runtime.sh oauth SESSION_URI      hand a consent session from AgentCore Identity to the AI agent (as callback.html)
#   ask-runtime.sh stop SESSION           stop the runtime session (the next request starts a new microVM)
#   ask-runtime.sh token                  print an access token
#
# USER_NAME selects the Cognito user (default alice; admin, alice, bob exist), the password is IDE_PASSWORD.
# SESSION is the X-Amzn-Bedrock-AgentCore-Runtime-Session-Id (at least 33 characters). The default,
# workshop-terminal-session-<user>-v<runtime version>, keeps one conversation per runtime version: a session's microVM
# runs the version it started with, so after an update the next request starts a new microVM. Reads ~/environment/.envrc.
# ATTACH_FILE=PATH sends the file with the prompt (fileName, fileBase64), like the attachment button of the UI.
set -euo pipefail
[ -f ~/environment/.envrc ] && source ~/environment/.envrc
USER_NAME="${USER_NAME:-alice}"
default_session() {
  echo "workshop-terminal-session-${USER_NAME}-v$(aws bedrock-agentcore-control get-agent-runtime \
    --agent-runtime-id "${AIAGENT_RUNTIME_ID}" --region "${AWS_REGION}" --no-cli-pager \
    --query agentRuntimeVersion --output text)"
}

token() {  # one access token per user for 50 minutes: AgentCore Identity binds a consent to the exact token
  local cache="/tmp/ask-runtime-token-${USER_NAME}"
  if [ -z "$(find "${cache}" -mmin -50 2>/dev/null)" ]; then
    aws cognito-idp initiate-auth --client-id "${AIAGENT_CLIENT_ID}" --auth-flow USER_PASSWORD_AUTH \
      --auth-parameters "USERNAME=${USER_NAME},PASSWORD=${IDE_PASSWORD}" --region "${AWS_REGION}" \
      --no-cli-pager --query 'AuthenticationResult.AccessToken' --output text > "${cache}"
  fi
  cat "${cache}"
}

request_body() {  # the JSON body of /invocations: prompt, and the file of ATTACH_FILE
  if [ -n "${ATTACH_FILE:-}" ]; then
    jq -n --arg prompt "$1" --arg name "$(basename "${ATTACH_FILE}")" --rawfile data <(base64 -w0 "${ATTACH_FILE}" 2>/dev/null || base64 -i "${ATTACH_FILE}") \
      '{prompt: $prompt, fileName: $name, fileBase64: $data}'
  else
    jq -n --arg prompt "$1" '{prompt: $prompt}'
  fi
}

case "${1:-}" in
  ask)
    prompt="${2:?ask-runtime.sh ask PROMPT [SESSION]}"
    curl -sSN --fail-with-body --max-time 300 -X POST "${AIAGENT_ENDPOINT}" \
      -H "Content-Type: application/json" \
      -H "Accept: text/event-stream" \
      -H "Authorization: Bearer $(token)" \
      -H "X-Amzn-Bedrock-AgentCore-Runtime-Session-Id: ${3:-$(default_session)}" \
      -d @<(request_body "${prompt}") \
    | python3 "$(dirname "$0")/sse_text.py"
    ;;
  oauth)
    curl -sSN --fail-with-body --max-time 60 -X POST "${AIAGENT_ENDPOINT}" \
      -H "Content-Type: application/json" \
      -H "Accept: text/event-stream" \
      -H "Authorization: Bearer $(token)" \
      -H "X-Amzn-Bedrock-AgentCore-Runtime-Session-Id: $(default_session)" \
      -d "$(jq -n --arg session "${2:?ask-runtime.sh oauth SESSION_URI}" '{oauthSession: $session}')" \
    | python3 "$(dirname "$0")/sse_text.py"
    ;;
  stop)
    session="${2:?ask-runtime.sh stop SESSION}"
    # A runtime with a JWT authorizer accepts the stop call with the user's bearer token (SigV4 is rejected)
    curl -sS --fail-with-body -X POST "${AIAGENT_ENDPOINT%/invocations*}/stopruntimesession?qualifier=DEFAULT" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $(token)" \
      -H "X-Amzn-Bedrock-AgentCore-Runtime-Session-Id: ${session}" \
      -d "$(jq -n --arg session "${session}" '{runtimeSessionId: $session}')" > /dev/null
    echo "stopped session ${session}"
    ;;
  token)
    token
    ;;
  *)
    sed -n '2,10p' "$0"; exit 2
    ;;
esac
