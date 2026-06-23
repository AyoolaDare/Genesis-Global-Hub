"""
Genesis Global CMS — Custom Exception Hierarchy

All domain exceptions inherit from GenesisException.
The FastAPI exception handlers in main.py translate these to
structured JSON error responses without leaking stack traces.
"""
from typing import Any, Optional


class GenesisException(Exception):
    """Base exception for all Genesis Global CMS errors."""

    status_code: int = 500
    error_code: str = "INTERNAL_ERROR"
    default_message: str = "An unexpected error occurred."

    def __init__(
        self,
        message: Optional[str] = None,
        details: Optional[Any] = None,
        *,
        error_code: Optional[str] = None,
    ) -> None:
        self.message = message or self.default_message
        self.details = details
        if error_code:
            self.error_code = error_code
        super().__init__(self.message)


class AuthenticationFailed(GenesisException):
    """
    Raised when the provided credentials are invalid or the token is
    missing / expired. Maps to HTTP 401.
    """

    status_code = 401
    error_code = "AUTHENTICATION_FAILED"
    default_message = "Authentication failed. Please check your credentials."


class TokenExpired(AuthenticationFailed):
    error_code = "TOKEN_EXPIRED"
    default_message = "Your session has expired. Please log in again."


class TokenInvalid(AuthenticationFailed):
    error_code = "TOKEN_INVALID"
    default_message = "The provided token is invalid."


class TokenBlacklisted(AuthenticationFailed):
    error_code = "TOKEN_BLACKLISTED"
    default_message = "This token has been revoked. Please log in again."


class PermissionDenied(GenesisException):
    """
    Raised when an authenticated user attempts an action outside their
    role or scope. Maps to HTTP 403 — NOT 401.
    """

    status_code = 403
    error_code = "PERMISSION_DENIED"
    default_message = "You do not have permission to perform this action."


class ScopeViolation(PermissionDenied):
    """User is authenticated but accessing an entity outside their scope."""

    error_code = "SCOPE_VIOLATION"
    default_message = "Access denied. This resource is outside your authorized scope."


class NotFound(GenesisException):
    """Raised when a requested resource does not exist. Maps to HTTP 404."""

    status_code = 404
    error_code = "NOT_FOUND"
    default_message = "The requested resource was not found."


class DuplicateRecord(GenesisException):
    """
    Raised when an insert would violate a uniqueness constraint.
    Maps to HTTP 409 Conflict.
    """

    status_code = 409
    error_code = "DUPLICATE_RECORD"
    default_message = "A record with the same identifier already exists."


class ValidationError(GenesisException):
    """
    Raised for domain-level validation failures (not Pydantic schema
    failures — those are handled by FastAPI automatically).
    Maps to HTTP 422 Unprocessable Entity.
    """

    status_code = 422
    error_code = "VALIDATION_ERROR"
    default_message = "The provided data is invalid."


class RateLimitExceeded(GenesisException):
    """Raised when a client exceeds the configured rate limit. HTTP 429."""

    status_code = 429
    error_code = "RATE_LIMIT_EXCEEDED"
    default_message = "Too many requests. Please wait before trying again."


class ServiceUnavailable(GenesisException):
    """Raised when a downstream service (Supabase, Redis, etc.) is down. HTTP 503."""

    status_code = 503
    error_code = "SERVICE_UNAVAILABLE"
    default_message = "A required service is temporarily unavailable."


class AccountInactive(AuthenticationFailed):
    """Raised when the user account has been deactivated."""

    error_code = "ACCOUNT_INACTIVE"
    default_message = "Your account has been deactivated. Contact an administrator."
