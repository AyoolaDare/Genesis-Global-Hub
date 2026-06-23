"""
Genesis Global CMS — Database Engine & Session Management
Uses SQLAlchemy with psycopg2 driver connecting to Supabase PostgreSQL.
"""
import logging
from contextlib import contextmanager
from typing import Generator

from sqlalchemy import create_engine, event, text
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app.config import settings

logger = logging.getLogger(__name__)

# ── Engine ─────────────────────────────────────────────────────────────────────
engine = create_engine(
    settings.DATABASE_URL,
    pool_pre_ping=True,          # verify connections before use
    pool_size=10,
    max_overflow=20,
    pool_timeout=30,
    pool_recycle=1800,           # recycle connections every 30 min
    echo=settings.is_development,  # only log SQL in dev
    connect_args={
        "connect_timeout": 10,
        "options": "-c timezone=UTC",
    },
)


@event.listens_for(engine, "connect")
def set_search_path(dbapi_connection, connection_record):  # noqa: ARG001
    """Ensure every connection uses the public schema."""
    cursor = dbapi_connection.cursor()
    cursor.execute("SET search_path TO public")
    cursor.close()


# ── Session Factory ────────────────────────────────────────────────────────────
SessionLocal = sessionmaker(
    autocommit=False,
    autoflush=False,
    bind=engine,
    expire_on_commit=False,
)


# ── Declarative Base ───────────────────────────────────────────────────────────
class Base(DeclarativeBase):
    pass


# ── Dependency ─────────────────────────────────────────────────────────────────
def get_db() -> Generator[Session, None, None]:
    """
    FastAPI dependency that yields a database session and closes it after use.
    Usage: db: Session = Depends(get_db)
    """
    db = SessionLocal()
    try:
        yield db
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


@contextmanager
def get_db_context() -> Generator[Session, None, None]:
    """Context manager for use outside FastAPI dependency injection."""
    db = SessionLocal()
    try:
        yield db
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def check_db_connection() -> bool:
    """Health check: verify database is reachable."""
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        return True
    except Exception as exc:
        logger.error("Database health check failed: %s", exc)
        return False
