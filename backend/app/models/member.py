"""
Genesis Global CMS — SQLAlchemy Models: Member Domain

Covers:
  - MemberModel       → members table (full definition)
  - PendingMemberData → pending_member_data table
  - MemberDuplicate   → member_duplicates table
"""
from __future__ import annotations

import enum
import uuid
from datetime import date, datetime
from typing import Optional, TYPE_CHECKING

from sqlalchemy import (
    Boolean,
    Date,
    DateTime,
    Enum,
    ForeignKey,
    Numeric,
    String,
    Text,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.sql import func

from app.database import Base

if TYPE_CHECKING:
    from app.models.structure import MemberAssignment


# ── Enums ──────────────────────────────────────────────────────────────────────

class GenderEnum(str, enum.Enum):
    MALE = "MALE"
    FEMALE = "FEMALE"


class MaritalStatusEnum(str, enum.Enum):
    SINGLE = "SINGLE"
    MARRIED = "MARRIED"
    DIVORCED = "DIVORCED"
    WIDOWED = "WIDOWED"


class MemberStatusEnum(str, enum.Enum):
    ACTIVE = "ACTIVE"
    INACTIVE = "INACTIVE"
    PENDING = "PENDING"
    PENDING_DUPLICATE_CHECK = "PENDING_DUPLICATE_CHECK"
    PENDING_INFO_REQUESTED = "PENDING_INFO_REQUESTED"
    REJECTED = "REJECTED"
    MERGED = "MERGED"


class DuplicateStatusEnum(str, enum.Enum):
    PENDING = "PENDING"
    RESOLVED = "RESOLVED"
    IGNORED = "IGNORED"


# ── MemberModel ────────────────────────────────────────────────────────────────

class MemberModel(Base):
    """Full mapping of the ``members`` table."""

    __tablename__ = "members"
    __table_args__ = {"extend_existing": True}

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
    )
    full_name: Mapped[str] = mapped_column(String(255), nullable=False)
    phone: Mapped[Optional[str]] = mapped_column(String(20), nullable=True, index=True)
    email: Mapped[Optional[str]] = mapped_column(String(255), nullable=True, index=True)
    gender: Mapped[Optional[GenderEnum]] = mapped_column(
        Enum(GenderEnum, name="gender", create_type=False), nullable=True
    )
    date_of_birth: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
    address: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    marital_status: Mapped[Optional[MaritalStatusEnum]] = mapped_column(
        Enum(MaritalStatusEnum, name="marital_status", create_type=False), nullable=True
    )
    salvation_date: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
    water_baptism_status: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )
    holy_spirit_baptism_status: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )
    membership_status: Mapped[MemberStatusEnum] = mapped_column(
        Enum(MemberStatusEnum, name="member_status", create_type=False),
        nullable=False,
        default=MemberStatusEnum.PENDING,
        server_default="PENDING",
    )
    photo_url: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    submitted_by: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("app_users.id", ondelete="SET NULL"),
        nullable=True,
    )
    approved_by: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("app_users.id", ondelete="SET NULL"),
        nullable=True,
    )
    approved_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    rejection_reason: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    duplicate_of: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("members.id", ondelete="SET NULL"),
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
    pending_data: Mapped[Optional["PendingMemberData"]] = relationship(
        "PendingMemberData",
        back_populates="member",
        uselist=False,
        cascade="all, delete-orphan",
    )
    duplicates_as_new: Mapped[list["MemberDuplicate"]] = relationship(
        "MemberDuplicate",
        foreign_keys="MemberDuplicate.new_member_id",
        back_populates="new_member",
        cascade="all, delete-orphan",
    )
    assignments: Mapped[list["MemberAssignment"]] = relationship(
        "MemberAssignment",
        back_populates="member",
        cascade="all, delete-orphan",
    )

    def __repr__(self) -> str:
        return f"<MemberModel id={self.id} name={self.full_name} status={self.membership_status}>"


# ── PendingMemberData ──────────────────────────────────────────────────────────

class PendingMemberData(Base):
    """Maps to ``pending_member_data`` — extra data for pending member submissions."""

    __tablename__ = "pending_member_data"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    member_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("members.id", ondelete="CASCADE"),
        nullable=False,
        unique=True,
    )
    submitter_notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    admin_notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    additional_info_requested: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    info_provided_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now()
    )

    member: Mapped["MemberModel"] = relationship("MemberModel", back_populates="pending_data")

    def __repr__(self) -> str:
        return f"<PendingMemberData member_id={self.member_id}>"


# ── MemberDuplicate ────────────────────────────────────────────────────────────

class MemberDuplicate(Base):
    """Maps to ``member_duplicates`` — records potential duplicate member pairs."""

    __tablename__ = "member_duplicates"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    new_member_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("members.id", ondelete="CASCADE"),
        nullable=False,
    )
    existing_member_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("members.id", ondelete="CASCADE"),
        nullable=False,
    )
    overall_score: Mapped[Optional[float]] = mapped_column(Numeric(5, 2), nullable=True)
    phone_score: Mapped[Optional[float]] = mapped_column(Numeric(5, 2), nullable=True)
    name_score: Mapped[Optional[float]] = mapped_column(Numeric(5, 2), nullable=True)
    email_score: Mapped[Optional[float]] = mapped_column(Numeric(5, 2), nullable=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="PENDING")
    resolved_by: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("app_users.id", ondelete="SET NULL"),
        nullable=True,
    )
    resolved_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    new_member: Mapped["MemberModel"] = relationship(
        "MemberModel",
        foreign_keys=[new_member_id],
        back_populates="duplicates_as_new",
    )
    existing_member: Mapped["MemberModel"] = relationship(
        "MemberModel",
        foreign_keys=[existing_member_id],
    )

    def __repr__(self) -> str:
        return f"<MemberDuplicate new={self.new_member_id} existing={self.existing_member_id} score={self.overall_score}>"
