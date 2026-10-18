"""Corporate calendar API (Lambda function URL): GET /events with a bearer token of the calendar user pool."""
import json
import os
import urllib.error
import urllib.request

USERINFO_URL = os.environ["USERINFO_URL"]

EVENTS = {
    "alice": [
        {"date": "2026-11-12", "time": "14:00-15:00", "title": "Travel planning with bob", "location": "Berlin"},
        {"date": "2026-11-17", "time": "10:00-11:00", "title": "Quarterly review (remote)", "location": "Online"},
        {"date": "2026-11-18", "time": "09:00-18:00", "title": "AI Summit Tokyo, day 1", "location": "Tokyo"},
        {"date": "2026-11-19", "time": "09:00-18:00", "title": "AI Summit Tokyo, day 2", "location": "Tokyo"},
        {"date": "2026-11-20", "time": "09:00-16:00", "title": "AI Summit Tokyo, day 3", "location": "Tokyo"},
        {"date": "2026-11-24", "time": "10:00-11:00", "title": "1:1 with bob", "location": "Berlin"},
    ],
    "bob": [
        {"date": "2026-11-12", "time": "14:00-15:00", "title": "Travel planning with alice", "location": "Berlin"},
        {"date": "2026-11-24", "time": "10:00-11:00", "title": "1:1 with alice", "location": "Berlin"},
    ],
}


def respond(status, body):
    return {"statusCode": status, "headers": {"Content-Type": "application/json"}, "body": json.dumps(body)}


def handler(event, context):
    auth = (event.get("headers") or {}).get("authorization", "")
    if not auth.lower().startswith("bearer "):
        return respond(401, {"error": "missing bearer token"})
    # The user pool validates the token and tells us whose calendar to return
    request = urllib.request.Request(USERINFO_URL, headers={"Authorization": auth})
    try:
        with urllib.request.urlopen(request, timeout=5) as r:
            user = json.loads(r.read())
    except urllib.error.HTTPError as e:
        return respond(401, {"error": f"invalid token ({e.code})"})
    username = user.get("username", "")
    return respond(200, {"user": username, "events": EVENTS.get(username, [])})
