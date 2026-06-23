"""
Genesis Global CMS — Pydantic v2 Schemas: Attendance Domain
"""
import uuid
from datetime import date, datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field

from app.models.attendance import AttendanceStatusEnum, MeetingTypeEnum


class BaseSchema(BaseModel):
    model_config = ConfigDict(from_attributes=True, use_enum_values=True)


# ── Meeting Schemas ────────────────────────────────────────────────────────────

class MeetingCreate(BaseSchema):
    title: str = Field(..., min_length=2, max_length=255)
    meeting_date: date
    meeting_type: Optional[MeetingTypeEnum] = None
    entity_id: Optional[uuid.UUID] = None
    notes: Optional[str] = None


class MeetingResponse(BaseSchema):
    id: uuid.UUID
    title: str
    meeting_date: date
    meeting_type: Optional[str] = None
    entity_id: Optional[uuid.UUID] = None
    notes: Optional[str] = None
    created_by: Optional[uuid.UUID] = None
    created_at: datetime
    updated_at: datetime


# ── Attendance Schemas ─────────────────────────────────────────────────────────

class AttendanceEntry(BaseSchema):
    member_id: uuid.UUID
    status: AttendanceStatusEnum
    notes: Optional[str] = None


class MarkAttendanceRequest(BaseSchema):
    attendances: list[AttendanceEntry] = Field(..., min_length=1)


class AttendanceRecordResponse(BaseSchema):
    id: uuid.UUID
    meeting_id: uuid.UUID
    member_id: uuid.UUID
    status: str
    marked_by: Optional[uuid.UUID] = None
    marked_at: Optional[datetime] = None
    notes: Optional[str] = None
    created_at: datetime
    updated_at: datetime


class MeetingWithAttendanceResponse(MeetingResponse):
    attendance_records: list[AttendanceRecordResponse] = []


# ── Stats Schemas ──────────────────────────────────────────────────────────────

class MemberAttendanceRate(BaseSchema):
    member_id: uuid.UUID
    member_name: str
    total_meetings: int
    attended: int
    rate: float


class AttendanceStatsResponse(BaseSchema):
    entity_type: str
    entity_id: uuid.UUID
    total_meetings: int
    avg_attendance_rate: float
    members: list[MemberAttendanceRate] = []


class MemberAttendanceHistory(BaseSchema):
    meeting_id: uuid.UUID
    meeting_title: str
    meeting_date: date
    meeting_type: Optional[str] = None
    status: str
    notes: Optional[str] = None
