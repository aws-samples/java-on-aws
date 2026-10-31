// Extract a business trip request from an email as structured data: npx tsx extract-trip.ts EMAIL_FILE
import { readFileSync } from 'node:fs';

import { createAmazonBedrock } from '@ai-sdk/amazon-bedrock';
import { fromNodeProviderChain } from '@aws-sdk/credential-providers';
import { generateText, Output } from 'ai';
import { z } from 'zod';

// >> The schema: field names, types, and descriptions tell the model what to extract
const TripRequest = z.object({
  traveler: z.string().describe('Full name of the traveler'),
  origin: z.string().describe('Departure city'),
  destination: z.string().describe('Destination city'),
  departureDate: z.iso.date().describe('Outbound travel date'),
  returnDate: z.iso.date().describe('Return travel date'),
  purpose: z.string().describe('Purpose of the trip, such as the event'),
  travelClass: z.enum(['ECONOMY', 'PREMIUM_ECONOMY', 'BUSINESS', 'FIRST']),
  hotelPreference: z.string().nullable().describe('Hotel location or category wishes'),
  budgetEur: z.number().nullable().describe('Total trip budget in EUR'),
  approver: z.string().nullable().describe('Who approves the trip, such as the manager the email goes to'),
});
// <<

const bedrock = createAmazonBedrock({ region: process.env.AWS_REGION, credentialProvider: fromNodeProviderChain() });

// >> Today's date with the weekday (UTC), so the model can turn "the Monday two months from now" into a date
const now = new Date();
const today = `${now.toLocaleDateString('en-US', { weekday: 'long', timeZone: 'UTC' })}, ${now.toISOString().slice(0, 10)}`;
// <<

const { output } = await generateText({
  model: bedrock('global.anthropic.claude-sonnet-5-5'),
  system: `Extract the business trip request from the email. Today is ${today}.`,
  prompt: readFileSync(process.argv[2], 'utf8'),
  // >> `Output.object()` returns a validated object; `outputFormat` uses Bedrock native structured output
  output: Output.object({ schema: TripRequest }),
  providerOptions: { bedrock: { structuredOutputMode: 'outputFormat' } },
  // <<
});
console.log(JSON.stringify(output, null, 2));
