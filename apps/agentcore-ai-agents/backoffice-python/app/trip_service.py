"""Trip service of the backoffice application: business trips in Amazon DynamoDB."""

import os
import uuid
from datetime import date, datetime

import boto3
from boto3.dynamodb.conditions import Key

table = boto3.resource("dynamodb", region_name=os.environ.get("AWS_REGION") or boto3.session.Session().region_name).Table(os.environ.get("TRIP_TABLE", "backoffice-trip"))


def register_trip(user_id, departure_date, return_date, origin, destination, purpose):
    if date.fromisoformat(return_date) < date.fromisoformat(departure_date):
        raise ValueError("returnDate must be after departureDate")
    reference = f"TRP-{uuid.uuid4().hex[:8].upper()}"
    now = datetime.now().isoformat()
    trip = {
        "pk": f"USER#{user_id}", "sk": f"TRIP#{reference}", "tripReference": reference,
        "userId": user_id, "departureDate": departure_date, "returnDate": return_date,
        "origin": origin, "destination": destination, "purpose": purpose,
        "status": "PLANNED", "createdAt": now, "updatedAt": now,
    }
    table.put_item(Item=trip)
    return trip


def get_trips(user_id):
    return table.query(KeyConditionExpression=Key("pk").eq(f"USER#{user_id}"))["Items"]


def get_trip(trip_reference):
    items = table.query(
        IndexName="tripReference-index", KeyConditionExpression=Key("tripReference").eq(trip_reference)
    )["Items"]
    if not items:
        raise LookupError(f"Trip not found: {trip_reference}")
    return items[0]


def cancel_trip(trip_reference):
    trip = get_trip(trip_reference)
    if trip["status"] == "COMPLETED":
        raise ValueError("Cannot cancel completed trip")
    trip["status"] = "CANCELLED"
    trip["updatedAt"] = datetime.now().isoformat()
    table.put_item(Item=trip)
    return trip
