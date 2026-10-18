import { createServer } from 'node:http';

// >> `McpServer` from the MCP TypeScript SDK registers tools; the transport serves them over streamable HTTP
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
// <<
import { z } from 'zod';

import * as trips from './trip-service.js';

const json = (value: unknown) => ({ content: [{ type: 'text' as const, text: JSON.stringify(value, null, 2) }] });

function buildServer() {
  const server = new McpServer({ name: 'backoffice', version: '1.0.0' });

  // >> The tool name and description tell the model when to call the tool; the zod schema describes the parameters
  server.registerTool('registerTrip', {
    description: 'Register a new business trip. Returns trip reference for tracking.',
    inputSchema: {
  // <<
      // >> `describe()` texts guide the model on parameter extraction from user prompts
      userId: z.string().describe('User ID'),
      departureDate: z.string().describe('Departure date (YYYY-MM-DD)'),
      returnDate: z.string().describe('Return date (YYYY-MM-DD)'),
      origin: z.string().describe('Origin city'),
      destination: z.string().describe('Destination city'),
      purpose: z.string().describe('Trip purpose'),
      // <<
    },
  }, async (a) => json(await trips.registerTrip(a.userId, a.departureDate, a.returnDate, a.origin, a.destination, a.purpose)));

  server.registerTool('getTrips', {
    description: 'Get all business trips registered by a user',
    inputSchema: { userId: z.string().describe('User ID') },
  }, async ({ userId }) => json(await trips.getTrips(userId)));

  server.registerTool('getTrip', {
    description: 'Get trip details by reference number',
    inputSchema: { tripReference: z.string().describe('Trip reference (TRP-XXXXXXXX)') },
  }, async ({ tripReference }) => json(await trips.getTrip(tripReference)));

  server.registerTool('cancelTrip', {
    description: 'Cancel a planned trip',
    inputSchema: { tripReference: z.string().describe('Trip reference (TRP-XXXXXXXX)') },
  }, async ({ tripReference }) => json(await trips.cancelTrip(tripReference)));

  return server;
}

// >> Stateless streamable HTTP with JSON responses, as required by AgentCore Runtime: one server and transport per request
createServer(async (req, res) => {
  if (req.method !== 'POST' || !req.url?.startsWith('/mcp')) {
    res.writeHead(404).end();
    return;
  }
  const chunks: Buffer[] = [];
  for await (const chunk of req) chunks.push(chunk as Buffer);
  const server = buildServer();
  const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined, enableJsonResponse: true });
  res.on('close', () => { transport.close(); server.close(); });
  await server.connect(transport);
  await transport.handleRequest(req, res, JSON.parse(Buffer.concat(chunks).toString() || '{}'));
// <<
// >> Port 8000 and the `/mcp` path are required by AgentCore Runtime for MCP servers
}).listen(8000, '0.0.0.0', () => console.log('MCP server listening on http://0.0.0.0:8000/mcp'));
// <<
