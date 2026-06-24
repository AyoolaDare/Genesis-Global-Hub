"""
Genesis Global CMS — Audit Logging Middleware

Intercepts HTTP requests and asynchronously logs audit entries to
the ``audit_logs`` table for:
  - All state-changing requests (POST, PUT, PATCH, DELETE)
  - GET requests to sensitive resource endpoints

Audit writes are non-blocking: they are submitted to a background task
after the response has been sent to the client.

Sensitive GET endpoints audited:
  /api/v1/medical/*   → MEDICAL
  /api/v1/sponsors/*  → SPONSOR
  /api/v1/members/*   → MEMBER
  /api/v1/hr/*        → HR
"""
import logging
import re
import uuid
from typing import Optional

from fastapi import Request, Response
from jose import JWTError, jwt
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.types import ASGIApp

from app.config import settings

logger = logging.getLogger(__name__)

# ── Sensitive GET Endpoint Configuration ──────────────────────────────────────

# Map of URL path prefixes to resource type strings
SENSITIVE_GET_PATTERNS: list[tuple[re.Pattern, str]] = [
    (re.compile(r"^/api/v1/medical(/|$)"), "MEDICAL"),
    (re.compile(r"^/api/v1/sponsors(/|$)"), "SPONSOR"),
    (re.compile(r"^/api/v1/members(/|$)"), "MEMBER"),
    (re.compile(r"^/api/v1/hr(/|$)"), "HR"),
]

# HTTP methods that always trigger an audit log
WRITE_METHODS = frozenset({"POST", "PUT", "PATCH", "DELETE"})

# Paths to never audit (auth endpoints, health checks, docs)
EXCLUDE_PATHS = frozenset({
    "/health",
    "/api/v1/auth/login",
    "/api/v1/auth/refresh",
    "/api/v1/auth/logout",
    "/api/v1/auth/forgot-password",
    "/api/v1/auth/reset-password",
    "/docs",
    "/redoc",
    "/openapi.json",
})

# ── Resource Type Detection ────────────────────────────────────────────────────

def _detect_resource_type(path: str, method: str) -> Optional[str]:
    """
    Derive the resource_type for an audit log entry from the request path.

    Returns None if the request should not be audited.
    """
    # Skip excluded paths
    if path in EXCLUDE_PATHS:
        return None

    # Write methods: always audit
    if method in WRITE_METHODS:
        # Derive resource from path segment
        # e.g. /api/v1/members/uuid/assignments → MEMBER
        parts = [p for p in path.split("/") if p]
        # Find "v1" and take the next segment as resource
        try:
            v1_idx = parts.index("v1")
            resource_segment = parts[v1_idx + 1].upper() if len(parts) > v1_idx + 1 else "UNKNOWN"
            return resource_segment
        except (ValueError, IndexError):
            return "UNKNOWN"

    # GET requests: only audit sensitive endpoints
    for pattern, resource_type in SENSITIVE_GET_PATTERNS:
        if pattern.match(path):
            return resource_type

    return None  # not auditable


def _extract_resource_id(path: str) -> Optional[str]:
    """
    Extract a UUID resource ID from the request path.

    Looks for the first UUID-shaped path segment.
    E.g. /api/v1/members/550e8400-e29b-41d4-a716-446655440000/attendance
         → "550e8400-e29b-41d4-a716-446655440000"
    """
    uuid_pattern = re.compile(
        r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}",
        re.IGNORECASE,
    )
    match = uuid_pattern.search(path)
    return match.group(0) if match else None


