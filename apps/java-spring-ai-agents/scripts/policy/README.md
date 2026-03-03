# AgentCore Policy-Based Access Control

Demonstrates Cedar policy-based access control for MCP tools through AgentCore Gateway.

## Overview

```
chat-agent (JWT) → Gateway → Policy Engine → MCP Runtime
                      ↓
              Cedar policy checks
              user's username tag
```

## Key Finding: Use `unless` for Denying Tools

AgentCore rejects standalone `forbid` policies as "Overly Restrictive". 

**Solution:** Use `permit ... unless` to deny specific tools:

```cedar
permit(
  principal is AgentCore::OAuthUser,
  action,
  resource == AgentCore::Gateway::"..."
) when {
  principal.hasTag("username") &&
  principal.getTag("username") == "alice"
} unless {
  action == AgentCore::Action::"travel-mcp___searchFlights"
};
```

## Setup Steps

```bash
cd /Users/shakirin/Projects/agentcore/samples/policy/scripts/policy
source .venv/bin/activate

# 1. Create policy engine (one-time)
python 01-create-policy-engine.py

# 2. Create policy (update ENGINE_ID in script first)
python 02-create-policy.py

# 3. Attach to gateway (update IDs in script first)
python 03-attach-policy-engine.py
```

## Test Results

| Tool | Policy | Result |
|------|--------|--------|
| `searchHotels` | Permitted | ✅ Returns hotel data |
| `searchFlights` | Denied via `unless` | ❌ Tool not available |

## JWT Token Requirements

The policy uses `username` tag from Cognito user tokens:

```json
{
  "username": "alice",
  "client_id": "...",
  "token_use": "access"
}
```

Get user token:
```bash
TOKEN=$(aws cognito-idp initiate-auth \
  --client-id $CLIENT_ID \
  --auth-flow USER_PASSWORD_AUTH \
  --auth-parameters "USERNAME=alice,PASSWORD=$PASSWORD,SECRET_HASH=$SECRET_HASH" \
  --region us-east-1 \
  --query 'AuthenticationResult.AccessToken' --output text)
```

## Files

- `policy.cedar` - Working Cedar policy with `unless` clause
- `policy_commands.py` - Helper functions for policy management
- `01-create-policy-engine.py` - Create policy engine
- `02-create-policy.py` - Create/update policy
- `03-attach-policy-engine.py` - Attach engine to gateway
