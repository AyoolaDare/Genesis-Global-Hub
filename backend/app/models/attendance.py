"""
Genesis Global CMS — SQLAlchemy Models: Attendance Domain

Covers:
  - Meeting         → meetings table
  - AttendanceRecord → attendance_records table
"""
import enum
import uuid
from datetime import date, datetime
from typing import Optional

from sqlalchemy import (
    Date,
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


class MeetingTypeEnum(str, enum.Enum):
    DEPARTMENT = "DEPARTMENT"
    TEAM = "TEAM"
    GROUP = "GROUP"
    CHURCH = "CHURCH"


class AttendanceStatusEnum(str, enum.Enum):
    PRESENT = "PRESENT"
    ABSENT = "ABSENT"
    EXCUSED = "EXCUSED"


# ── Meeting ────────────────────────────────────────────────────────────────────

class Meeting(Base):
    """Maps to ``meetings`` table."""

    __tablename__ = "meetings"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    meeting_date: Mapped[date] = mapped_column(Date, nullable=False, index=True)
    meeting_type: Mapped[Optional[MeetingTypeEnum]] = mapped_column(
        Enum(MeetingTypeEnum, name="meeting_type_enum", create_type=True),
        nullable=True,
    )
    entity_id: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), nullable=True)
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    created_by: Mapped[Optional[uuid.UUID]] = mapped_column(
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
    attendance_records: Mapped[list["AttendanceRecord"]] = relationship(
        "AttendanceRecord",
        back_populates="meeting",
        cascade="all, delete-orphan",
    )

    def __repr__(self) -> str:
        return f"<Meeting id={self.id} title={self.title} date={self.meeting_date}>"


# ── AttendanceRecord ───────────────────────────────────────────────────────────

class AttendanceRecord(Base):
    """Maps to ``attendance_records`` table."""

    __tablename__ = "attendance_records"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    meeting_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("meetings.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    member_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("members.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    status: Mapped[AttendanceStatusEnum] = mapped_column(
        Enum(AttendanceStatusEnum, name="attendance_status", create_type=False),
        nullable=False,
        default=AttendanceStatusEnum.ABSENT,
    )
    marked_by: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("app_users.id", ondelete="SET NULL"),
        nullable=True,
    )
    marked_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now()
    )

    __table_args__ = (
        UniqueConstraint("meeting_id", "member_id", name="uq_attendance_meeting_member"),
    )

    meeting: Mapped["Meeting"] = relationship("Meeting", back_populates="attendance_records")

    def __repr__(self) -> str:
        return f"<AttendanceRecord meeting={self.meeting_id} member={self.member_id} status={self.status}>"