def _get_user_id_from_token(request: Request) -> Optional[uuid.UUID]:
    """
    Extract user_id from the Bearer token without re-verifying the full
    token (middleware runs AFTER auth, so we trust the state set by the
    auth dependency if available, otherwise decode directly).
    """
    # Fast path: auth dependency already set current_user on request state
    current_user = getattr(request.state, "current_user", None)
    if current_user is not None:
        return current_user.id

    # Fallback: decode token header directly (no signature check needed here
    # since middleware is for logging only; auth dependency already validated it)
    auth_header = request.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        return None

    token = auth_header[7:]
    try:
        payload = jwt.decode(
            token,
            settings.JWT_SECRET_KEY,
            algorithms=[settings.JWT_ALGORITHM],
            options={"verify_exp": False},  # already validated by auth dependency
        )
        user_id_str = payload.get("sub")
        return uuid.UUID(user_id_str) if user_id_str else None
    except (JWTError, ValueError):
        return None


def _get_client_ip(request: Request) -> Optional[str]:
    """Extract real client IP, honouring X-Forwarded-For."""
    forwarded_for = request.headers.get("X-Forwarded-For")
    if forwarded_for:
        return forwarded_for.split(",")[0].strip()
    if request.client:
        return request.client.host
    return None


# ── Middleware ─────────────────────────────────────────────────────────────────

class AuditMiddleware(BaseHTTPMiddleware):
    """
    Starlette/FastAPI middleware that writes audit log entries after each
    qualifying HTTP request completes.

    Audit writes are performed asynchronously via FastAPI's BackgroundTasks
    mechanism to avoid adding latency to the response.
    """

    def __init__(self, app: ASGIApp) -> None:
        super().__init__(app)

    async def dispatch(
        self, request: Request, call_next: RequestResponseEndpoint
    ) -> Response:
        # Let the request proceed first
        response: Response = await call_next(request)

        # Determine whether this request needs auditing
        resource_type = _detect_resource_type(request.url.path, request.method)
        if resource_type is None:
            return response

        # Skip 4xx/5xx responses for GET requests (nothing sensitive was returned)
        if request.method not in WRITE_METHODS and response.status_code >= 400:
            return response

        # Gather audit data (non-blocking — we add a background task)
        user_id = _get_user_id_from_token(request)
        resource_id = _extract_resource_id(request.url.path)
        ip_address = _get_client_ip(request)
        user_agent = request.headers.get("User-Agent")
        action = _infer_action(request.method, request.url.path)

        # Schedule audit log write as background task
        # We use add_task from the ASGI background tasks if available,
        # otherwise spawn a plain asyncio task.
        import asyncio
        asyncio.create_task(
            _write_audit_log_async(
                user_id=user_id,
                action=action,
                resource_type=resource_type,
                resource_id=resource_id,
                ip_address=ip_address,
                user_agent=user_agent,
                status_code=response.status_code,
            )
        )

        return response


def _infer_action(method: str, path: str) -> str:
    """Map HTTP method to AuditAction enum string."""
    mapping = {
        "GET": "READ",
        "POST": "CREATE",
        "PUT": "UPDATE",
        "PATCH": "UPDATE",
        "DELETE": "DELETE",
    }
    return mapping.get(method.upper(), "READ")


async def _write_audit_log_async(
    *,
    user_id: Optional[uuid.UUID],
    action: str,
    resource_type: Optional[str],
    resource_id: Optional[str],
    ip_address: Optional[str],
    user_agent: Optional[str],
    status_code: int,
) -> None:
    """
    Async function that opens a new DB session and writes one audit log row.

    Runs as a background task so it never blocks the HTTP response.
    """
    # Skip if request failed (for sensitive GETs — no data was exposed)
    if action == "READ" and status_code >= 400:
        return

    # Import here to avoid circular imports at module load time
    from app.database import get_db_context
    from app.auth.models import AuditLog, AuditAction

    try:
        audit_action = AuditAction(action)
    except ValueError:
        audit_action = AuditAction.READ

    try:
        with get_db_context() as db:
            log = AuditLog(
                user_id=user_id,
                action=audit_action,
                resource_type=resource_type,
                resource_id=resource_id,
                ip_address=ip_address,
                user_agent=user_agent,
            )
            db.add(log)
    except Exception as exc:
        # Audit failures must NEVER propagate or disrupt the application
        logger.error("Background audit log write failed: %s", exc)
