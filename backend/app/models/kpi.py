"""
Genesis Global CMS — SQLAlchemy Models: KPI Domain

Covers:
  - KpiDefinition → kpi_definitions table
  - KpiRecord     → kpi_records table
"""
import enum
import uuid
from datetime import date, datetime
from typing import Optional

from sqlalchemy import (
    Boolean,
    Date,
    DateTime,
    Enum,
    ForeignKey,
    Numeric,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.sql import func

from app.database import Base


class KpiPeriodEnum(str, enum.Enum):
    MONTHLY = "MONTHLY"
    QUARTERLY = "QUARTERLY"
    ANNUAL = "ANNUAL"


class KpiEntityTypeEnum(str, enum.Enum):
    DEPARTMENT = "DEPARTMENT"
    TEAM = "TEAM"
    GROUP = "GROUP"


# ── KpiDefinition ──────────────────────────────────────────────────────────────

class KpiDefinition(Base):
    """Maps to ``kpi_definitions`` table."""

    __tablename__ = "kpi_definitions"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    entity_type: Mapped[str] = mapped_column(String(20), nullable=False)
    entity_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    target_value: Mapped[Optional[float]] = mapped_column(Numeric(15, 2), nullable=True)
    target_unit: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    period: Mapped[KpiPeriodEnum] = mapped_column(
        Enum(KpiPeriodEnum, name="kpi_period", create_type=False),
        nullable=False,
        default=KpiPeriodEnum.MONTHLY,
    )
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="true")
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

    records: Mapped[list["KpiRecord"]] = relationship(
        "KpiRecord",
        back_populates="definition",
        cascade="all, delete-orphan",
        order_by="desc(KpiRecord.period_start)",
    )

    def __repr__(self) -> str:
        return f"<KpiDefinition id={self.id} name={self.name}>"


# ── KpiRecord ──────────────────────────────────────────────────────────────────

class KpiRecord(Base):
    """Maps to ``kpi_records`` table — actual values recorded against a KPI definition."""

    __tablename__ = "kpi_records"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    kpi_definition_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("kpi_definitions.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    period_start: Mapped[date] = mapped_column(Date, nullable=False)
    period_end: Mapped[date] = mapped_column(Date, nullable=False)
    actual_value: Mapped[Optional[float]] = mapped_column(Numeric(15, 2), nullable=True)
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    recorded_by: Mapped[Optional[uuid.UUID]] = mapped_column(
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

    __table_args__ = (
        UniqueConstraint("kpi_definition_id", "period_start", name="uq_kpi_records_def_period"),
    )

    definition: Mapped["KpiDefinition"] = relationship("KpiDefinition", back_populates="records")

    def __repr__(self) -> str:
        return f"<KpiRecord kpi={self.kpi_definition_id} period={self.period_start} value={self.actual_value}>"
