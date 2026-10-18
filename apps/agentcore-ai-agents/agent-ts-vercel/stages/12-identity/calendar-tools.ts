import { AsyncLocalStorage } from 'node:async_hooks';

import {
  BedrockAgentCoreClient, CompleteResourceTokenAuthCommand, GetResourceOauth2TokenCommand, GetWorkloadAccessTokenForUserIdCommand,
} from '@aws-sdk/client-bedrock-agentcore';
import { tool, type ToolSet } from 'ai';
import { z } from 'zod';

const CALENDAR_URL = process.env.CALENDAR_URL;
// >> Where AgentCore sends the browser after the consent: the UI's callback page
const RETURN_URL = process.env.OAUTH_RETURN_URL ?? 'http://localhost:8080/callback.html';
// <<
const LOCAL_WORKLOAD = 'aiagent-local';

const identity = new BedrockAgentCoreClient({ region: process.env.AWS_REGION });
// The user of the current request: user ID, bearer token (empty for local requests without Cognito),
// and the workload access token that AgentCore Runtime adds to the request (undefined locally)
export const currentUser = new AsyncLocalStorage<{ userId: string; bearer: string; workloadToken?: string }>();

async function workloadToken() {
  const { userId, workloadToken } = currentUser.getStore()!;
  // >> On AgentCore Runtime the request carries a workload access token for the signed-in user
  if (workloadToken) {
    return workloadToken;
  }
  // <<
  // >> Locally, the application gets one for the user ID from its own workload identity
  const response = await identity.send(new GetWorkloadAccessTokenForUserIdCommand({ workloadName: LOCAL_WORKLOAD, userId }));
  return response.workloadAccessToken!;
  // <<
}

// Bind the consent session from the callback page to the user who started it
export async function completeAuthorization(sessionUri: string) {
  const { userId, bearer, workloadToken } = currentUser.getStore()!;
  // >> The same user as for the workload access token: the user's JWT on Runtime, the user ID locally
  const userIdentifier = workloadToken ? { userToken: bearer.replace(/^Bearer /, '') } : { userId };
  await identity.send(new CompleteResourceTokenAuthCommand({ sessionUri, userIdentifier }));
  // <<
}

async function getCalendarEvents() {
  // >> USER_FEDERATION (3LO): a token for this user from the token vault, or a link for the user's consent
  const response = await identity.send(new GetResourceOauth2TokenCommand({
    workloadIdentityToken: await workloadToken(),
    resourceCredentialProviderName: 'calendar-provider',
    scopes: ['openid', 'calendar/read'],
    oauth2Flow: 'USER_FEDERATION',
    resourceOauth2ReturnUrl: RETURN_URL,
  }));
  // <<
  if (!response.accessToken) {
    return 'The user has not connected the corporate calendar yet. Give the user this link to sign in '
      + `and ask them to send the question again afterwards: ${response.authorizationUrl}`;
  }
  // >> Call the calendar API with the user's token, as the user
  const result = await fetch(`${CALENDAR_URL}/events`, {
    headers: { Authorization: `Bearer ${response.accessToken}` }, signal: AbortSignal.timeout(10000),
  });
  return JSON.stringify((await result.json()).events);
  // <<
}

// >> The calendar tool; registered only when `CALENDAR_URL` is set
export const calendarTools: ToolSet = CALENDAR_URL ? {
  get_calendar_events: tool({
    description: "Read the user's events from the corporate calendar: meetings, trips, and conferences with date, time, "
      + 'and location. Use it to check whether the user is free for a trip or to find the dates of an event.',
    inputSchema: z.object({}),
    execute: getCalendarEvents,
  }),
} : {};
// <<
