"""Corporate calendar API (behind an API Gateway HTTP API with a JWT authorizer): GET /events with a bearer token of the calendar user pool."""
import json
import os
import urllib.error
import urllib.request
from datetime import date, timedelta

USERINFO_URL = os.environ["USERINFO_URL"]


def working_days_after(day, count):
    while count:
        day += timedelta(days=1)
        if day.weekday() < 5:
            count -= 1
    return day


def weekly(today, weekday, time, title):
    """The next 12 occurrences from today, so every week of the next three months has one, whatever the trip dates."""
    first = today + timedelta(days=(weekday - today.weekday()) % 7)
    return [{"date": (first + timedelta(weeks=w)).isoformat(), "time": time, "title": title, "location": "Berlin"}
            for w in range(12)]


def events(username, today):
    """Events relative to the day of the request; weekly meetings, so any trip in the next weeks overlaps two of them."""
    planning = working_days_after(today, 2)
    team = weekly(today, 1, "10:00-11:00", "Team meeting")
    if username == "alice":
        own = [{"date": planning.isoformat(), "time": "14:00-15:00", "title": "Travel planning with Bob", "location": "Berlin"},
               *weekly(today, 3, "14:00-15:00", "1:1 with Bob")]
    elif username == "bob":
        own = [{"date": planning.isoformat(), "time": "14:00-15:00", "title": "Travel planning with Alice", "location": "Berlin"},
               *weekly(today, 3, "14:00-15:00", "1:1 with Alice")]
    else:
        return []
    return sorted(own + team, key=lambda e: (e["date"], e["time"]))


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
    return respond(200, {"user": username, "events": events(username, date.today())})
