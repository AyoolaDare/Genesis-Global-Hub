"""
Genesis Global CMS — Pydantic v2 Schemas: Sponsor/Finance Domain (ISOLATED)

CRITICAL: member_link_id MUST NEVER appear in these schemas.
"""
import uuid
from datetime import date, datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, EmailStr, Field

from app.models.sponsor import (
    PaymentMethodEnum,
    PreferredChannelEnum,
    SponsorshipTierEnum,
)


class BaseSchema(BaseModel):
    model_config = ConfigDict(from_attributes=True, use_enum_values=True)


# ── Sponsor Schemas ────────────────────────────────────────────────────────────

class SponsorCreate(BaseSchema):
    full_name: str = Field(..., min_length=2, max_length=255)
    phone: Optional[str] = Field(None, max_length=20)
    email: Optional[EmailStr] = None
    sponsorship_tier: SponsorshipTierEnum
    amount: float = Field(..., gt=0)
    preferred_channel: Optional[PreferredChannelEnum] = None
    is_active: bool = True


class SponsorUpdate(BaseSchema):
    full_name: Optional[str] = Field(None, min_length=2, max_length=255)
    phone: Optional[str] = Field(None, max_length=20)
    email: Optional[EmailStr] = None
    sponsorship_tier: Optional[SponsorshipTierEnum] = None
    amount: Optional[float] = Field(None, gt=0)
    preferred_channel: Optional[PreferredChannelEnum] = None
    is_active: Optional[bool] = None


class SponsorResponse(BaseSchema):
    """CRITICAL: Does NOT include member_link_id."""
    id: uuid.UUID
    full_name: str
    phone: Optional[str] = None
    email: Optional[str] = None
    sponsorship_tier: str
    amount: float
    preferred_channel: Optional[str] = None
    is_active: bool
    created_by: Optional[uuid.UUID] = None
    created_at: datetime
    updated_at: datetime


class SponsorWithPaymentsResponse(SponsorResponse):
    payments: list["SponsorPaymentResponse"] = []


# ── Payment Schemas ────────────────────────────────────────────────────────────

class SponsorPaymentCreate(BaseSchema):
    amount: float = Field(..., gt=0)
    payment_date: Optional[datetime] = None
    payment_method: Optional[PaymentMethodEnum] = None
    notes: Optional[str] = None
    next_due_date: Optional[date] = None


class InitiatePaymentRequest(BaseSchema):
    sponsor_id: uuid.UUID
    amount: float = Field(..., gt=0)
    redirect_url: Optional[str] = None


class InitiatePaymentResponse(BaseSchema):
    tx_ref: str
    payment_link: str
    amount: float
    sponsor_name: str


class SponsorPaymentResponse(BaseSchema):
    id: uuid.UUID
    sponsor_id: uuid.UUID
    amount: float
    payment_date: Optional[datetime] = None
    payment_method: Optional[str] = None
    status: str
    flutterwave_tx_ref: Optional[str] = None
    verified_by: Optional[uuid.UUID] = None
    verified_at: Optional[datetime] = None
    notes: Optional[str] = None
    next_due_date: Optional[date] = None
    reminder_sent_at: Optional[datetime] = None
    thank_you_sent_at: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime


# ── Dashboard / Report Schemas ─────────────────────────────────────────────────

class OverdueSponsor(BaseSchema):
    id: uuid.UUID
    full_name: str
    phone: Optional[str] = None
    sponsorship_tier: str
    amount: float
    last_payment_date: Optional[datetime] = None
    next_due_date: Optional[date] = None


class FinanceDashboardResponse(BaseSchema):
    total_sponsors: int
    active_sponsors: int
    monthly_revenue: float
    annual_revenue: float
    payments_this_month: int
    overdue_sponsors: list[OverdueSponsor] = []


class AnnualReportEntry(BaseSchema):
    month: str
    total_payments: int
    total_amount: float


class AnnualSponsorshipReport(BaseSchema):
    year: int
    total_annual_revenue: float
    total_payments: int
    by_month: list[AnnualReportEntry] = []
    by_tier: dict = {}


# Rebuild for forward refs
SponsorWithPaymentsResponse.model_rebuild()
