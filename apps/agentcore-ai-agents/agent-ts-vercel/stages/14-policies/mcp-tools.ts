import { Sha256 } from '@aws-crypto/sha256-js';
import { createMCPClient } from '@ai-sdk/mcp';
import { fromNodeProviderChain } from '@aws-sdk/credential-providers';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import { SignatureV4 } from '@smithy/signature-v4';

const BACKOFFICE = /^backoffice___/;

const signer = new SignatureV4({
  service: 'bedrock-agentcore', region: process.env.AWS_REGION!, credentials: fromNodeProviderChain(), sha256: Sha256,
});

async function signedFetch(input: string | URL | Request, init: RequestInit = {}): Promise<Response> {
  const url = new URL(input instanceof Request ? input.url : input.toString());
  const signed = await signer.sign({
    method: init.method ?? 'GET',
    protocol: url.protocol,
    hostname: url.hostname,
    path: url.pathname,
    query: Object.fromEntries(url.searchParams),
    headers: { ...Object.fromEntries(new Headers(init.headers).entries()), host: url.hostname },
    body: init.body as string | undefined,
  });
  return fetch(url, { ...init, headers: signed.headers });
}

// Keep the tools whose names match (or, with `keep = false`, do not match) the pattern
function filterTools<T extends Record<string, unknown>>(tools: T, pattern: RegExp, keep: boolean) {
  return Object.fromEntries(Object.entries(tools).filter(([name]) => pattern.test(name) === keep)) as T;
}

export async function gatewayTools() {
  const url = process.env.GATEWAY_URL;
  if (!url) {
    return {};
  }
  const client = await createMCPClient({ transport: new StreamableHTTPClientTransport(new URL(url), { fetch: signedFetch }) });
  // >> With the JWT Gateway, the backoffice tools come from there; the IAM Gateway keeps the other tools
  const tools = await client.tools();
  return process.env.JWT_GATEWAY_URL ? filterTools(tools, BACKOFFICE, false) : tools;
  // <<
}

async function listUserTools(url: string, authorization: string) {
  // >> The Gateway validates the user's Cognito token and hides the tools that the user's policies forbid
  const transport = new StreamableHTTPClientTransport(new URL(url), { requestInit: { headers: { Authorization: authorization } } });
  const client = await createMCPClient({ transport });
  return filterTools(await client.tools(), BACKOFFICE, true);
  // <<
}

// The backoffice tools of the JWT Gateway per `Authorization` header, listed once per token
const userTools = new Map<string, ReturnType<typeof listUserTools>>();

// Backoffice tools from the JWT Gateway, called with the user's token, so that policies see the user's claims
export async function userGatewayTools(authorization: string) {
  const url = process.env.JWT_GATEWAY_URL;
  if (!url || !authorization.startsWith('Bearer ')) {
    return {};
  }
  if (!userTools.has(authorization)) {
    userTools.set(authorization, listUserTools(url, authorization));
  }
  try {
    return await userTools.get(authorization)!;
  } catch (error) {
    userTools.delete(authorization);
    throw error;
  }
}
