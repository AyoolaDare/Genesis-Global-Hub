"""
Genesis Global CMS — Rate Limiting Middleware

Implements a sliding window rate limiter using Upstash Redis.
Applies a global request rate limit to protect the API from abuse.

Per-endpoint rate limiting (e.g., auth endpoints) is enforced separately
in core/security.py via check_auth_rate_limit().

Global limits:
  - General endpoints: 200 requests / 60 seconds per IP
  - Auth endpoints: handled by core/security.py (5 / 15 min)

Rate limit headers are included in all responses:
  X-RateLimit-Limit:     Max requests in the window
  X-RateLimit-Remaining: Remaining requests
  X-RateLimit-Reset:     Unix timestamp when the window resets
"""
import logging
import time
from typing import Optional

import redis as redis_lib
from fastapi import Request, Response
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.types import ASGIApp

from app.config import settings
from app.core.responses import error_response

logger = logging.getLogger(__name__)

# ── Configuration ──────────────────────────────────────────────────────────────

GLOBAL_RATE_LIMIT = 200          # requests
GLOBAL_RATE_WINDOW = 60          # seconds
AUTH_RATE_LIMIT = 5              # requests
AUTH_RATE_WINDOW = 900           # 15 minutes (900 seconds)

# Endpoints with stricter per-endpoint limits (enforced here as well)
AUTH_PATHS = frozenset({
    "/api/v1/auth/login",
    "/api/v1/auth/forgot-password",
    "/api/v1/auth/reset-password",
})


# ── Redis Client ───────────────────────────────────────────────────────────────

def _get_redis() -> redis_lib.Redis:
    return redis_lib.from_url(
        settings.UPSTASH_REDIS_URL,
        decode_responses=True,
        socket_connect_timeout=2,
        socket_timeout=2,
    )


def _get_client_ip(request: Request) -> str:
    """Extract real client IP, honouring reverse-proxy headers."""
    forwarded_for = request.headers.get("X-Forwarded-For")
    if forwarded_for:
        return forwarded_for.split(",")[0].strip()
    if request.client:
        return request.client.host
    return "unknown"


# ── Sliding Window Counter ─────────────────────────────────────────────────────

def _check_rate_limit(
    key: str,
    limit: int,
    window: int,
) -> tuple[bool, int, int, int]:
    """
    Sliding window rate limit check using Redis INCR + EXPIRE.

    Returns:
        (allowed, count, limit, reset_timestamp)
        allowed: True if request is within the limit.
        count:   Current request count in the window.
        limit:   The configured maximum.
        reset_ts: Unix timestamp when the window resets.
    """
    reset_ts = int(time.time()) + window

    try:
        r = _get_redis()
        pipe = r.pipeline()
        pipe.incr(key)
        pipe.ttl(key)
        results = pipe.execute()

        count = results[0]
        ttl = results[1]

        # Set expiry on first request in this window
        if ttl == -1:
            r.expire(key, window)
            reset_ts = int(time.time()) + window
        elif ttl > 0:
            reset_ts = int(time.time()) + ttl

        allowed = count <= limit
        return allowed, count, limit, reset_ts

    except Exception as exc:
        logger.warning("Rate limit Redis check failed (failing open): %s", exc)
        # Fail open to avoid blocking all requests when Redis is down
        return True, 0, limit, reset_ts


# ── Middleware ─────────────────────────────────────────────────────────────────

class RateLimitMiddleware(BaseHTTPMiddleware):
    """
    Global sliding-window rate limiter.

    Applies:
      - AUTH_RATE_LIMIT to auth-related endpoints
      - GLOBAL_RATE_LIMIT to all other endpoints
    """

    def __init__(self, app: ASGIApp) -> None:
        super().__init__(app)

    async def dispatch(
        self, request: Request, call_next: RequestResponseEndpoint
    ) -> Response:
        ip = _get_client_ip(request)
        path = request.url.path

        # Skip rate limiting for health checks and OPTIONS preflight
        if path == "/health" or request.method == "OPTIONS":
            return await call_next(request)

        # Choose limit tier
        if path in AUTH_PATHS:
            limit = AUTH_RATE_LIMIT
            window = AUTH_RATE_WINDOW
            key = f"rl:auth:{ip}"
        else:
            limit = GLOBAL_RATE_LIMIT
            window = GLOBAL_RATE_WINDOW
            key = f"rl:global:{ip}"

        allowed, count, max_limit, reset_ts = _check_rate_limit(key, limit, window)
        remaining = max(0, max_limit - count)

        if not allowed:
            logger.warning("Rate limit exceeded for IP %s on path %s", ip, path)
            response_body = error_response(
                code="RATE_LIMIT_EXCEEDED",
                message="Too many requests. Please slow down and try again later.",
                details={"retry_after": reset_ts - int(time.time())},
            )
            return JSONResponse(
                status_code=429,
                content=response_body,
                headers={
                    "X-RateLimit-Limit": str(max_limit),
                    "X-RateLimit-Remaining": "0",
                    "X-RateLimit-Reset": str(reset_ts),
                    "Retry-After": str(reset_ts - int(time.time())),
                },
            )

        response: Response = await call_next(request)

        # Inject rate limit headers into every successful response
        response.headers["X-RateLimit-Limit"] = str(max_limit)
        response.headers["X-RateLimit-Remaining"] = str(remaining)
        response.headers["X-RateLimit-Reset"] = str(reset_ts)

        return response
