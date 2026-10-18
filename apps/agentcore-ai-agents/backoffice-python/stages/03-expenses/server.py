from typing import Annotated

from pydantic import Field
from mcp.server.fastmcp import FastMCP

# >> Import the expense service
import expense_service
# <<
import trip_service
mcp = FastMCP("backoffice", host="0.0.0.0", port=8000, stateless_http=True, json_response=True)
@mcp.tool()
def registerTrip(
    userId: Annotated[str, Field(description="User ID")],
    departureDate: Annotated[str, Field(description="Departure date (YYYY-MM-DD)")],
    returnDate: Annotated[str, Field(description="Return date (YYYY-MM-DD)")],
    origin: Annotated[str, Field(description="Origin city")],
    destination: Annotated[str, Field(description="Destination city")],
    purpose: Annotated[str, Field(description="Trip purpose")],
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


# >> Expense tools: same names, descriptions, and parameters as the Java backoffice (`ExpenseTools.java`)
@mcp.tool()
def createExpense(
    userId: Annotated[str, Field(description="User ID")],
    amount: Annotated[float, Field(description="Amount")],
    currency: Annotated[str, Field(description="Currency code (USD, EUR, etc.)")],
    date: Annotated[str, Field(description="Expense date (YYYY-MM-DD)")],
    description: Annotated[str, Field(description="Description of expense")],
    type: Annotated[str, Field(description="Type: FLIGHT, HOTEL, MEALS, TRANSPORT, OTHER")],
    tripReference: Annotated[str | None, Field(description="Trip reference to link (optional, TRP-XXXXXXXX)")] = None,
) -> dict:
    """Create a new expense report. Optionally link to a trip."""
    return expense_service.create_expense(userId, amount, currency, date, description, type, tripReference)
# <<


@mcp.tool()
def getExpenses(userId: Annotated[str, Field(description="User ID")]) -> list[dict]:
    """Get all expenses for a user"""
    return expense_service.get_expenses(userId)


@mcp.tool()
def getExpense(expenseReference: Annotated[str, Field(description="Expense reference (EXP-XXXXXXXX)")]) -> dict:
    """Get expense details by reference number"""
    return expense_service.get_expense(expenseReference)


@mcp.tool()
def getExpensesForTrip(tripReference: Annotated[str, Field(description="Trip reference (TRP-XXXXXXXX)")]) -> list[dict]:
    """Get all expenses linked to a specific trip"""
    return expense_service.get_expenses_for_trip(tripReference)


@mcp.tool()
def submitExpense(expenseReference: Annotated[str, Field(description="Expense reference (EXP-XXXXXXXX)")]) -> dict:
    """Submit a draft expense for approval"""
    return expense_service.submit_expense(expenseReference)


@mcp.tool()
def approveExpense(
    expenseReference: Annotated[str, Field(description="Expense reference (EXP-XXXXXXXX)")],
    approverId: Annotated[str, Field(description="User ID of the approving manager")],
) -> dict:
    """Approve a submitted expense (managers only)"""
    return expense_service.approve_expense(expenseReference, approverId)


@mcp.tool()
def deleteExpense(expenseReference: Annotated[str, Field(description="Expense reference (EXP-XXXXXXXX)")]) -> dict:
    """Delete a draft expense"""
    return expense_service.delete_expense(expenseReference)


if __name__ == "__main__":
    mcp.run(transport="streamable-http")
