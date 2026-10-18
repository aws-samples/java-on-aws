"""Expense service of the backoffice application: expense reports in Amazon DynamoDB."""

import os
import uuid
from datetime import date, datetime
from decimal import Decimal

import boto3
from boto3.dynamodb.conditions import Key

import trip_service

TYPES = {"FLIGHT", "HOTEL", "MEALS", "TRANSPORT", "OTHER"}
table = boto3.resource("dynamodb", region_name=os.environ.get("AWS_REGION") or boto3.session.Session().region_name).Table(os.environ.get("EXPENSE_TABLE", "backoffice-expense"))


def create_expense(user_id, amount, currency, expense_date, description, expense_type, trip_reference=None):
    if expense_type not in TYPES:
        raise ValueError(f"type must be one of {', '.join(sorted(TYPES))}")
    date.fromisoformat(expense_date)
    if trip_reference:
        trip_service.get_trip(trip_reference)
    reference = f"EXP-{uuid.uuid4().hex[:8].upper()}"
    now = datetime.now().isoformat()
    expense = {
        "pk": f"USER#{user_id}", "sk": f"EXPENSE#{reference}", "expenseReference": reference,
        "userId": user_id, "amount": Decimal(str(amount)), "currency": currency, "date": expense_date,
        "description": description, "type": expense_type, "status": "DRAFT", "createdAt": now, "updatedAt": now,
    }
    if trip_reference:
        expense["tripReference"] = trip_reference
    table.put_item(Item=expense)
    return expense


def get_expenses(user_id):
    return table.query(KeyConditionExpression=Key("pk").eq(f"USER#{user_id}") & Key("sk").begins_with("EXPENSE#"))["Items"]


def get_expense(expense_reference):
    items = table.query(
        IndexName="expenseReference-index", KeyConditionExpression=Key("expenseReference").eq(expense_reference)
    )["Items"]
    if not items:
        raise LookupError(f"Expense not found: {expense_reference}")
    return items[0]


def get_expenses_for_trip(trip_reference):
    trip_service.get_trip(trip_reference)
    return table.query(IndexName="tripReference-index", KeyConditionExpression=Key("tripReference").eq(trip_reference))["Items"]


def submit_expense(expense_reference):
    expense = get_expense(expense_reference)
    if expense["status"] != "DRAFT":
        raise ValueError("Only draft expenses can be submitted")
    expense["status"] = "SUBMITTED"
    expense["updatedAt"] = datetime.now().isoformat()
    table.put_item(Item=expense)
    return expense


def approve_expense(expense_reference, approver_id):
    expense = get_expense(expense_reference)
    if expense["status"] != "SUBMITTED":
        raise ValueError("Only submitted expenses can be approved")
    expense["status"] = "APPROVED"
    expense["approvedBy"] = approver_id
    expense["updatedAt"] = datetime.now().isoformat()
    table.put_item(Item=expense)
    return expense


def delete_expense(expense_reference):
    expense = get_expense(expense_reference)
    if expense["status"] != "DRAFT":
        raise ValueError("Only draft expenses can be deleted")
    table.delete_item(Key={"pk": expense["pk"], "sk": expense["sk"]})
    return expense
