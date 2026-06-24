"""
Genesis Global CMS — Pytest Configuration & Shared Fixtures

Strategy:
- SQLite in-memory for fast, isolated tests (no Postgres needed)
- Enum types registered manually because SQLite does not support CREATE TYPE
- Redis and external services are fully mocked
- Each test function gets a fresh DB session that is rolled back after the test
- Tokens are created directly using create_access_token (no Supabase call)
"""
import os
import uuid
from typing import Generator
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, event, text
from sqlalchemy.orm import Session, sessionmaker

# Force test environment before any app imports.
os.environ["ENVIRONMENT"] = "test"
if not os.environ.get("DATABASE_URL"):
    os.environ["DATABASE_URL"] = "sqlite:///./test_genesis.db"
os.environ.setdefault(
    "JWT_SECRET_KEY", "test-only-jwt-secret-key-at-least-32-chars-long"
)
os.environ.setdefault("UPSTASH_REDIS_URL", "redis://localhost:6379/0")

from app.database import Base, get_db  # noqa: E402
from app.auth.models import AppUser, UserRole  # noqa: E402
from app.core.security import create_access_token  # noqa: E402

# ── SQLite Test Engine ─────────────────────────────────────────────────────────

TEST_DATABASE_URL = "sqlite:///:memory:"


def _make_engine():
    engine = create_engine(
        TEST_DATABASE_URL,
        connect_args={"check_same_thread": False},
        echo=False,
    )

    # SQLite does not enforce FK constraints by default; enable them.
    @event.listens_for(engine, "connect")
    def _set_sqlite_pragma(dbapi_conn, _):
        cursor = dbapi_conn.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()

    return engine


# Session-scoped engine; tables created once.
@pytest.fixture(scope="session")
def engine():
    eng = _make_engine()
    # Create all tables — SQLite will skip CREATE TYPE statements but we patch
    # Enum columns to use String so they work correctly.
    Base.metadata.create_all(bind=eng)
    yield eng
    with eng.begin() as conn:
        conn.execute(text("PRAGMA foreign_keys=OFF"))
        Base.metadata.drop_all(bind=conn)
        conn.execute(text("PRAGMA foreign_keys=ON"))


@pytest.fixture(scope="function")
def db(engine) -> Generator[Session, None, None]:
    """
    Yields a fresh database session per test function.
    All changes are rolled back after each test to keep tests isolated.
    """
    TestingSessionLocal = sessionmaker(
        autocommit=False,
        autoflush=False,
        bind=engine,
        expire_on_commit=False,
    )
    session = TestingSessionLocal()
    try:
        yield session
    finally:
        session.rollback()
        session.close()


# ── Application Client ─────────────────────────────────────────────────────────

@pytest.fixture(scope="function")
def client(db: Session):
    """
    Returns a TestClient with:
    - DB dependency overridden to use the test session
    - Redis mocked out (no real Redis needed)
    - Celery task queuing mocked out
    """
    # Patch Redis so token blacklist checks always pass (not blacklisted)
    # and rate limit checks always succeed.
    redis_mock = MagicMock()
    redis_mock.exists.return_value = 0  # token not blacklisted
    redis_mock.get.return_value = None
    redis_mock.incr.return_value = 1  # first attempt (within rate limit)
    redis_mock.expire.return_value = True
    redis_mock.setex.return_value = True

    pipeline_mock = MagicMock()
    pipeline_mock.__enter__.return_value = pipeline_mock
    pipeline_mock.__exit__.return_value = False
    pipeline_mock.incr.return_value = 1
    pipeline_mock.expire.return_value = True
    pipeline_mock.execute.return_value = [1, True]
    redis_mock.pipeline.return_value = pipeline_mock

    with patch("app.core.security._get_redis_client", return_value=redis_mock), \
         patch("app.workers.tasks.payment_tasks.process_webhook_payment") as mock_celery:
        mock_celery.delay = MagicMock()

        # Import create_app only after env vars are set
        from app.main import create_app

        app = create_app()
        app.dependency_overrides[get_db] = lambda: db

        with TestClient(app, raise_server_exceptions=True) as c:
            yield c

        app.dependency_overrides.clear()


# ── Token Helper ───────────────────────────────────────────────────────────────

def make_token(user_id: str, email: str, role: str, scope: dict = None) -> str:
    """Create a signed JWT access token for testing."""
    return create_access_token({
        "sub": user_id,
        "email": email,
        "role": role,
        "scope": scope or {"departments": [], "teams": [], "groups": []},
    })


def auth_headers(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


# ── User Fixtures for Every Role ───────────────────────────────────────────────

def _make_user(db: Session, email: str, role: UserRole) -> AppUser:
    user = AppUser(
        id=uuid.uuid4(),
        email=email,
        role=role,
        is_active=True,
    )
    db.add(user)
    db.flush()
    return user


@pytest.fixture
def super_admin_user(db):
    return _make_user(db, "superadmin@test.com", UserRole.SUPER_ADMIN)


@pytest.fixture
def super_admin_token(super_admin_user):
    return make_token(str(super_admin_user.id), super_admin_user.email, "SUPER_ADMIN")


@pytest.fixture
def pastor_user(db):
    return _make_user(db, "pastor@test.com", UserRole.PASTOR)


@pytest.fixture
def pastor_token(pastor_user):
    return make_token(str(pastor_user.id), pastor_user.email, "PASTOR")


@pytest.fixture
def finance_user(db):
    return _make_user(db, "finance@test.com", UserRole.FINANCE_ADMIN)


@pytest.fixture
def finance_token(finance_user):
    return make_token(str(finance_user.id), finance_user.email, "FINANCE_ADMIN")


@pytest.fixture
def hr_user(db):
    return _make_user(db, "hr@test.com", UserRole.HR_ADMIN)


@pytest.fixture
def hr_token(hr_user):
    return make_token(str(hr_user.id), hr_user.email, "HR_ADMIN")


@pytest.fixture
def department_head_user(db):
    return _make_user(db, "depthead@test.com", UserRole.DEPARTMENT_HEAD)


@pytest.fixture
def department_head_token(department_head_user):
    return make_token(
        str(department_head_user.id),
        department_head_user.email,
        "DEPARTMENT_HEAD",
    )


@pytest.fixture
def team_leader_user(db):
    return _make_user(db, "teamleader@test.com", UserRole.TEAM_LEADER)


@pytest.fixture
def team_leader_token(team_leader_user):
    return make_token(
        str(team_leader_user.id), team_leader_user.email, "TEAM_LEADER"
    )


@pytest.fixture
def group_leader_user(db):
    return _make_user(db, "groupleader@test.com", UserRole.GROUP_LEADER)


@pytest.fixture
def group_leader_token(group_leader_user):
    return make_token(
        str(group_leader_user.id), group_leader_user.email, "GROUP_LEADER"
    )


@pytest.fixture
def follow_up_user(db):
    return _make_user(db, "followup@test.com", UserRole.FOLLOW_UP)


@pytest.fixture
def follow_up_token(follow_up_user):
    return make_token(str(follow_up_user.id), follow_up_user.email, "FOLLOW_UP")


@pytest.fixture
def medical_user(db):
    return _make_user(db, "medical@test.com", UserRole.MEDICAL)


@pytest.fixture
def medical_token(medical_user):
    return make_token(str(medical_user.id), medical_user.email, "MEDICAL")


@pytest.fixture
def member_user(db):
    return _make_user(db, "member@test.com", UserRole.MEMBER)


@pytest.fixture
def member_token(member_user):
    return make_token(str(member_user.id), member_user.email, "MEMBER")
