"""Corporate calendar API (behind an API Gateway HTTP API with a JWT authorizer): GET /events with a bearer token of the calendar user pool."""
import calendar
import json
import os
import urllib.error
import urllib.request
from datetime import date, timedelta

USERINFO_URL = os.environ["USERINFO_URL"]


def trip_start(today):
    """The Monday of the week that contains today plus two calendar months (the workshop's trip rule)."""
    month = today.month + 2
    year, month = today.year + (month - 1) // 12, (month - 1) % 12 + 1
    day = min(today.day, calendar.monthrange(year, month)[1])
    start = date(year, month, day)
    return start - timedelta(days=start.weekday())


def working_days_after(day, count):
    while count:
        day += timedelta(days=1)
        if day.weekday() < 5:
            count -= 1
    return day


def events(username, today):
    """Events relative to the day of the request, so the calendar is always about two months ahead."""
    trip = trip_start(today)
    planning = working_days_after(today, 2)
    first_tuesday = today + timedelta(days=(1 - today.weekday()) % 7)
    team = [{"date": (first_tuesday + timedelta(weeks=w)).isoformat(), "time": "10:00-11:00",
             "title": "Team meeting", "location": "Berlin"} for w in range(12)]
    if username == "alice":
        own = [
            {"date": planning.isoformat(), "time": "14:00-15:00", "title": "Travel planning with Bob", "location": "Berlin"},
            *({"date": (trip + timedelta(days=d)).isoformat(), "time": "09:00-17:00",
               "title": f"AI conference, day {d}", "location": "San Francisco"} for d in (1, 2, 3)),
            {"date": (trip + timedelta(days=8)).isoformat(), "time": "14:00-15:00", "title": "1:1 with Bob", "location": "Berlin"},
        ]
    elif username == "bob":
        own = [
            {"date": planning.isoformat(), "time": "14:00-15:00", "title": "Travel planning with Alice", "location": "Berlin"},
            {"date": (trip + timedelta(days=8)).isoformat(), "time": "14:00-15:00", "title": "1:1 with Alice", "location": "Berlin"},
        ]
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
