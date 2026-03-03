#!/usr/bin/env python3
"""
Step 1: Create Policy Engine

Run: python 01-create-policy-engine.py
Auto-updates ENGINE_ID in .env
"""

from config import update_env
from policy_commands import create_policy_engine, list_policy_engines

ENGINE_NAME = "TravelPolicyEngine"

if __name__ == "__main__":
    print("=== Creating Policy Engine ===")
    engine = create_policy_engine(ENGINE_NAME)
    
    # Auto-update .env
    update_env("ENGINE_ID", engine['policyEngineId'])
    
    print("\n=== All Policy Engines ===")
    list_policy_engines()
