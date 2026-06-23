"""
Genesis Global CMS — Pydantic v2 Schemas: Follow-Up Domain
"""
import uuid
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field

from app.models.follow_up import FollowUpStageEnum, NoteTypeEnum


class BaseSchema(BaseModel):
    model_config = ConfigDict(from_attributes=True, use_enum_values=True)


# ── Contact Schemas ────────────────────────────────────────────────────────────

class FollowUpContactCreate(BaseSchema):
    full_name: str = Field(..., min_length=2, max_length=255)
    phone: Optional[str] = Field(None, max_length=20)
    address: Optional[str] = None
    prayer_requests: Optional[str] = None
    how_heard: Optional[str] = None


class FollowUpContactResponse(BaseSchema):
    id: uuid.UUID
    full_name: str
    phone: Optional[str] = None
    address: Optional[str] = None
    prayer_requests: Optional[str] = None
    how_heard: Optional[str] = None
    registered_by: Optional[uuid.UUID] = None
    member_id: Optional[uuid.UUID] = None
    created_at: datetime
    updated_at: datetime


# ── Task Schemas ───────────────────────────────────────────────────────────────

class FollowUpTaskCreate(BaseSchema):
    contact_id: uuid.UUID
    assigned_to: uuid.UUID
    stage: FollowUpStageEnum = FollowUpStageEnum.FIRST_CONTACT
    due_date: Optional[datetime] = None
    notes: Optional[str] = None


class FollowUpTaskUpdate(BaseSchema):
    stage: Optional[FollowUpStageEnum] = None
    assigned_to: Optional[uuid.UUID] = None
    due_date: Optional[datetime] = None
    notes: Optional[str] = None


class EscalateTaskRequest(BaseSchema):
    escalate_to: uuid.UUID
    reason: Optional[str] = None


class FollowUpTaskResponse(BaseSchema):
    id: uuid.UUID
    contact_id: uuid.UUID
    member_id: Optional[uuid.UUID] = None
    assigned_to: uuid.UUID
    stage: str
    due_date: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    notes: Optional[str] = None
    escalated_at: Optional[datetime] = None
    escalated_to: Optional[uuid.UUID] = None
    created_at: datetime
    updated_at: datetime
    contact_name: Optional[str] = None
    contact_phone: Optional[str] = None


# ── Note Schemas ───────────────────────────────────────────────────────────────

class FollowUpNoteCreate(BaseSchema):
    task_id: uuid.UUID
    contact_id: Optional[uuid.UUID] = None
    member_id: Optional[uuid.UUID] = None
    note_type: Optional[NoteTypeEnum] = None
    content: str = Field(..., min_length=5)


class FollowUpNoteResponse(BaseSchema):
    id: uuid.UUID
    task_id: uuid.UUID
    contact_id: Optional[uuid.UUID] = None
    member_id: Optional[uuid.UUID] = None
    note_type: Optional[str] = None
    content: str
    recorded_by: uuid.UUID
    created_at: datetime
    updated_at: datetime
