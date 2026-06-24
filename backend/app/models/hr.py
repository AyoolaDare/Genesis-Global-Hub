"""
Genesis Global CMS — SQLAlchemy Models: HR Domain (ISOLATED)

Covers:
  - Worker                  → workers table
  - WorkerPerformanceReview → worker_performance_reviews table
  - WorkerLeaveRequest      → worker_leave_requests table
  - WorkerRecognition       → worker_recognitions table

CRITICAL: member_link_id MUST NEVER appear in any API response.
NOTE: No salary fields — volunteer-first architecture.
"""
import enum
import uuid
from datetime import date, datetime
from typing import Optional

from sqlalchemy import (
    ARRAY,
    Date,
    DateTime,
    Enum,
    ForeignKey,
    Integer,
    Numeric,
    String,
    Text,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.sql import func

from app.database import Base


class EmploymentTypeEnum(str, enum.Enum):
    VOLUNTEER = "VOLUNTEER"
    PART_TIME = "PART_TIME"
    FULL_TIME = "FULL_TIME"


class WorkerStatusEnum(str, enum.Enum):
    ACTIVE = "ACTIVE"
    INACTIVE = "INACTIVE"
    ON_LEAVE = "ON_LEAVE"


class LeaveTypeEnum(str, enum.Enum):
    ANNUAL = "ANNUAL"
    SICK = "SICK"
    PERSONAL = "PERSONAL"
    OTHER = "OTHER"


class LeaveStatusEnum(str, enum.Enum):
    PENDING = "PENDING"
    APPROVED = "APPROVED"
    REJECTED = "REJECTED"


class RecognitionTypeEnum(str, enum.Enum):
    AWARD = "AWARD"
    COMMENDATION = "COMMENDATION"
    MILESTONE = "MILESTONE"


# ── Worker ─────────────────────────────────────────────────────────────────────

class Worker(Base):
    """Maps to ``workers`` table. Completely isolated HR domain."""

    __tablename__ = "workers"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    full_name: Mapped[str] = mapped_column(String(255), nullable=False)
    phone: Mapped[Optional[str]] = mapped_column(String(20), nullable=True)
    email: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    department_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("departments.id", ondelete="SET NULL"),
        nullable=True,
    )
    role_title: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    employment_type: Mapped[EmploymentTypeEnum] = mapped_column(
        Enum(EmploymentTypeEnum, name="employment_type", create_type=False),
        nullable=False,
        default=EmploymentTypeEnum.VOLUNTEER,
    )
    start_date: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="ACTIVE")
    time_commitment_hours_per_week: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    skills: Mapped[Optional[list]] = mapped_column(ARRAY(Text), nullable=True)
    interests: Mapped[Optional[list]] = mapped_column(ARRAY(Text), nullable=True)
    # NEVER expose member_link_id in API responses
    member_link_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), nullable=True, comment="Backend-only. NEVER expose in API responses."
    )
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
    reviews: Mapped[list["WorkerPerformanceReview"]] = relationship(
        "WorkerPerformanceReview",
        back_populates="worker",
        cascade="all, delete-orphan",
        order_by="desc(WorkerPerformanceReview.review_period_start)",
    )
    leave_requests: Mapped[list["WorkerLeaveRequest"]] = relationship(
        "WorkerLeaveRequest",
        back_populates="worker",
        cascade="all, delete-orphan",
        order_by="desc(WorkerLeaveRequest.start_date)",
    )
    recognitions: Mapped[list["WorkerRecognition"]] = relationship(
        "WorkerRecognition",
        back_populates="worker",
        cascade="all, delete-orphan",
        order_by="desc(WorkerRecognition.awarded_at)",
    )

    def __repr__(self) -> str:
        return f"<Worker id={self.id} name={self.full_name} type={self.employment_type}>"


# ── WorkerPerformanceReview ────────────────────────────────────────────────────

class WorkerPerformanceReview(Base):
    """Maps to ``worker_performance_reviews`` table."""

    __tablename__ = "worker_performance_reviews"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    worker_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("workers.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    review_period_start: Mapped[date] = mapped_column(Date, nullable=False)
    review_period_end: Mapped[date] = mapped_column(Date, nullable=False)
    reviewer_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("app_users.id", ondelete="RESTRICT"),
        nullable=False,
    )
    self_score: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    peer_score: Mapped[Optional[float]] = mapped_column(Numeric(3, 2), nullable=True)
    supervisor_score: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    overall_score: Mapped[Optional[float]] = mapped_column(Numeric(3, 2), nullable=True)
    strengths: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    areas_for_growth: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    goals: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now()
    )

    worker: Mapped["Worker"] = relationship("Worker", back_populates="reviews")

    def __repr__(self) -> str:
        return f"<WorkerPerformanceReview worker={self.worker_id} period={self.review_period_start}>"


# ── WorkerLeaveRequest ─────────────────────────────────────────────────────────

class WorkerLeaveRequest(Base):
    """Maps to ``worker_leave_requests`` table."""

    __tablename__ = "worker_leave_requests"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    worker_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("workers.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    leave_type: Mapped[str] = mapped_column(String(20), nullable=False)
    start_date: Mapped[date] = mapped_column(Date, nullable=False)
    end_date: Mapped[date] = mapped_column(Date, nullable=False)
    reason: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="PENDING")
    approved_by: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("app_users.id", ondelete="SET NULL"),
        nullable=True,
    )
    approved_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now()
    )

    worker: Mapped["Worker"] = relationship("Worker", back_populates="leave_requests")

    def __repr__(self) -> str:
        return f"<WorkerLeaveRequest worker={self.worker_id} type={self.leave_type} status={self.status}>"


# ── WorkerRecognition ──────────────────────────────────────────────────────────

class WorkerRecognition(Base):
    """Maps to ``worker_recognitions`` table."""

    __tablename__ = "worker_recognitions"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    worker_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("workers.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    recognition_type: Mapped[Optional[str]] = mapped_column(String(20), nullable=True)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    awarded_by: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("app_users.id", ondelete="SET NULL"),
        nullable=True,
    )
    awarded_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    worker: Mapped["Worker"] = relationship("Worker", back_populates="recognitions")

    def __repr__(self) -> str:
        return f"<WorkerRecognition worker={self.worker_id} title={self.title}>"
