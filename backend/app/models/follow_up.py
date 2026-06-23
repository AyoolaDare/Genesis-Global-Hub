"""
Genesis Global CMS — SQLAlchemy Models: Follow-Up Domain

Covers:
  - FollowUpContact → follow_up_contacts table
  - FollowUpTask    → follow_up_tasks table
  - FollowUpNote    → follow_up_notes table
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
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.sql import func

from app.database import Base


class FollowUpStageEnum(str, enum.Enum):
    FIRST_CONTACT = "FIRST_CONTACT"
    HOME_VISIT_SCHEDULED = "HOME_VISIT_SCHEDULED"
    ONBOARDING_CLASS_COMPLETED = "ONBOARDING_CLASS_COMPLETED"
    DEPARTMENT_PLACEMENT = "DEPARTMENT_PLACEMENT"
    FULLY_INTEGRATED = "FULLY_INTEGRATED"


class NoteTypeEnum(str, enum.Enum):
    CALL = "CALL"
    VISIT = "VISIT"
    SMS = "SMS"
    EMAIL = "EMAIL"
    OTHER = "OTHER"


# ── FollowUpContact ────────────────────────────────────────────────────────────

class FollowUpContact(Base):
    """Maps to ``follow_up_contacts`` — new converts / prospects."""

    __tablename__ = "follow_up_contacts"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    full_name: Mapped[str] = mapped_column(String(255), nullable=False)
    phone: Mapped[Optional[str]] = mapped_column(String(20), nullable=True)
    address: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    prayer_requests: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    how_heard: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    registered_by: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("app_users.id", ondelete="SET NULL"),
        nullable=True,
    )
    member_id: Mapped[Optional[uuid.UUID]] = mapped_column(
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

    tasks: Mapped[list["FollowUpTask"]] = relationship(
        "FollowUpTask",
        back_populates="contact",
        cascade="all, delete-orphan",
    )

    def __repr__(self) -> str:
        return f"<FollowUpContact id={self.id} name={self.full_name}>"


# ── FollowUpTask ───────────────────────────────────────────────────────────────

class FollowUpTask(Base):
    """Maps to ``follow_up_tasks`` — individual follow-up assignments."""

    __tablename__ = "follow_up_tasks"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    contact_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("follow_up_contacts.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    member_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("members.id", ondelete="SET NULL"),
        nullable=True,
    )
    assigned_to: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("app_users.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
    )
    stage: Mapped[FollowUpStageEnum] = mapped_column(
        Enum(FollowUpStageEnum, name="follow_up_stage", create_type=False),
        nullable=False,
        default=FollowUpStageEnum.FIRST_CONTACT,
    )
    due_date: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    completed_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    escalated_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    escalated_to: Mapped[Optional[uuid.UUID]] = mapped_column(
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

    contact: Mapped["FollowUpContact"] = relationship("FollowUpContact", back_populates="tasks")
    notes_list: Mapped[list["FollowUpNote"]] = relationship(
        "FollowUpNote",
        back_populates="task",
        cascade="all, delete-orphan",
    )

    def __repr__(self) -> str:
        return f"<FollowUpTask id={self.id} stage={self.stage} assigned={self.assigned_to}>"


# ── FollowUpNote ───────────────────────────────────────────────────────────────

class FollowUpNote(Base):
    """Maps to ``follow_up_notes`` — notes logged during follow-up interactions."""

    __tablename__ = "follow_up_notes"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    task_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("follow_up_tasks.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    contact_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("follow_up_contacts.id", ondelete="SET NULL"),
        nullable=True,
    )
    member_id: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), nullable=True)
    note_type: Mapped[Optional[NoteTypeEnum]] = mapped_column(
        Enum(NoteTypeEnum, name="note_type_enum", create_type=True),
        nullable=True,
    )
    content: Mapped[str] = mapped_column(Text, nullable=False)
    recorded_by: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("app_users.id", ondelete="RESTRICT"),
        nullable=False,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now()
    )

    task: Mapped["FollowUpTask"] = relationship("FollowUpTask", back_populates="notes_list")

    def __repr__(self) -> str:
        return f"<FollowUpNote id={self.id} task={self.task_id} type={self.note_type}>"
