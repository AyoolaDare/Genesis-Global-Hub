"""
Genesis Global CMS — Pydantic v2 Schemas: Member Domain
"""
import uuid
from datetime import date, datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator

from app.models.member import GenderEnum, MaritalStatusEnum, MemberStatusEnum


# ── Base Config ────────────────────────────────────────────────────────────────

class BaseSchema(BaseModel):
    model_config = ConfigDict(from_attributes=True, use_enum_values=True)


# ── Member Schemas ─────────────────────────────────────────────────────────────

class MemberCreate(BaseSchema):
    full_name: str = Field(..., min_length=2, max_length=255)
    phone: Optional[str] = Field(None, max_length=20)
    email: Optional[EmailStr] = None
    gender: Optional[GenderEnum] = None
    date_of_birth: Optional[date] = None
    address: Optional[str] = None
    marital_status: Optional[MaritalStatusEnum] = None
    salvation_date: Optional[date] = None
    water_baptism_status: bool = False
    holy_spirit_baptism_status: bool = False
    photo_url: Optional[str] = None
    submitter_notes: Optional[str] = None


class MemberUpdate(BaseSchema):
    full_name: Optional[str] = Field(None, min_length=2, max_length=255)
    phone: Optional[str] = Field(None, max_length=20)
    email: Optional[EmailStr] = None
    gender: Optional[GenderEnum] = None
    date_of_birth: Optional[date] = None
    address: Optional[str] = None
    marital_status: Optional[MaritalStatusEnum] = None
    salvation_date: Optional[date] = None
    water_baptism_status: Optional[bool] = None
    holy_spirit_baptism_status: Optional[bool] = None
    photo_url: Optional[str] = None


class MemberResponse(BaseSchema):
    id: uuid.UUID
    full_name: str
    phone: Optional[str] = None
    email: Optional[str] = None
    gender: Optional[str] = None
    date_of_birth: Optional[date] = None
    address: Optional[str] = None
    marital_status: Optional[str] = None
    salvation_date: Optional[date] = None
    water_baptism_status: bool
    holy_spirit_baptism_status: bool
    membership_status: str
    photo_url: Optional[str] = None
    submitted_by: Optional[uuid.UUID] = None
    approved_by: Optional[uuid.UUID] = None
    approved_at: Optional[datetime] = None
    rejection_reason: Optional[str] = None
    duplicate_of: Optional[uuid.UUID] = None
    created_at: datetime
    updated_at: datetime


class MemberSummary(BaseSchema):
    """Reduced member info for list views."""
    id: uuid.UUID
    full_name: str
    phone: Optional[str] = None
    email: Optional[str] = None
    gender: Optional[str] = None
    membership_status: str
    created_at: datetime


class MemberSearchRequest(BaseSchema):
    query: str = Field(..., min_length=2, max_length=100)
    page: int = Field(1, ge=1)
    per_page: int = Field(20, ge=1, le=100)


class ApproveRequest(BaseSchema):
    admin_notes: Optional[str] = None


class RejectRequest(BaseSchema):
    reason: str = Field(..., min_length=5, max_length=500)
    admin_notes: Optional[str] = None


class RequestInfoRequest(BaseSchema):
    info_requested: str = Field(..., min_length=10, max_length=1000)
    admin_notes: Optional[str] = None


class MergeRequest(BaseSchema):
    notes: Optional[str] = None


class PendingMemberDataResponse(BaseSchema):
    id: uuid.UUID
    member_id: uuid.UUID
    submitter_notes: Optional[str] = None
    admin_notes: Optional[str] = None
    additional_info_requested: Optional[str] = None
    info_provided_at: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime


class MemberDuplicateResponse(BaseSchema):
    id: uuid.UUID
    new_member_id: uuid.UUID
    existing_member_id: uuid.UUID
    overall_score: Optional[float] = None
    phone_score: Optional[float] = None
    name_score: Optional[float] = None
    email_score: Optional[float] = None
    status: str
    resolved_by: Optional[uuid.UUID] = None
    resolved_at: Optional[datetime] = None
    created_at: datetime
    new_member_name: Optional[str] = None
    existing_member_name: Optional[str] = None


class MemberWithPendingResponse(MemberResponse):
    pending_data: Optional[PendingMemberDataResponse] = None
