import { createServer } from 'node:http';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { z } from 'zod';

// >> Import the expense service
import * as expenses from './expense-service.js';
// <<
import * as trips from './trip-service.js';

const json = (value: unknown) => ({ content: [{ type: 'text' as const, text: JSON.stringify(value, null, 2) }] });

function buildServer() {
  const server = new McpServer({ name: 'backoffice', version: '1.0.0' });
  server.registerTool('registerTrip', {
    description: 'Register a new business trip. Returns trip reference for tracking.',
    inputSchema: {
      userId: z.string().describe('User ID'),
      departureDate: z.string().describe('Departure date (YYYY-MM-DD)'),
      returnDate: z.string().describe('Return date (YYYY-MM-DD)'),
      origin: z.string().describe('Origin city'),
      destination: z.string().describe('Destination city'),
      purpose: z.string().describe('Trip purpose'),
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

  // >> Expense tools: same names, descriptions, and parameters as in the other backoffice languages
  server.registerTool('createExpense', {
    description: 'Create a new expense report. Optionally link to a trip.',
    inputSchema: {
      userId: z.string().describe('User ID'),
      amount: z.number().describe('Amount'),
      currency: z.string().describe('Currency code (USD, EUR, etc.)'),
      date: z.string().describe('Expense date (YYYY-MM-DD)'),
      description: z.string().describe('Description of expense'),
      type: z.string().describe('Type: FLIGHT, HOTEL, MEALS, TRANSPORT, OTHER'),
      tripReference: z.string().optional().describe('Trip reference to link (optional, TRP-XXXXXXXX)'),
    },
  }, async (a) => json(await expenses.createExpense(a.userId, a.amount, a.currency, a.date, a.description, a.type, a.tripReference)));
  // <<

  server.registerTool('getExpenses', {
    description: 'Get all expenses for a user',
    inputSchema: { userId: z.string().describe('User ID') },
  }, async ({ userId }) => json(await expenses.getExpenses(userId)));

  server.registerTool('getExpense', {
    description: 'Get expense details by reference number',
    inputSchema: { expenseReference: z.string().describe('Expense reference (EXP-XXXXXXXX)') },
  }, async ({ expenseReference }) => json(await expenses.getExpense(expenseReference)));

  server.registerTool('getExpensesForTrip', {
    description: 'Get all expenses linked to a specific trip',
    inputSchema: { tripReference: z.string().describe('Trip reference (TRP-XXXXXXXX)') },
  }, async ({ tripReference }) => json(await expenses.getExpensesForTrip(tripReference)));

  server.registerTool('submitExpense', {
    description: 'Submit a draft expense for approval',
    inputSchema: { expenseReference: z.string().describe('Expense reference (EXP-XXXXXXXX)') },
  }, async ({ expenseReference }) => json(await expenses.submitExpense(expenseReference)));

  server.registerTool('approveExpense', {
    description: 'Approve a submitted expense (managers only)',
    inputSchema: {
      expenseReference: z.string().describe('Expense reference (EXP-XXXXXXXX)'),
      approverId: z.string().describe('User ID of the approving manager'),
    },
  }, async ({ expenseReference, approverId }) => json(await expenses.approveExpense(expenseReference, approverId)));

  server.registerTool('deleteExpense', {
    description: 'Delete a draft expense',
    inputSchema: { expenseReference: z.string().describe('Expense reference (EXP-XXXXXXXX)') },
  }, async ({ expenseReference }) => json(await expenses.deleteExpense(expenseReference)));

  return server;
}
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
}).listen(8000, '0.0.0.0', () => console.log('MCP server listening on http://0.0.0.0:8000/mcp'));
