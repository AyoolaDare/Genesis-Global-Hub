"""
Genesis Global CMS — Pydantic v2 Schemas: Medical Domain (ISOLATED)

CRITICAL: member_link_id MUST NEVER appear in these schemas.
Only return is_church_member: bool — no member identity.
"""
import uuid
from datetime import date, datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field

from app.models.member import GenderEnum


class BaseSchema(BaseModel):
    model_config = ConfigDict(from_attributes=True, use_enum_values=True)


# ── Patient Schemas ────────────────────────────────────────────────────────────

class MedicalPatientCreate(BaseSchema):
    full_name: str = Field(..., min_length=2, max_length=255)
    phone: Optional[str] = Field(None, max_length=20)
    gender: Optional[GenderEnum] = None
    date_of_birth: Optional[date] = None
    consent_given: bool = False
    consent_date: Optional[datetime] = None
    allergies: Optional[str] = None
    chronic_conditions: Optional[str] = None


class MedicalPatientUpdate(BaseSchema):
    full_name: Optional[str] = Field(None, min_length=2, max_length=255)
    phone: Optional[str] = Field(None, max_length=20)
    gender: Optional[GenderEnum] = None
    date_of_birth: Optional[date] = None
    consent_given: Optional[bool] = None
    consent_date: Optional[datetime] = None
    allergies: Optional[str] = None
    chronic_conditions: Optional[str] = None


class MedicalPatientResponse(BaseSchema):
    """
    CRITICAL: Does NOT include member_link_id.
    is_church_member is bool only — no identity info.
    """
    id: uuid.UUID
    full_name: str
    phone: Optional[str] = None
    gender: Optional[str] = None
    date_of_birth: Optional[date] = None
    is_church_member: bool
    consent_given: bool
    consent_date: Optional[datetime] = None
    allergies: Optional[str] = None
    chronic_conditions: Optional[str] = None
    created_by: Optional[uuid.UUID] = None
    created_at: datetime
    updated_at: datetime


class MedicalPatientSummary(BaseSchema):
    id: uuid.UUID
    full_name: str
    phone: Optional[str] = None
    gender: Optional[str] = None
    is_church_member: bool
    created_at: datetime


# ── Visit Schemas ──────────────────────────────────────────────────────────────

class MedicalVisitCreate(BaseSchema):
    visit_date: date
    complaints: Optional[str] = None
    diagnosis: Optional[str] = None
    treatment: Optional[str] = None
    medications: Optional[str] = None
    follow_up_date: Optional[date] = None
    notes: Optional[str] = None


class MedicalVisitUpdate(BaseSchema):
    complaints: Optional[str] = None
    diagnosis: Optional[str] = None
    treatment: Optional[str] = None
    medications: Optional[str] = None
    follow_up_date: Optional[date] = None
    notes: Optional[str] = None


class MedicalVisitResponse(BaseSchema):
    id: uuid.UUID
    patient_id: uuid.UUID
    visit_date: date
    complaints: Optional[str] = None
    diagnosis: Optional[str] = None
    treatment: Optional[str] = None
    medications: Optional[str] = None
    follow_up_date: Optional[date] = None
    notes: Optional[str] = None
    attended_by: uuid.UUID
    created_at: datetime
    updated_at: datetime


# ── Dashboard Schema ───────────────────────────────────────────────────────────

class MedicalDashboardResponse(BaseSchema):
    total_patients: int
    visits_this_month: int
    pending_follow_ups: int
