#!/usr/bin/env python3
"""
Step 3: Attach Policy Engine to Gateway

Run: python 03-attach-policy-engine.py
Requires: ENGINE_ID and GATEWAY_ID set in config.py
"""

from config import GATEWAY_ID, ENGINE_ARN
from policy_commands import attach_policy_engine, get_gateway_policy_config

if __name__ == "__main__":
    import time
    
    print(f"Using GATEWAY_ID: {GATEWAY_ID}")
    print(f"Using ENGINE_ARN: {ENGINE_ARN}")
    
    print("\n=== Attaching Policy Engine ===")
    attach_policy_engine(GATEWAY_ID, ENGINE_ARN, mode="ENFORCE")
    
    print("\n=== Waiting for attachment ===")
    for i in range(10):
        time.sleep(2)
        config = get_gateway_policy_config(GATEWAY_ID)
        if config:
            print("✓ Policy engine attached")
            break
        print(f"  Attempt {i+1}/10...")
    else:
        print("✗ Attachment not confirmed after 10 attempts")
