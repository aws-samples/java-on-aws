import os
import uuid

import jwt
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import JSONResponse

# >> Cognito issuer from `~/environment/.envrc`; without it, all requests are allowed (local development)
ISSUER = os.environ.get("COGNITO_ISSUER_URI")
jwks = jwt.PyJWKClient(f"{ISSUER}/.well-known/jwks.json") if ISSUER else None
# <<


class JwtAuthMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        # >> Require a valid JWT for `/invocations`; static files and `/ping` stay public
        if jwks and request.url.path == "/invocations":
            token = request.headers.get("authorization", "").removeprefix("Bearer ")
            try:
                key = jwks.get_signing_key_from_jwt(token)
                jwt.decode(token, key.key, algorithms=["RS256"], issuer=ISSUER, options={"verify_aud": False})
            except jwt.PyJWTError:
                return JSONResponse({"error": "Unauthorized"}, status_code=401)
        # <<
        return await call_next(request)


def conversation_id(context):
    """Return userId:sessionId for authenticated requests, sessionId otherwise."""
    # >> Read the session header first, fall back to a random UUID
    session_id = context.session_id or str(uuid.uuid4())
    # <<
    auth_header = (context.request_headers or {}).get("Authorization", "")
    if auth_header.startswith("Bearer "):
        try:
            # >> Extract the `sub` claim (Cognito user ID) and combine it with the session ID for per-user isolation
            claims = jwt.decode(auth_header[7:], options={"verify_signature": False})
            return f"{claims['sub']}:{session_id}"
            # <<
        except (jwt.PyJWTError, KeyError):
            pass
    return session_id
