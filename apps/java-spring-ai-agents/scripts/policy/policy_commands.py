#!/usr/bin/env python3
"""
AgentCore Policy Management Commands
"""

from bedrock_agentcore_starter_toolkit.operations.policy.client import PolicyClient
import boto3
from config import REGION


def get_policy_client():
    return PolicyClient(region_name=REGION)


def get_control_client():
    return boto3.client('bedrock-agentcore-control', region_name=REGION)


# Policy Engine operations
def create_policy_engine(name: str):
    client = get_policy_client()
    engine = client.create_policy_engine(name=name)
    print(f"Created: {engine['policyEngineId']}")
    print(f"ARN: {engine['policyEngineArn']}")
    return engine


def list_policy_engines():
    client = get_policy_client()
    for e in client.list_policy_engines().get('policyEngines', []):
        print(f"{e['name']}: {e['policyEngineId']} - {e['status']}")


def delete_policy_engine(engine_id: str):
    client = get_policy_client()
    client.delete_policy_engine(engine_id)
    print(f"Deleted: {engine_id}")


# Policy operations
def create_policy(engine_id: str, name: str, cedar_statement: str):
    client = get_policy_client()
    policy = client.create_policy(
        policy_engine_id=engine_id,
        name=name,
        definition={"cedar": {"statement": cedar_statement}}
    )
    print(f"Created: {policy['policyId']} - Status: {policy['status']}")
    return policy


def list_policies(engine_id: str):
    client = get_policy_client()
    for p in client.list_policies(engine_id).get('policies', []):
        print(f"{p['name']}: {p['status']}")
        for r in p.get('statusReasons', []):
            print(f"  - {r}")


def delete_all_policies(engine_id: str):
    client = get_policy_client()
    for p in client.list_policies(engine_id).get('policies', []):
        client.delete_policy(engine_id, p['policyId'])
        print(f"Deleted: {p['name']}")


# Gateway attachment
def attach_policy_engine(gateway_id: str, engine_arn: str, mode: str = "ENFORCE"):
    client = get_control_client()
    gw = client.get_gateway(gatewayIdentifier=gateway_id)
    client.update_gateway(
        gatewayIdentifier=gateway_id,
        name=gw['name'],
        roleArn=gw['roleArn'],
        protocolType=gw['protocolType'],
        authorizerType=gw['authorizerType'],
        policyEngineConfiguration={"arn": engine_arn, "mode": mode}
    )
    print(f"Attached {engine_arn} to {gateway_id} in {mode} mode")


def get_gateway_policy_config(gateway_id: str):
    client = get_control_client()
    config = client.get_gateway(gatewayIdentifier=gateway_id).get('policyEngineConfiguration')
    if config:
        print(f"Policy Engine: {config['arn']}")
        print(f"Mode: {config['mode']}")
    else:
        print("No policy engine attached")
    return config
