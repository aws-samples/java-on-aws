#!/bin/bash
set -e

echo "=============================================="
echo "13-mcp-policy.sh - MCP Gateway Policy Deployment"
echo "=============================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source ~/environment/.envrc 2>/dev/null || true

if [ -z "${GATEWAY_ID}" ]; then
    echo "Error: Missing GATEWAY_ID. Run 06-mcp-gateway.sh first."
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --no-cli-pager)
AWS_REGION=$(aws configure get region --no-cli-pager)
GATEWAY_ARN="arn:aws:bedrock-agentcore:${AWS_REGION}:${ACCOUNT_ID}:gateway/${GATEWAY_ID}"

echo "Gateway: ${GATEWAY_ID}"

VENV_DIR="/tmp/policy_venv"
[ ! -d "${VENV_DIR}" ] && python3 -m venv "${VENV_DIR}" && "${VENV_DIR}/bin/pip" install -q boto3

"${VENV_DIR}/bin/python3" << EOF
import boto3, time, secrets, json

client = boto3.client('bedrock-agentcore-control', region_name='${AWS_REGION}')
iam = boto3.client('iam', region_name='${AWS_REGION}')

GATEWAY_ARN = "${GATEWAY_ARN}"
ACCOUNT_ID = "${ACCOUNT_ID}"

# Get or create policy engine
engines = client.list_policy_engines()
existing = [e for e in engines.get('policyEngines', []) if e['name'].startswith('BackofficePolicyEngine') and e['status'] == 'ACTIVE']
if existing:
    ENGINE_ID = existing[0]['policyEngineId']
else:
    result = client.create_policy_engine(name=f"BackofficePolicyEngine_{secrets.token_hex(5)}")
    ENGINE_ID = result['policyEngineId']
    while client.get_policy_engine(policyEngineId=ENGINE_ID)['status'] != 'ACTIVE':
        time.sleep(3)
print(f"Policy Engine: {ENGINE_ID}")

# Cleanup
for p in client.list_policies(policyEngineId=ENGINE_ID).get('policies', []):
    try: client.delete_policy(policyEngineId=ENGINE_ID, policyId=p['policyId']); time.sleep(1)
    except: pass

# Try combined policy first
COMBINED = f'''forbid(
  principal,
  action in [
    AgentCore::Action::"backoffice___cancelTrip",
    AgentCore::Action::"backoffice___deleteExpense"
  ],
  resource == AgentCore::Gateway::"{GATEWAY_ARN}"
);'''

print("Creating forbid policy...")
result = client.create_policy(
    policyEngineId=ENGINE_ID,
    name="ForbidDangerousOperations",
    definition={'cedar': {'statement': COMBINED}},
    validationMode='IGNORE_ALL_FINDINGS'
)

success = False
for _ in range(15):
    p = client.get_policy(policyEngineId=ENGINE_ID, policyId=result['policyId'])
    if p['status'] == 'ACTIVE':
        print("  ✅ Combined policy active")
        success = True
        break
    elif 'FAILED' in p['status']:
        print("  ⚠️  Combined failed, creating separate policies...")
        client.delete_policy(policyEngineId=ENGINE_ID, policyId=result['policyId'])
        break
    time.sleep(2)

# Fallback to separate policies
if not success:
    for action in ["cancelTrip", "deleteExpense"]:
        policy = f'''forbid(
  principal,
  action == AgentCore::Action::"backoffice___{action}",
  resource == AgentCore::Gateway::"{GATEWAY_ARN}"
);'''
        result = client.create_policy(
            policyEngineId=ENGINE_ID,
            name=f"Forbid{action}",
            definition={'cedar': {'statement': policy}},
            validationMode='IGNORE_ALL_FINDINGS'
        )
        for _ in range(10):
            p = client.get_policy(policyEngineId=ENGINE_ID, policyId=result['policyId'])
            if p['status'] == 'ACTIVE':
                print(f"  ✅ Forbid{action}: active")
                break
            elif 'FAILED' in p['status']:
                print(f"  ⚠️  Forbid{action}: failed (tool not in schema)")
                break
            time.sleep(2)

# IAM
iam.put_role_policy(
    RoleName='mcp-gateway-role',
    PolicyName='PolicyEngineAccess',
    PolicyDocument=json.dumps({
        "Version": "2012-10-17",
        "Statement": [{"Effect": "Allow", "Action": [
            "bedrock-agentcore:GetPolicyEngine", "bedrock-agentcore:IsAuthorized",
            "bedrock-agentcore:AuthorizeAction", "bedrock-agentcore:AuthorizeActions"
        ], "Resource": f"arn:aws:bedrock-agentcore:${AWS_REGION}:{ACCOUNT_ID}:*"}]
    })
)

# Attach to gateway
gateway = client.get_gateway(gatewayIdentifier="${GATEWAY_ID}")
ENGINE_ARN = f"arn:aws:bedrock-agentcore:${AWS_REGION}:{ACCOUNT_ID}:policy-engine/{ENGINE_ID}"
client.update_gateway(
    gatewayIdentifier="${GATEWAY_ID}",
    name=gateway['name'], roleArn=gateway['roleArn'],
    protocolType=gateway['protocolType'], authorizerType=gateway['authorizerType'],
    policyEngineConfiguration={'arn': ENGINE_ARN, 'mode': 'ENFORCE'}
)
while client.get_gateway(gatewayIdentifier="${GATEWAY_ID}")['status'] != 'READY':
    time.sleep(2)
print("✅ Gateway ready")
EOF

echo ""
echo "Done! Forbidden: cancelTrip, deleteExpense"
