import json
import os
import urllib.request
from contextvars import ContextVar

import boto3
from bedrock_agentcore.runtime.context import BedrockAgentCoreContext
from strands import tool

CALENDAR_URL = os.environ.get("CALENDAR_URL")
# >> Where AgentCore sends the browser after the consent: the UI's callback page
RETURN_URL = os.environ.get("OAUTH_RETURN_URL", "http://localhost:8080/callback.html")
# <<
LOCAL_WORKLOAD = "aiagent-local"
REGION = os.environ.get("AWS_REGION") or boto3.session.Session().region_name

identity = boto3.client("bedrock-agentcore", region_name=REGION)
# (user ID, bearer token) of the current request; the token is empty for local requests without Cognito
current_user = ContextVar("current_user", default=("", ""))


def workload_token():
    # >> On AgentCore Runtime the request carries a workload access token for the signed-in user
    token = BedrockAgentCoreContext.get_workload_access_token()
    if token:
        return token
    # <<
    # >> Locally, the application gets one for the user ID from its own workload identity
    user_id, _ = current_user.get()
    return identity.get_workload_access_token_for_user_id(workloadName=LOCAL_WORKLOAD, userId=user_id)["workloadAccessToken"]
    # <<


def complete_authorization(session_uri):
    """Bind the consent session from the callback page to the user who started it."""
    user_id, bearer = current_user.get()
    # >> The same user as for the workload access token: the user's JWT on Runtime, the user ID locally
    on_runtime = BedrockAgentCoreContext.get_workload_access_token() is not None
    user = {"userToken": bearer.removeprefix("Bearer ")} if on_runtime else {"userId": user_id}
    identity.complete_resource_token_auth(sessionUri=session_uri, userIdentifier=user)
    # <<


@tool
def get_calendar_events() -> str:
    """Read the user's events from the corporate calendar: meetings, trips, and conferences with date, time, and location.
    Use it to check whether the user is free for a trip or to find the dates of an event."""
    # >> USER_FEDERATION (3LO): a token for this user from the token vault, or a link for the user's consent
    response = identity.get_resource_oauth2_token(
        workloadIdentityToken=workload_token(),
        resourceCredentialProviderName="calendar-provider",
        scopes=["openid", "calendar/read"],
        oauth2Flow="USER_FEDERATION",
        resourceOauth2ReturnUrl=RETURN_URL,
    )
    # <<
    if "accessToken" not in response:
        return ("The user has not connected the corporate calendar yet. Give the user this link to sign in "
                f"and ask them to send the question again afterwards: {response['authorizationUrl']}")
    # >> Call the calendar API with the user's token, as the user
    request = urllib.request.Request(f"{CALENDAR_URL}/events",
                                     headers={"Authorization": f"Bearer {response['accessToken']}"})
    with urllib.request.urlopen(request, timeout=10) as result:
        return json.dumps(json.loads(result.read())["events"])
    # <<
