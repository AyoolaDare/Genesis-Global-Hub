"""
Genesis Global CMS - SQLAlchemy ORM models for the auth domain.

These map to the Supabase PostgreSQL schema. Database migrations live in the
database folder; these classes are the ORM layer used by the API.
"""
import enum
import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import Boolean, DateTime, Enum, ForeignKey, String, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import JSON, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.sql import func

from app.database import Base
from app.models.member import MemberModel


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


class AppUser(Base):
    """Maps to app_users; id matches Supabase auth.users.id."""

    __tablename__ = "app_users"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        comment="Matches auth.users.id from Supabase Auth",
    )
    email: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
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

    member: Mapped[Optional[MemberModel]] = relationship(
        MemberModel,
        foreign_keys=[member_id],
        lazy="select",
    )
    audit_logs: Mapped[list["AuditLog"]] = relationship(
        "AuditLog",
        back_populates="user",
        lazy="dynamic",
    )

    __table_args__ = (UniqueConstraint("email", name="uq_app_users_email"),)

    def __repr__(self) -> str:
        return f"<AppUser id={self.id} email={self.email} role={self.role}>"


class AuditLog(Base):
    """Maps to audit_logs, an append-only audit table."""

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

    user: Mapped[Optional[AppUser]] = relationship(
        AppUser,
        back_populates="audit_logs",
        foreign_keys=[user_id],
    )

    def __repr__(self) -> str:
        return f"<AuditLog id={self.id} action={self.action} user_id={self.user_id}>"
