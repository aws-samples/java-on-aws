#!/bin/bash
# Talk to the deployed AI agent on AgentCore Runtime as a Cognito user, for the terminal tests.
#
#   ask-runtime.sh ask PROMPT [SESSION]   sign in, send PROMPT, print the streamed answer as text
#   ask-runtime.sh oauth SESSION_URI      hand a consent session from AgentCore Identity to the AI agent (as callback.html)
#   ask-runtime.sh stop [SESSION]         stop the runtime session (the next request starts a new microVM on the latest version)
#   ask-runtime.sh token                  print an access token
#
# USER_NAME selects the Cognito user (default alice; admin, alice, bob exist), the password is IDE_PASSWORD.
# SESSION is the X-Amzn-Bedrock-AgentCore-Runtime-Session-Id (at least 33 characters). The default is one conversation per user,
# workshop-conversation-of-user-<user> padded with "-" to 33 characters, the same ID as the chat UI (ui/auth.js). A session's microVM
# runs the version it started with: after an update, `stop` ends it, and the next request continues the conversation on the new
# version. Reads ~/environment/.envrc.
# ATTACH_FILE=PATH sends the file with the prompt (fileName, fileBase64), like the attachment button of the UI.
set -euo pipefail
[ -f ~/environment/.envrc ] && source ~/environment/.envrc
USER_NAME="${USER_NAME:-alice}"
default_session() {
  local id="workshop-conversation-of-user-${USER_NAME}"
  while [ ${#id} -lt 33 ]; do id="${id}-"; done
  echo "${id}"
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
    session="${2:-$(default_session)}"
    # A runtime with a JWT authorizer accepts the stop call with the user's bearer token (SigV4 is rejected)
    for attempt in 1 2 3 4 5; do   # 409: the session is starting or stopping, retry
      status=$(curl -sS -o /tmp/ask-runtime-stop.out -w '%{http_code}' -X POST "${AIAGENT_ENDPOINT%/invocations*}/stopruntimesession?qualifier=DEFAULT" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $(token)" \
        -H "X-Amzn-Bedrock-AgentCore-Runtime-Session-Id: ${session}" \
        -d "$(jq -n --arg session "${session}" '{runtimeSessionId: $session}')")
      [ "${status}" = "409" ] || break
      sleep $((attempt * 3))
    done
    if [[ "${status}" == 2* ]]; then
      echo "stopped session ${session}"
    elif [ "${status}" = "404" ]; then
      echo "no running session ${session}"   # the user has not called the runtime since the last stop or update
    else
      cat /tmp/ask-runtime-stop.out; echo; exit 1
    fi
    ;;
  token)
    token
    ;;
  *)
    sed -n '2,10p' "$0"; exit 2
    ;;
esac
