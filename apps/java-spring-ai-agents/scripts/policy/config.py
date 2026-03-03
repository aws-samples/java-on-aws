import os
from dotenv import load_dotenv

load_dotenv()

REGION = os.getenv("REGION", "us-east-1")
ACCOUNT_ID = os.getenv("ACCOUNT_ID")
GATEWAY_ID = os.getenv("GATEWAY_ID")
ENGINE_ID = os.getenv("ENGINE_ID")
TARGET_NAME = os.getenv("TARGET_NAME", "travel-mcp")

# Derived ARNs
GATEWAY_ARN = f"arn:aws:bedrock-agentcore:{REGION}:{ACCOUNT_ID}:gateway/{GATEWAY_ID}"
ENGINE_ARN = f"arn:aws:bedrock-agentcore:{REGION}:{ACCOUNT_ID}:policy-engine/{ENGINE_ID}" if ENGINE_ID else None


def update_env(key: str, value: str):
    """Update a value in .env file."""
    env_path = os.path.join(os.path.dirname(__file__), ".env")
    
    with open(env_path, "r") as f:
        lines = f.readlines()
    
    updated = False
    for i, line in enumerate(lines):
        if line.startswith(f"{key}="):
            lines[i] = f"{key}={value}\n"
            updated = True
            break
    
    if not updated:
        lines.append(f"{key}={value}\n")
    
    with open(env_path, "w") as f:
        f.writelines(lines)
    
    # Update current process
    os.environ[key] = value
    print(f"Updated .env: {key}={value}")
