"""Extract a business trip request from an email as structured data: uv run extract_trip.py EMAIL_FILE"""
import os
import sys
from datetime import date
from typing import Literal

from langchain_aws import ChatBedrockConverse
from pydantic import BaseModel, Field


# >> The schema: field names, types, and descriptions tell the model what to extract
class TripRequest(BaseModel):
    """A business trip request extracted from an employee's email."""
    traveler: str = Field(description="Full name of the traveler")
    origin: str = Field(description="Departure city")
    destination: str = Field(description="Destination city")
    departure_date: date = Field(description="Outbound travel date")
    return_date: date = Field(description="Return travel date")
    purpose: str = Field(description="Purpose of the trip, e.g. the event name")
    travel_class: Literal["ECONOMY", "PREMIUM_ECONOMY", "BUSINESS", "FIRST"]
    hotel_preference: str | None = Field(default=None, description="Hotel location or category wishes")
    budget_eur: float | None = Field(default=None, description="Total trip budget in EUR")
    approver: str | None = Field(default=None, description="Who approved the trip or budget")
# <<


model = ChatBedrockConverse(
    model="global.anthropic.claude-sonnet-5-5", max_tokens=1024, region_name=os.environ.get("AWS_REGION")
)
# >> `with_structured_output()` returns a validated `TripRequest` instead of a message
extractor = model.with_structured_output(TripRequest)
# <<

if __name__ == "__main__":
    email = open(sys.argv[1]).read()
    trip = extractor.invoke([("system", "Extract the business trip request from the email."), ("user", email)])
    print(trip.model_dump_json(indent=2))
