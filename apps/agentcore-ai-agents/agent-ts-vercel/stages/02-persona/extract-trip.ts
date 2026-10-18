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
  purpose: z.string().describe('Purpose of the trip, e.g. the event name'),
  travelClass: z.enum(['ECONOMY', 'PREMIUM_ECONOMY', 'BUSINESS', 'FIRST']),
  hotelPreference: z.string().nullable().describe('Hotel location or category wishes'),
  budgetEur: z.number().nullable().describe('Total trip budget in EUR'),
  approver: z.string().nullable().describe('Who approved the trip or budget'),
});
// <<

const bedrock = createAmazonBedrock({ region: process.env.AWS_REGION, credentialProvider: fromNodeProviderChain() });

const { output } = await generateText({
  model: bedrock('global.anthropic.claude-sonnet-4-6'),
  system: 'Extract the business trip request from the email.',
  prompt: readFileSync(process.argv[2], 'utf8'),
  // >> `temperature: 0` keeps the extraction stable between runs
  temperature: 0,
  // <<
  // >> `Output.object()` returns a validated object; `outputFormat` uses Bedrock native structured output
  output: Output.object({ schema: TripRequest }),
  providerOptions: { bedrock: { structuredOutputMode: 'outputFormat' } },
  // <<
});
console.log(JSON.stringify(output, null, 2));
