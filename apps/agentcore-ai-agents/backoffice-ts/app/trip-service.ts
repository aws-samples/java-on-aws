// Trip service of the backoffice application: business trips in Amazon DynamoDB.
import { randomUUID } from 'node:crypto';

import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, PutCommand, QueryCommand } from '@aws-sdk/lib-dynamodb';

const TABLE = process.env.TRIP_TABLE ?? 'backoffice-trip';
const db = DynamoDBDocumentClient.from(new DynamoDBClient({ region: process.env.AWS_REGION }));

export async function registerTrip(userId: string, departureDate: string, returnDate: string,
  origin: string, destination: string, purpose: string) {
  if (returnDate < departureDate) {
    throw new Error('returnDate must be after departureDate');
  }
  const tripReference = `TRP-${randomUUID().replace(/-/g, '').slice(0, 8).toUpperCase()}`;
  const now = new Date().toISOString();
  const trip = {
    pk: `USER#${userId}`, sk: `TRIP#${tripReference}`, tripReference, userId, departureDate, returnDate,
    origin, destination, purpose, status: 'PLANNED', createdAt: now, updatedAt: now,
  };
  await db.send(new PutCommand({ TableName: TABLE, Item: trip }));
  return trip;
}

export async function getTrips(userId: string) {
  const res = await db.send(new QueryCommand({
    TableName: TABLE, KeyConditionExpression: 'pk = :pk', ExpressionAttributeValues: { ':pk': `USER#${userId}` },
  }));
  return res.Items ?? [];
}

export async function getTrip(tripReference: string) {
  const res = await db.send(new QueryCommand({
    TableName: TABLE, IndexName: 'tripReference-index',
    KeyConditionExpression: 'tripReference = :ref', ExpressionAttributeValues: { ':ref': tripReference },
  }));
  if (!res.Items?.length) {
    throw new Error(`Trip not found: ${tripReference}`);
  }
  return res.Items[0];
}

export async function cancelTrip(tripReference: string) {
  const trip = await getTrip(tripReference);
  if (trip.status === 'COMPLETED') {
    throw new Error('Cannot cancel completed trip');
  }
  const updated = { ...trip, status: 'CANCELLED', updatedAt: new Date().toISOString() };
  await db.send(new PutCommand({ TableName: TABLE, Item: updated }));
  return updated;
}
