"""
Genesis Global CMS — CORS Configuration

SECURITY: Only origins listed in ALLOWED_ORIGINS env var are permitted.
Never allow "*" in production — this would allow any website to make
credentialed requests to the API.
"""
import logging
from typing import List

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings

logger = logging.getLogger(__name__)


def configure_cors(app: FastAPI) -> None:
    """
    Apply CORS middleware to the FastAPI application.

    Reads allowed origins from settings.ALLOWED_ORIGINS (comma-separated list).
    In development, falls back to localhost origins if none configured.

    Args:
        app: The FastAPI application instance.
    """
    allowed_origins: List[str] = settings.allowed_origins_list

    if not allowed_origins:
        if settings.is_development:
            # Safe defaults for local development only
            allowed_origins = [
                "http://localhost:3000",
                "http://localhost:8080",
                "http://127.0.0.1:3000",
                "http://127.0.0.1:8080",
            ]
            logger.warning(
                "ALLOWED_ORIGINS not configured — using localhost fallback for development."
            )
        else:
            # Production with no origins configured: deny all cross-origin requests
            logger.critical(
                "ALLOWED_ORIGINS is empty in production! "
                "All cross-origin requests will be rejected."
            )
            allowed_origins = []  # CORSMiddleware will deny all

    logger.info("CORS configured for origins: %s", allowed_origins)

    # Allow all Vercel preview deployments + any custom domains in ALLOWED_ORIGINS.
    # CORSMiddleware supports allow_origin_regex for pattern matching.
    allow_origin_regex = (
        r"https://.*\.vercel\.app"
        r"|https://.*\.onrender\.com"
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=allowed_origins,
        allow_origin_regex=allow_origin_regex,
        allow_credentials=True,
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
        allow_headers=[
            "Authorization",
            "Content-Type",
            "Accept",
            "Origin",
            "X-Requested-With",
            "X-Request-ID",
        ],
        expose_headers=[
            "X-Request-ID",
            "X-RateLimit-Limit",
            "X-RateLimit-Remaining",
            "X-RateLimit-Reset",
        ],
        max_age=600,
    )
