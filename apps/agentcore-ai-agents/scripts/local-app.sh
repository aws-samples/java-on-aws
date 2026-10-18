#!/bin/bash
# Run the AI agent or the backoffice MCP server in the background for the terminal tests.
#
#   local-app.sh start [DIR]            start the application in DIR (default: the current directory)
#                                       and wait until it answers; stops an earlier instance first
#   local-app.sh ask PROMPT [SESSION]   send PROMPT to the AI agent and print the streamed answer as text
#                                       (SESSION: X-Amzn-Bedrock-AgentCore-Runtime-Session-Id, default alice)
#   local-app.sh oauth SESSION_URI [SESSION]  hand a consent session from AgentCore Identity to the AI agent,
#                                       as the UI's callback page does
#   local-app.sh stop [DIR]             stop the application started from DIR
#
# The start command follows the project: uv run main.py / server.py, npx tsx main.ts / server.ts,
# ./mvnw (or mvn) spring-boot:run. The AI agent listens on 8080 (/ping), the MCP server (folder backoffice*) on 8000 (/mcp).
# The application reads ~/environment/.envrc; its output goes to /tmp/<folder>.log.
# AUTH_TOKEN adds "Authorization: Bearer AUTH_TOKEN" to ask.
# ATTACH_FILE=PATH sends the file with the prompt (fileName, fileBase64), like the attachment button of the UI.
set -euo pipefail

request_body() {  # the JSON body of /invocations: prompt, and the file of ATTACH_FILE
  if [ -n "${ATTACH_FILE:-}" ]; then
    jq -n --arg prompt "$1" --arg name "$(basename "${ATTACH_FILE}")" --rawfile data <(base64 -w0 "${ATTACH_FILE}" 2>/dev/null || base64 -i "${ATTACH_FILE}") \
      '{prompt: $prompt, fileName: $name, fileBase64: $data}'
  else
    jq -n --arg prompt "$1" '{prompt: $prompt}'
  fi
}

app_dir() { cd "${1:-.}" && pwd; }
name_of() { basename "$1"; }

start_command() {
  if [ -x mvnw ]; then echo "./mvnw -q spring-boot:run"
  elif [ -f pom.xml ]; then echo "mvn -q spring-boot:run"
  elif [ -f main.py ]; then echo "uv run main.py"
  elif [ -f server.py ]; then echo "uv run server.py"
  elif [ -f main.ts ]; then echo "npx tsx main.ts"
  elif [ -f server.ts ]; then echo "npx tsx server.ts"
  else echo "local-app.sh: no main.py, server.py, main.ts, server.ts, or pom.xml in $(pwd)" >&2; return 1
  fi
}

stop_app() {
  local pidfile="/tmp/$1.pid" pid
  [ -f "${pidfile}" ] || return 0
  pid=$(cat "${pidfile}")
  rm -f "${pidfile}"
  kill -TERM -- "-${pid}" 2>/dev/null || return 0
  for _ in $(seq 30); do
    kill -0 -- "-${pid}" 2>/dev/null || return 0
    sleep 1
  done
  kill -KILL -- "-${pid}" 2>/dev/null || true
}

case "${1:-}" in
  start)
    dir=$(app_dir "${2:-}")
    name=$(name_of "${dir}")
    stop_app "${name}"
    cd "${dir}"
    cmd=$(start_command)
    case "${name}" in
      backoffice*) url="http://localhost:8000/mcp" ;;
      *) url="http://localhost:8080/ping" ;;
    esac
    # shellcheck disable=SC1090
    [ -f ~/environment/.envrc ] && set -a && source ~/environment/.envrc && set +a
    set -m  # own process group, so stop also ends the processes uv, npx, and mvnw start
    ${cmd} > "/tmp/${name}.log" 2>&1 &
    echo $! > "/tmp/${name}.pid"
    set +m
    echo -n "Starting ${name} (${cmd})"
    for _ in $(seq 150); do
      code=$(curl -s -o /dev/null -w "%{http_code}" "${url}" || true)
      if [ "${code}" != "000" ] && { [ "${url##*/}" != "ping" ] || [ "${code}" = "200" ]; }; then
        echo " ready on ${url%/*}"
        exit 0
      fi
      if ! kill -0 "$(cat "/tmp/${name}.pid")" 2>/dev/null; then
        echo " exited"; tail -n 30 "/tmp/${name}.log"; exit 1
      fi
      echo -n "."; sleep 2
    done
    echo " no answer on ${url} after 300 s"; tail -n 30 "/tmp/${name}.log"; exit 1
    ;;
  ask)
    prompt="${2:?local-app.sh ask PROMPT [SESSION]}"
    curl -sSN --fail-with-body --max-time 300 -X POST http://localhost:8080/invocations \
      -H "Content-Type: application/json" \
      -H "Accept: text/event-stream" \
      -H "X-Amzn-Bedrock-AgentCore-Runtime-Session-Id: ${3:-alice}" \
      ${AUTH_TOKEN:+-H "Authorization: Bearer ${AUTH_TOKEN}"} \
      -d @<(request_body "${prompt}") \
    | python3 "$(dirname "$0")/sse_text.py"
    ;;
  oauth)
    curl -sSN --fail-with-body --max-time 60 -X POST http://localhost:8080/invocations \
      -H "Content-Type: application/json" \
      -H "Accept: text/event-stream" \
      -H "X-Amzn-Bedrock-AgentCore-Runtime-Session-Id: ${3:-alice}" \
      ${AUTH_TOKEN:+-H "Authorization: Bearer ${AUTH_TOKEN}"} \
      -d "$(jq -n --arg session "${2:?local-app.sh oauth SESSION_URI [SESSION]}" '{oauthSession: $session}')" \
    | python3 "$(dirname "$0")/sse_text.py"
    ;;
  stop)
    stop_app "$(name_of "$(app_dir "${2:-}")")"
    ;;
  *)
    sed -n '2,13p' "$0"; exit 2
    ;;
esac
