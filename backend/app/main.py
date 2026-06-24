"""
Genesis Global CMS — FastAPI Application Entry Point

Wires together:
  - Application settings
  - CORS middleware
  - Rate limiting middleware
  - Audit logging middleware
  - Auth router
  - Global exception handlers
  - Health check endpoint
"""
import logging
import traceback
import uuid
from contextlib import asynccontextmanager
from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from app.auth.router import router as auth_router
from app.routers.attendance import router as attendance_router
from app.routers.follow_up import router as follow_up_router
from app.routers.hr import router as hr_router
from app.routers.kpi import router as kpi_router
from app.routers.medical import router as medical_router
from app.routers.members import router as members_router
from app.routers.sponsors import router as sponsors_router
from app.routers.structure import router as structure_router
from app.routers.webhooks import router as webhooks_router
from app.config import settings
from app.core.exceptions import GenesisException
from app.core.responses import error_response
from app.database import check_db_connection
from app.middleware.audit import AuditMiddleware
from app.middleware.cors import configure_cors
from app.middleware.rate_limit import RateLimitMiddleware

# ── Logging Configuration ──────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.DEBUG if settings.is_development else logging.INFO,
    format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)
logger = logging.getLogger(__name__)


# ── Lifespan ───────────────────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup and shutdown lifecycle hooks."""
    logger.info("Starting %s v%s in %s mode", settings.APP_NAME, settings.APP_VERSION, settings.ENVIRONMENT)

    # Verify database connectivity on startup
    if check_db_connection():
        logger.info("Database connection: OK")
    else:
        logger.critical("Database connection FAILED — check DATABASE_URL")

    yield  # Application runs here

    logger.info("Shutting down %s", settings.APP_NAME)


# ── Application Factory ────────────────────────────────────────────────────────

def create_app() -> FastAPI:
    """Create and configure the FastAPI application."""

    # Disable API docs in production for security
    docs_url = "/docs" if settings.is_development else None
    redoc_url = "/redoc" if settings.is_development else None
    openapi_url = "/openapi.json" if settings.is_development else None

    app = FastAPI(
        title=settings.APP_NAME,
        version=settings.APP_VERSION,
        description="Genesis Global Church Management System API",
        docs_url=docs_url,
        redoc_url=redoc_url,
        openapi_url=openapi_url,
        lifespan=lifespan,
    )

    # ── Middleware (order matters: outermost wraps all inner) ──────────────────
    # 1. CORS must be first so preflight OPTIONS requests are handled correctly
    configure_cors(app)

    # 2. Rate limiting — before routing so abusive IPs are stopped early
    if settings.ENVIRONMENT != "test":
        app.add_middleware(RateLimitMiddleware)

    # 3. Audit logging — after auth middleware sets request.state.current_user
    app.add_middleware(AuditMiddleware)

    # ── Exception Handlers ─────────────────────────────────────────────────────
    _register_exception_handlers(app)

    # ── Routers ───────────────────────────────────────────────────────────────
    app.include_router(auth_router, prefix="/api/v1")
    app.include_router(members_router, prefix="/api/v1")
    app.include_router(medical_router, prefix="/api/v1")
    app.include_router(sponsors_router, prefix="/api/v1")
    app.include_router(hr_router, prefix="/api/v1")
    app.include_router(follow_up_router, prefix="/api/v1")
    app.include_router(structure_router, prefix="/api/v1")
    app.include_router(attendance_router, prefix="/api/v1")
    app.include_router(kpi_router, prefix="/api/v1")
    app.include_router(webhooks_router)  # prefix="/api/v1/webhooks" defined in router

    # ── Built-in Endpoints ────────────────────────────────────────────────────
    @app.get("/health", tags=["System"], summary="Health check")
    async def health_check():
        """Returns service health status. Does not require authentication."""
        db_ok = check_db_connection()
        return {
            "status": "ok" if db_ok else "degraded",
            "version": settings.APP_VERSION,
            "environment": settings.ENVIRONMENT,
            "database": "ok" if db_ok else "error",
        }

    return app


# ── Exception Handlers ─────────────────────────────────────────────────────────

def _register_exception_handlers(app: FastAPI) -> None:
    """Register all global exception handlers."""

    @app.exception_handler(GenesisException)
    async def genesis_exception_handler(
        request: Request, exc: GenesisException
    ) -> JSONResponse:
        """Handle all domain exceptions — log internally, return clean response."""
        request_id = str(uuid.uuid4())[:8]

        # Log at appropriate level
        if exc.status_code >= 500:
            logger.error(
                "[%s] %s: %s\n%s",
                request_id,
                type(exc).__name__,
                exc.message,
                traceback.format_exc(),
            )
        else:
            logger.warning(
                "[%s] %s: %s",
                request_id,
                type(exc).__name__,
                exc.message,
            )

        return JSONResponse(
            status_code=exc.status_code,
            content=error_response(
                code=exc.error_code,
                message=exc.message,
                details=exc.details,
            ),
        )

    @app.exception_handler(RequestValidationError)
    async def validation_exception_handler(
        request: Request, exc: RequestValidationError
    ) -> JSONResponse:
        """Handle Pydantic v2 request validation errors with structured details."""
        # Format Pydantic errors into a clean list
        field_errors = []
        for error in exc.errors():
            location = " -> ".join(str(loc) for loc in error.get("loc", []))
            field_errors.append({
                "field": location,
                "message": error.get("msg", "Validation error"),
                "type": error.get("type", ""),
            })

        logger.debug("Request validation failed: %s", field_errors)

        return JSONResponse(
            status_code=422,
            content=error_response(
                code="VALIDATION_ERROR",
                message="The request data is invalid. Please check the provided fields.",
                details=field_errors,
            ),
        )

    @app.exception_handler(404)
    async def not_found_handler(request: Request, exc: Any) -> JSONResponse:
        return JSONResponse(
            status_code=404,
            content=error_response(
                code="NOT_FOUND",
                message=f"The requested endpoint '{request.url.path}' does not exist.",
            ),
        )

    @app.exception_handler(405)
    async def method_not_allowed_handler(request: Request, exc: Any) -> JSONResponse:
        return JSONResponse(
            status_code=405,
            content=error_response(
                code="METHOD_NOT_ALLOWED",
                message=f"HTTP method '{request.method}' is not allowed for '{request.url.path}'.",
            ),
        )

    @app.exception_handler(Exception)
    async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
        """
        Catch-all for unhandled exceptions.
        NEVER exposes stack trace or internal details to the client.
        """
        request_id = str(uuid.uuid4())[:8]
        logger.critical(
            "[%s] Unhandled exception on %s %s:\n%s",
            request_id,
            request.method,
            request.url.path,
            traceback.format_exc(),
        )
        return JSONResponse(
            status_code=500,
            content=error_response(
                code="INTERNAL_ERROR",
                message="An unexpected error occurred. Our team has been notified.",
                details={"request_id": request_id},
            ),
        )


# ── Application Instance ───────────────────────────────────────────────────────

app = create_app()


# ── Entry Point (for direct execution) ────────────────────────────────────────

if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=8000,
        reload=settings.is_development,
        log_level="debug" if settings.is_development else "info",
    )
