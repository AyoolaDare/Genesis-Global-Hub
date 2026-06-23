"""
Genesis Global CMS — SQLAlchemy Models: Sponsor Domain

Covers:
  - Sponsor         → sponsors table
  - SponsorPayment  → sponsor_payments table
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
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.sql import func

from app.database import Base


# ── Enums ──────────────────────────────────────────────────────────────────────

class SponsorshipTierEnum(str, enum.Enum):
    MONTHLY = "MONTHLY"
    QUARTERLY = "QUARTERLY"
    ANNUAL = "ANNUAL"
    ONE_TIME = "ONE_TIME"


class PaymentStatusEnum(str, enum.Enum):
    PENDING = "PENDING"
    COMPLETED = "COMPLETED"
    FAILED = "FAILED"
    CANCELLED = "CANCELLED"
    REFUNDED = "REFUNDED"


class PaymentMethodEnum(str, enum.Enum):
    FLUTTERWAVE = "FLUTTERWAVE"
    BANK_TRANSFER = "BANK_TRANSFER"
    CASH = "CASH"


class PreferredChannelEnum(str, enum.Enum):
    SMS = "SMS"
    WHATSAPP = "WHATSAPP"
    EMAIL = "EMAIL"


# ── Sponsor ────────────────────────────────────────────────────────────────────

class Sponsor(Base):
    """Maps to ``sponsors`` table."""

    __tablename__ = "sponsors"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    member_link_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("members.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    full_name: Mapped[str] = mapped_column(String(255), nullable=False)
    email: Mapped[Optional[str]] = mapped_column(String(255), nullable=True, index=True)
    phone: Mapped[Optional[str]] = mapped_column(String(20), nullable=True)
    sponsorship_tier: Mapped[SponsorshipTierEnum] = mapped_column(
        Enum(SponsorshipTierEnum, name="sponsorship_tier", create_type=False),
        nullable=False,
        default=SponsorshipTierEnum.MONTHLY,
    )
    amount: Mapped[float] = mapped_column(Numeric(15, 2), nullable=False)
    is_active: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default="true"
    )
    preferred_channel: Mapped[PreferredChannelEnum] = mapped_column(
        Enum(PreferredChannelEnum, name="preferred_channel", create_type=False),
        nullable=False,
        default=PreferredChannelEnum.SMS,
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
    payments: Mapped[list["SponsorPayment"]] = relationship(
        "SponsorPayment",
        back_populates="sponsor",
        cascade="all, delete-orphan",
        order_by="desc(SponsorPayment.created_at)",
    )

    def __repr__(self) -> str:
        return f"<Sponsor id={self.id} name={self.full_name} tier={self.sponsorship_tier}>"


# ── SponsorPayment ─────────────────────────────────────────────────────────────

class SponsorPayment(Base):
    """Maps to ``sponsor_payments`` table."""

    __tablename__ = "sponsor_payments"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    sponsor_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("sponsors.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    payment_method: Mapped[Optional[PaymentMethodEnum]] = mapped_column(
        Enum(PaymentMethodEnum, name="payment_method", create_type=False),
        nullable=True,
    )
    flutterwave_tx_ref: Mapped[Optional[str]] = mapped_column(String(255), nullable=True, unique=True, index=True)
    flutterwave_tx_id: Mapped[Optional[str]] = mapped_column(String(255), nullable=True, index=True)
    amount: Mapped[float] = mapped_column(Numeric(15, 2), nullable=False)
    status: Mapped[PaymentStatusEnum] = mapped_column(
        Enum(PaymentStatusEnum, name="payment_status", create_type=False),
        nullable=False,
        default=PaymentStatusEnum.PENDING,
    )
    payment_date: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    verified_by: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("app_users.id", ondelete="SET NULL"),
        nullable=True,
    )
    verified_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    next_due_date: Mapped[Optional[date]] = mapped_column(Date, nullable=True, index=True)
    reminder_sent_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    thank_you_sent_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    flutterwave_response: Mapped[Optional[dict]] = mapped_column(JSONB, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now()
    )
    deleted_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)

    # Relationships
    sponsor: Mapped["Sponsor"] = relationship("Sponsor", back_populates="payments")

    def __repr__(self) -> str:
        return f"<SponsorPayment id={self.id} sponsor={self.sponsor_id} status={self.status} amount={self.amount}>"
