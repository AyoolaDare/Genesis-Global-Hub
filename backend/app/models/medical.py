"""
Genesis Global CMS — SQLAlchemy Models: Medical Domain (ISOLATED)

Covers:
  - MedicalPatient → medical_patients table
  - MedicalVisit   → medical_visits table

CRITICAL: member_link_id MUST NEVER appear in any API response.
"""
import uuid
from datetime import date, datetime
from typing import Optional

from sqlalchemy import (
    Boolean,
    Date,
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
from app.models.member import GenderEnum


# ── MedicalPatient ─────────────────────────────────────────────────────────────

class MedicalPatient(Base):
    """Maps to ``medical_patients`` table. Completely isolated from member domain."""

    __tablename__ = "medical_patients"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    full_name: Mapped[str] = mapped_column(String(255), nullable=False)
    phone: Mapped[Optional[str]] = mapped_column(String(20), nullable=True)
    gender: Mapped[Optional[GenderEnum]] = mapped_column(
        Enum(GenderEnum, name="gender", create_type=False), nullable=True
    )
    date_of_birth: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
    is_church_member: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )
    # NEVER expose member_link_id in API responses
    member_link_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), nullable=True, comment="Backend-only. NEVER expose in API responses."
    )
    consent_given: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )
    consent_date: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    allergies: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    chronic_conditions: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    created_by: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("app_users.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now()
    )
    deleted_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)

    visits: Mapped[list["MedicalVisit"]] = relationship(
        "MedicalVisit",
        back_populates="patient",
        cascade="all, delete-orphan",
        order_by="desc(MedicalVisit.visit_date)",
    )

    def __repr__(self) -> str:
        return f"<MedicalPatient id={self.id} name={self.full_name}>"


# ── MedicalVisit ───────────────────────────────────────────────────────────────

class MedicalVisit(Base):
    """Maps to ``medical_visits`` table."""

    __tablename__ = "medical_visits"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    patient_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("medical_patients.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    visit_date: Mapped[date] = mapped_column(Date, nullable=False, index=True)
    complaints: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    diagnosis: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    treatment: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    medications: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    follow_up_date: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    attended_by: Mapped[uuid.UUID] = mapped_column(
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
    deleted_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)

    patient: Mapped["MedicalPatient"] = relationship("MedicalPatient", back_populates="visits")

    def __repr__(self) -> str:
        return f"<MedicalVisit id={self.id} patient={self.patient_id} date={self.visit_date}>"
