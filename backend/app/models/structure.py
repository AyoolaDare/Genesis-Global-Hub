"""
Genesis Global CMS — SQLAlchemy Models: Structure Domain

Covers:
  - Department      → departments table
  - Team            → teams table
  - Group           → groups table
  - MemberAssignment → member_assignments table
"""
import enum
import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import (
    DateTime,
    Enum,
    ForeignKey,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.sql import func

from app.database import Base


class AssignmentTypeEnum(str, enum.Enum):
    DEPARTMENT = "DEPARTMENT"
    TEAM = "TEAM"
    GROUP = "GROUP"


# ── Department ─────────────────────────────────────────────────────────────────

class Department(Base):
    """Maps to ``departments`` table."""

    __tablename__ = "departments"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(255), nullable=False, unique=True)
    description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    head_user_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("app_users.id", ondelete="SET NULL"),
        nullable=True,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now()
    )
    deleted_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)

    # Relationships
    teams: Mapped[list["Team"]] = relationship(
        "Team",
        back_populates="department",
        primaryjoin="and_(Team.department_id == Department.id, Team.deleted_at == None)",
        lazy="select",
    )
    groups: Mapped[list["Group"]] = relationship(
        "Group",
        back_populates="department",
        primaryjoin="and_(Group.department_id == Department.id, Group.deleted_at == None)",
        lazy="select",
    )

    def __repr__(self) -> str:
        return f"<Department id={self.id} name={self.name}>"


# ── Team ───────────────────────────────────────────────────────────────────────

class Team(Base):
    """Maps to ``teams`` table."""

    __tablename__ = "teams"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    department_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("departments.id", ondelete="CASCADE"),
        nullable=False,
    )
    leader_user_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("app_users.id", ondelete="SET NULL"),
        nullable=True,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now()
    )
    deleted_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)

    __table_args__ = (
        UniqueConstraint("name", "department_id", name="uq_teams_name_dept"),
    )

    department: Mapped["Department"] = relationship("Department", back_populates="teams")
    groups: Mapped[list["Group"]] = relationship(
        "Group",
        back_populates="team",
        primaryjoin="and_(Group.team_id == Team.id, Group.deleted_at == None)",
        lazy="select",
    )

    def __repr__(self) -> str:
        return f"<Team id={self.id} name={self.name}>"


# ── Group ──────────────────────────────────────────────────────────────────────

class Group(Base):
    """Maps to ``groups`` table."""

    __tablename__ = "groups"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    team_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("teams.id", ondelete="SET NULL"),
        nullable=True,
    )
    department_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("departments.id", ondelete="CASCADE"),
        nullable=False,
    )
    leader_user_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("app_users.id", ondelete="SET NULL"),
        nullable=True,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now()
    )
    deleted_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)

    department: Mapped["Department"] = relationship("Department", back_populates="groups")
    team: Mapped[Optional["Team"]] = relationship("Team", back_populates="groups")

    def __repr__(self) -> str:
        return f"<Group id={self.id} name={self.name}>"


# ── MemberAssignment ───────────────────────────────────────────────────────────

class MemberAssignment(Base):
    """Maps to ``member_assignments`` — junction table linking members to entities."""

    __tablename__ = "member_assignments"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    member_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("members.id", ondelete="CASCADE"),
        nullable=False,
    )
    assignment_type: Mapped[str] = mapped_column(String(20), nullable=False)
    assignment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    role_in_assignment: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    joined_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    left_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now()
    )
    deleted_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)

    member: Mapped["MemberModel"] = relationship("MemberModel", back_populates="assignments")

    def __repr__(self) -> str:
        return f"<MemberAssignment member={self.member_id} type={self.assignment_type} entity={self.assignment_id}>"
