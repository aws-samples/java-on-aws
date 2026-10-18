// Expense service of the backoffice application: expense reports in Amazon DynamoDB.
import { randomUUID } from 'node:crypto';

import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DeleteCommand, DynamoDBDocumentClient, PutCommand, QueryCommand } from '@aws-sdk/lib-dynamodb';

import * as trips from './trip-service.js';

const TABLE = process.env.EXPENSE_TABLE ?? 'backoffice-expense';
const TYPES = ['FLIGHT', 'HOTEL', 'MEALS', 'TRANSPORT', 'OTHER'];
const db = DynamoDBDocumentClient.from(new DynamoDBClient({ region: process.env.AWS_REGION }));

export async function createExpense(userId: string, amount: number, currency: string, date: string,
  description: string, type: string, tripReference?: string) {
  if (!TYPES.includes(type)) {
    throw new Error(`type must be one of ${TYPES.join(', ')}`);
  }
  if (tripReference) {
    await trips.getTrip(tripReference);
  }
  const expenseReference = `EXP-${randomUUID().replace(/-/g, '').slice(0, 8).toUpperCase()}`;
  const now = new Date().toISOString();
  const expense = {
    pk: `USER#${userId}`, sk: `EXPENSE#${expenseReference}`, expenseReference, userId, amount, currency, date,
    description, type, status: 'DRAFT', createdAt: now, updatedAt: now, ...(tripReference ? { tripReference } : {}),
  };
  await db.send(new PutCommand({ TableName: TABLE, Item: expense }));
  return expense;
}

export async function getExpenses(userId: string) {
  const res = await db.send(new QueryCommand({
    TableName: TABLE, KeyConditionExpression: 'pk = :pk AND begins_with(sk, :sk)',
    ExpressionAttributeValues: { ':pk': `USER#${userId}`, ':sk': 'EXPENSE#' },
  }));
  return res.Items ?? [];
}

export async function getExpense(expenseReference: string) {
  const res = await db.send(new QueryCommand({
    TableName: TABLE, IndexName: 'expenseReference-index',
    KeyConditionExpression: 'expenseReference = :ref', ExpressionAttributeValues: { ':ref': expenseReference },
  }));
  if (!res.Items?.length) {
    throw new Error(`Expense not found: ${expenseReference}`);
  }
  return res.Items[0];
}

export async function getExpensesForTrip(tripReference: string) {
  await trips.getTrip(tripReference);
  const res = await db.send(new QueryCommand({
    TableName: TABLE, IndexName: 'tripReference-index',
    KeyConditionExpression: 'tripReference = :ref', ExpressionAttributeValues: { ':ref': tripReference },
  }));
  return res.Items ?? [];
}

export async function submitExpense(expenseReference: string) {
  const expense = await getExpense(expenseReference);
  if (expense.status !== 'DRAFT') {
    throw new Error('Only draft expenses can be submitted');
  }
  const updated = { ...expense, status: 'SUBMITTED', updatedAt: new Date().toISOString() };
  await db.send(new PutCommand({ TableName: TABLE, Item: updated }));
  return updated;
}

export async function approveExpense(expenseReference: string, approverId: string) {
  const expense = await getExpense(expenseReference);
  if (expense.status !== 'SUBMITTED') {
    throw new Error('Only submitted expenses can be approved');
  }
  const updated = { ...expense, status: 'APPROVED', approvedBy: approverId, updatedAt: new Date().toISOString() };
  await db.send(new PutCommand({ TableName: TABLE, Item: updated }));
  return updated;
}

export async function deleteExpense(expenseReference: string) {
  const expense = await getExpense(expenseReference);
  if (expense.status !== 'DRAFT') {
    throw new Error('Only draft expenses can be deleted');
  }
  await db.send(new DeleteCommand({ TableName: TABLE, Key: { pk: expense.pk, sk: expense.sk } }));
  return expense;
}
