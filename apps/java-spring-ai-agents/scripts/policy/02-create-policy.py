#!/usr/bin/env python3
"""
Step 2: Create Policy

Run: python 02-create-policy.py
Requires: ENGINE_ID set in config.py
"""

from config import ENGINE_ID, GATEWAY_ARN, TARGET_NAME
from policy_commands import create_policy, list_policies, delete_all_policies
import time

# Policy: Permit all tools for alice, EXCEPT searchFlights
POLICY = f'''permit(
  principal is AgentCore::OAuthUser,
  action,
  resource == AgentCore::Gateway::"{GATEWAY_ARN}"
) when {{
  principal.hasTag("username") &&
  principal.getTag("username") == "alice"
}} unless {{
  action == AgentCore::Action::"{TARGET_NAME}___searchFlights"
}};'''

if __name__ == "__main__":
    print(f"Using ENGINE_ID: {ENGINE_ID}")
    print(f"Using GATEWAY_ARN: {GATEWAY_ARN}")
    
    print("\n=== Deleting existing policies ===")
    delete_all_policies(ENGINE_ID)
    time.sleep(3)
    
    print("\n=== Creating policy ===")
    create_policy(ENGINE_ID, "PermitAllExceptFlights", POLICY)
    
    time.sleep(5)
    
    print("\n=== Policy status ===")
    list_policies(ENGINE_ID)
