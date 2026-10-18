import { randomUUID } from 'node:crypto';

import type { FastifyInstance } from 'fastify';
import { createRemoteJWKSet, decodeJwt, jwtVerify } from 'jose';

// >> Cognito issuer from `~/environment/.envrc`; without it, all requests are allowed (local development)
const ISSUER = process.env.COGNITO_ISSUER_URI;
const jwks = ISSUER ? createRemoteJWKSet(new URL(`${ISSUER}/.well-known/jwks.json`)) : undefined;
// <<

export function requireJwt(server: FastifyInstance) {
  // >> Require a valid JWT for `/invocations`; static files and `/ping` stay public
  server.addHook('onRequest', async (request, reply) => {
    if (!jwks || request.url.split('?')[0] !== '/invocations') {
      return;
    }
    const token = (request.headers.authorization ?? '').replace(/^Bearer /, '');
    try {
      await jwtVerify(token, jwks, { issuer: ISSUER });
    } catch {
      return reply.code(401).send({ error: 'Unauthorized' });
    }
  });
  // <<
}

// Return userId:sessionId for authenticated requests, sessionId otherwise
export function conversationId(context: { sessionId: string; headers: Record<string, string> }) {
  // >> Read the session header first, fall back to a random UUID
  const sessionId = context.sessionId || randomUUID();
  // <<
  const authHeader = context.headers.authorization ?? context.headers.Authorization ?? '';
  if (authHeader.startsWith('Bearer ')) {
    try {
      // >> Extract the `sub` claim (Cognito user ID) and combine it with the session ID for per-user isolation
      const { sub } = decodeJwt(authHeader.slice(7));
      if (sub) return `${sub}:${sessionId}`;
      // <<
    } catch {
      // not a JWT: use the session ID only
    }
  }
  return sessionId;
}
