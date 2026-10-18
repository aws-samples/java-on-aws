from typing import Annotated

from pydantic import Field
# >> `FastMCP` from the MCP Python SDK turns Python functions into MCP tools
from mcp.server.fastmcp import FastMCP
# <<

import trip_service

# >> Port 8000, the `/mcp` path, and stateless streamable HTTP are required by AgentCore Runtime; `json_response` returns plain JSON instead of an event stream
mcp = FastMCP("backoffice", host="0.0.0.0", port=8000, stateless_http=True, json_response=True)
# <<


# >> The function name and docstring become the tool name and description; the model reads them to decide when to call the tool
@mcp.tool()
def registerTrip(
# <<
    # >> `Field` descriptions guide the model on parameter extraction from user prompts
    userId: Annotated[str, Field(description="User ID")],
    departureDate: Annotated[str, Field(description="Departure date (YYYY-MM-DD)")],
    returnDate: Annotated[str, Field(description="Return date (YYYY-MM-DD)")],
    origin: Annotated[str, Field(description="Origin city")],
    destination: Annotated[str, Field(description="Destination city")],
    purpose: Annotated[str, Field(description="Trip purpose")],
    # <<
) -> dict:
    """Register a new business trip. Returns trip reference for tracking."""
    return trip_service.register_trip(userId, departureDate, returnDate, origin, destination, purpose)


@mcp.tool()
def getTrips(userId: Annotated[str, Field(description="User ID")]) -> list[dict]:
    """Get all business trips registered by a user"""
    return trip_service.get_trips(userId)


@mcp.tool()
def getTrip(tripReference: Annotated[str, Field(description="Trip reference (TRP-XXXXXXXX)")]) -> dict:
    """Get trip details by reference number"""
    return trip_service.get_trip(tripReference)


@mcp.tool()
def cancelTrip(tripReference: Annotated[str, Field(description="Trip reference (TRP-XXXXXXXX)")]) -> dict:
    """Cancel a planned trip"""
    return trip_service.cancel_trip(tripReference)


if __name__ == "__main__":
    # >> Serve the tools over streamable HTTP at `/mcp`
    mcp.run(transport="streamable-http")
    # <<
