"""Extract a business trip request from an email as structured data: uv run extract_trip.py EMAIL_FILE"""
import sys
from datetime import date
from typing import Literal

from pydantic import BaseModel, Field
from strands import Agent
from strands.models.bedrock import BedrockModel


# >> The schema: field names, types, and descriptions tell the model what to extract
class TripRequest(BaseModel):
    """A business trip request extracted from an employee's email."""
    traveler: str = Field(description="Full name of the traveler")
    origin: str = Field(description="Departure city")
    destination: str = Field(description="Destination city")
    departure_date: date = Field(description="Outbound travel date")
    return_date: date = Field(description="Return travel date")
    purpose: str = Field(description="Purpose of the trip, such as the event")
    travel_class: Literal["ECONOMY", "PREMIUM_ECONOMY", "BUSINESS", "FIRST"]
    hotel_preference: str | None = Field(default=None, description="Hotel location or category wishes")
    budget_eur: float | None = Field(default=None, description="Total trip budget in EUR")
    approver: str | None = Field(default=None, description="Who approves the trip, such as the manager the email goes to")
# <<


model = BedrockModel(model_id="global.anthropic.claude-sonnet-5-5", max_tokens=1024)
# >> Today's date with the weekday, so the model can turn "the Monday two months from now" into a date
today = date.today().strftime("%A, %Y-%m-%d")
agent = Agent(model=model, system_prompt=f"Extract the business trip request from the email. Today is {today}.",
              callback_handler=None)
# <<

if __name__ == "__main__":
    email = open(sys.argv[1]).read()
    # >> `structured_output_model` returns a validated `TripRequest` instead of text
    result = agent(email, structured_output_model=TripRequest)
    print(result.structured_output.model_dump_json(indent=2))
    # <<
