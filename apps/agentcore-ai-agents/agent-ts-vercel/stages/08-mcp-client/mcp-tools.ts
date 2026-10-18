import { Sha256 } from '@aws-crypto/sha256-js';
import { createMCPClient } from '@ai-sdk/mcp';
import { fromNodeProviderChain } from '@aws-sdk/credential-providers';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import { SignatureV4 } from '@smithy/signature-v4';

// >> SigV4 signer for the `bedrock-agentcore` service, using the IAM credentials of the application
const signer = new SignatureV4({
  service: 'bedrock-agentcore', region: process.env.AWS_REGION!, credentials: fromNodeProviderChain(), sha256: Sha256,
});
// <<

// >> A `fetch` that signs every request to the Gateway; the MCP transport sends all requests through it
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
// <<

export async function gatewayTools() {
  // >> Gateway URL from `~/environment/.envrc`; without it, the agent runs without Gateway tools
  const url = process.env.GATEWAY_URL;
  if (!url) {
    return {};
  }
  // <<
  // >> The MCP client discovers the Gateway tools with `tools/list` and converts them to AI SDK tools
  const client = await createMCPClient({ transport: new StreamableHTTPClientTransport(new URL(url), { fetch: signedFetch }) });
  return client.tools();
  // <<
}
