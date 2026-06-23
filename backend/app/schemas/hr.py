"""
Genesis Global CMS — Pydantic v2 Schemas: HR Domain (ISOLATED)

CRITICAL:
  - member_link_id MUST NEVER appear in these schemas
  - NO salary fields anywhere
  - Employment type is visible (VOLUNTEER/PART_TIME/FULL_TIME)
"""
import uuid
from datetime import date, datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, EmailStr, Field

from app.models.hr import EmploymentTypeEnum, LeaveTypeEnum, RecognitionTypeEnum


class BaseSchema(BaseModel):
    model_config = ConfigDict(from_attributes=True, use_enum_values=True)


# ── Worker Schemas ─────────────────────────────────────────────────────────────

class WorkerCreate(BaseSchema):
    full_name: str = Field(..., min_length=2, max_length=255)
    phone: Optional[str] = Field(None, max_length=20)
    email: Optional[EmailStr] = None
    department_id: Optional[uuid.UUID] = None
    role_title: Optional[str] = Field(None, max_length=255)
    employment_type: EmploymentTypeEnum = EmploymentTypeEnum.VOLUNTEER
    start_date: Optional[date] = None
    time_commitment_hours_per_week: Optional[int] = Field(None, ge=0)
    skills: Optional[list[str]] = None
    interests: Optional[list[str]] = None


class WorkerUpdate(BaseSchema):
    full_name: Optional[str] = Field(None, min_length=2, max_length=255)
    phone: Optional[str] = Field(None, max_length=20)
    email: Optional[EmailStr] = None
    department_id: Optional[uuid.UUID] = None
    role_title: Optional[str] = Field(None, max_length=255)
    employment_type: Optional[EmploymentTypeEnum] = None
    start_date: Optional[date] = None
    status: Optional[str] = Field(None, pattern="^(ACTIVE|INACTIVE|ON_LEAVE)$")
    time_commitment_hours_per_week: Optional[int] = Field(None, ge=0)
    skills: Optional[list[str]] = None
    interests: Optional[list[str]] = None


class WorkerResponse(BaseSchema):
    """CRITICAL: Does NOT include member_link_id."""
    id: uuid.UUID
    full_name: str
    phone: Optional[str] = None
    email: Optional[str] = None
    department_id: Optional[uuid.UUID] = None
    role_title: Optional[str] = None
    employment_type: str
    start_date: Optional[date] = None
    status: str
    time_commitment_hours_per_week: Optional[int] = None
    skills: Optional[list[str]] = None
    interests: Optional[list[str]] = None
    created_by: Optional[uuid.UUID] = None
    created_at: datetime
    updated_at: datetime


# ── Review Schemas ─────────────────────────────────────────────────────────────

class WorkerReviewCreate(BaseSchema):
    review_period_start: date
    review_period_end: date
    self_score: Optional[int] = Field(None, ge=1, le=5)
    peer_score: Optional[float] = Field(None, ge=1.0, le=5.0)
    supervisor_score: Optional[int] = Field(None, ge=1, le=5)
    overall_score: Optional[float] = Field(None, ge=1.0, le=5.0)
    strengths: Optional[str] = None
    areas_for_growth: Optional[str] = None
    goals: Optional[str] = None
    notes: Optional[str] = None


class WorkerReviewResponse(BaseSchema):
    id: uuid.UUID
    worker_id: uuid.UUID
    review_period_start: date
    review_period_end: date
    reviewer_id: uuid.UUID
    self_score: Optional[int] = None
    peer_score: Optional[float] = None
    supervisor_score: Optional[int] = None
    overall_score: Optional[float] = None
    strengths: Optional[str] = None
    areas_for_growth: Optional[str] = None
    goals: Optional[str] = None
    notes: Optional[str] = None
    created_at: datetime
    updated_at: datetime


# ── Leave Schemas ──────────────────────────────────────────────────────────────

class LeaveRequestCreate(BaseSchema):
    leave_type: LeaveTypeEnum
    start_date: date
    end_date: date
    reason: Optional[str] = None


class LeaveApprovalRequest(BaseSchema):
    status: str = Field(..., pattern="^(APPROVED|REJECTED)$")
    notes: Optional[str] = None


class LeaveRequestResponse(BaseSchema):
    id: uuid.UUID
    worker_id: uuid.UUID
    leave_type: str
    start_date: date
    end_date: date
    reason: Optional[str] = None
    status: str
    approved_by: Optional[uuid.UUID] = None
    approved_at: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime


# ── Recognition Schemas ────────────────────────────────────────────────────────

class RecognitionCreate(BaseSchema):
    recognition_type: Optional[RecognitionTypeEnum] = None
    title: str = Field(..., min_length=2, max_length=255)
    description: Optional[str] = None
    awarded_at: Optional[datetime] = None


class RecognitionResponse(BaseSchema):
    id: uuid.UUID
    worker_id: uuid.UUID
    recognition_type: Optional[str] = None
    title: str
    description: Optional[str] = None
    awarded_by: Optional[uuid.UUID] = None
    awarded_at: datetime
    created_at: datetime


# ── Dashboard Schemas ──────────────────────────────────────────────────────────

class DeptWorkerCount(BaseSchema):
    department_id: Optional[uuid.UUID] = None
    department_name: str
    count: int


class HRDashboardResponse(BaseSchema):
    total_workers: int
    active_workers: int
    volunteers: int
    pending_leave_requests: int
    by_department: list[DeptWorkerCount] = []
