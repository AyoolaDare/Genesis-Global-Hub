"""
Genesis Global CMS — SQLAlchemy ORM Models for Auth Domain

Maps to the existing Supabase PostgreSQL schema created by the
DatabaseArchitect. DO NOT run migrations from here — the schema
already exists. These models are read-only mirrors for the ORM layer.
"""
import enum
import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import (
    Boolean,
    DateTime,
    Enum,
    ForeignKey,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import JSON, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.sql import func

from app.database import Base


# ── Enums (must match PostgreSQL enum definitions exactly) ─────────────────────

class UserRole(str, enum.Enum):
    SUPER_ADMIN = "SUPER_ADMIN"
    PASTOR = "PASTOR"
    FINANCE_ADMIN = "FINANCE_ADMIN"
    HR_ADMIN = "HR_ADMIN"
    DEPARTMENT_HEAD = "DEPARTMENT_HEAD"
    TEAM_LEADER = "TEAM_LEADER"
    GROUP_LEADER = "GROUP_LEADER"
    FOLLOW_UP = "FOLLOW_UP"
    MEDICAL = "MEDICAL"
    MEMBER = "MEMBER"


class AuditAction(str, enum.Enum):
    CREATE = "CREATE"
    READ = "READ"
    UPDATE = "UPDATE"
    DELETE = "DELETE"
    LOGIN = "LOGIN"
    LOGOUT = "LOGOUT"
    APPROVE = "APPROVE"
    REJECT = "REJECT"
    MERGE = "MERGE"
    VIEW_SENSITIVE = "VIEW_SENSITIVE"


class MemberStatus(str, enum.Enum):
    ACTIVE = "ACTIVE"
    INACTIVE = "INACTIVE"
    PENDING = "PENDING"
    PENDING_DUPLICATE_CHECK = "PENDING_DUPLICATE_CHECK"
    PENDING_INFO_REQUESTED = "PENDING_INFO_REQUESTED"
    REJECTED = "REJECTED"
    MERGED = "MERGED"


# ── AppUser ────────────────────────────────────────────────────────────────────

class AppUser(Base):
    """
    Maps to ``app_users`` table.
    References Supabase ``auth.users`` via the ``id`` column (same UUID).
    """

    __tablename__ = "app_users"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        comment="Matches auth.users.id from Supabase Auth",
    )
    email: Mapped[str] = mapped_column(
        String(255),
        nullable=False,
        index=True,
    )
    role: Mapped[UserRole] = mapped_column(
        Enum(UserRole, name="user_role", create_type=False),
        nullable=False,
        default=UserRole.MEMBER,
    )
    member_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("members.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    is_active: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=True,
        server_default="true",
    )
    last_login_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )

    # Relationships
    member: Mapped[Optional["MemberModel"]] = relationship(
        "MemberModel",
        foreign_keys=[member_id],
        lazy="select",
    )
    audit_logs: Mapped[list["AuditLog"]] = relationship(
        "AuditLog",
        back_populates="user",
        lazy="dynamic",
    )

    __table_args__ = (
        UniqueConstraint("email", name="uq_app_users_email"),
    )

    def __repr__(self) -> str:
        return f"<AppUser id={self.id} email={self.email} role={self.role}>"


# ── Member (partial — for FK resolution only) ─────────────────────────────────

class Member(Base):
    """
    Partial mapping of ``members`` table — only columns needed for auth.
    Full member model lives in the members domain module.
    """

    __tablename__ = "members"
    __table_args__ = {"extend_existing": True}

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True)
    full_name: Mapped[str] = mapped_column(String(255), nullable=False)
    email: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    phone: Mapped[Optional[str]] = mapped_column(String(20), nullable=True)
    membership_status: Mapped[MemberStatus] = mapped_column(
        Enum(MemberStatus, name="member_status", create_type=False),
        nullable=False,
        default=MemberStatus.PENDING,
    )
    deleted_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    # Reverse relationship
    app_user: Mapped[Optional["AppUser"]] = relationship(
        "AppUser",
        back_populates="member",
        foreign_keys="AppUser.member_id",
        uselist=False,
    )

    def __repr__(self) -> str:
        return f"<Member id={self.id} name={self.full_name}>"


# ── AuditLog ───────────────────────────────────────────────────────────────────

class AuditLog(Base):
    """
    Maps to ``audit_logs`` — append-only table (DB triggers block UPDATE/DELETE).
    """

    __tablename__ = "audit_logs"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
    )
    user_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("app_users.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    action: Mapped[AuditAction] = mapped_column(
        Enum(AuditAction, name="audit_action", create_type=False),
        nullable=False,
    )
    resource_type: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    resource_id: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    old_values: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)
    new_values: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)
    ip_address: Mapped[Optional[str]] = mapped_column(String(45), nullable=True)
    user_agent: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        index=True,
    )

    # Relationship
    user: Mapped[Optional["AppUser"]] = relationship(
        "AppUser",
        back_populates="audit_logs",
        foreign_keys=[user_id],
    )

    def __repr__(self) -> str:
        return f"<AuditLog id={self.id} action={self.action} user_id={self.user_id}>"
