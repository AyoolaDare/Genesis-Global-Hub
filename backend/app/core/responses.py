"""
Genesis Global CMS — Standard Response Helpers

All API responses follow a consistent envelope:
  Success:  {"success": true,  "data": ..., "meta": ..., "message": "..."}
  Error:    {"success": false, "error": {"code": "...", "message": "...", "details": ...}}
"""
from typing import Any, Optional


def success_response(
    data: Any = None,
    message: str = "Success",
    meta: Optional[dict] = None,
) -> dict:
    """
    Wrap a successful payload in the standard Genesis envelope.

    Args:
        data:    The primary response payload (any JSON-serialisable value).
        message: Human-readable success message.
        meta:    Optional metadata (e.g., pagination info).

    Returns:
        Standardised response dict.
    """
    return {
        "success": True,
        "data": data,
        "meta": meta,
        "message": message,
    }


def error_response(
    code: str,
    message: str,
    details: Any = None,
) -> dict:
    """
    Wrap an error in the standard Genesis error envelope.

    Args:
        code:    UPPER_SNAKE_CASE error code (e.g., "PERMISSION_DENIED").
        message: Human-readable error description.
        details: Optional structured detail payload (list of field errors, etc.).

    Returns:
        Standardised error dict.
    """
    return {
        "success": False,
        "error": {
            "code": code,
            "message": message,
            "details": details,
        },
    }


def paginated_response(
    data: list,
    total: int,
    page: int,
    per_page: int,
    message: str = "Success",
) -> dict:
    """
    Wrap a paginated list in the standard Genesis envelope with pagination meta.

    Args:
        data:     List of items for the current page.
        total:    Total number of matching records across all pages.
        page:     Current page number (1-based).
        per_page: Number of items per page.
        message:  Human-readable success message.

    Returns:
        Standardised paginated response dict.
    """
    total_pages = max(1, (total + per_page - 1) // per_page)

    return {
        "success": True,
        "data": data,
        "meta": {
            "page": page,
            "per_page": per_page,
            "total": total,
            "total_pages": total_pages,
            "has_next": page < total_pages,
            "has_prev": page > 1,
        },
        "message": message,
    }
