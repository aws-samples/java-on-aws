#!/bin/bash
# Sign in for an AgentCore Identity consent link and print the session ID (see oauth_sign_in.py).
#   oauth-sign-in.sh AUTHORIZATION_URL USERNAME PASSWORD
exec uv run --quiet --no-project --with requests python "$(dirname "$0")/oauth_sign_in.py" "$@"
