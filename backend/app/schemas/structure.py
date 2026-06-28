"""
Genesis Global CMS — Pydantic v2 Schemas: Structure Domain
"""
import uuid
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field


class BaseSchema(BaseModel):
    model_config = ConfigDict(from_attributes=True, use_enum_values=True)


# ── Department Schemas ─────────────────────────────────────────────────────────

class DepartmentCreate(BaseSchema):
    name: str = Field(..., min_length=2, max_length=255)
    description: Optional[str] = None
    head_user_id: Optional[uuid.UUID] = None


class DepartmentUpdate(BaseSchema):
    name: Optional[str] = Field(None, min_length=2, max_length=255)
    description: Optional[str] = None


class AssignHeadRequest(BaseSchema):
    user_id: uuid.UUID


class DepartmentResponse(BaseSchema):
    id: uuid.UUID
    name: str
    description: Optional[str] = None
    head_user_id: Optional[uuid.UUID] = None
    created_at: datetime
    updated_at: datetime


class DepartmentDetailResponse(DepartmentResponse):
    teams: list["TeamSummary"] = []
    groups: list["GroupSummary"] = []


# ── Team Schemas ───────────────────────────────────────────────────────────────

class TeamCreate(BaseSchema):
    name: str = Field(..., min_length=2, max_length=255)
    department_id: Optional[uuid.UUID] = None
    leader_user_id: Optional[uuid.UUID] = None


class TeamUpdate(BaseSchema):
    name: Optional[str] = Field(None, min_length=2, max_length=255)
    department_id: Optional[uuid.UUID] = None
    leader_user_id: Optional[uuid.UUID] = None


class AssignLeaderRequest(BaseSchema):
    user_id: uuid.UUID


class TeamResponse(BaseSchema):
    id: uuid.UUID
    name: str
    department_id: Optional[uuid.UUID] = None
    leader_user_id: Optional[uuid.UUID] = None
    created_at: datetime
    updated_at: datetime


class TeamSummary(BaseSchema):
    id: uuid.UUID
    name: str
    leader_user_id: Optional[uuid.UUID] = None


# ── Group Schemas ──────────────────────────────────────────────────────────────

class GroupCreate(BaseSchema):
    name: str = Field(..., min_length=2, max_length=255)
    department_id: Optional[uuid.UUID] = None
    team_id: Optional[uuid.UUID] = None
    leader_user_id: Optional[uuid.UUID] = None


class GroupUpdate(BaseSchema):
    name: Optional[str] = Field(None, min_length=2, max_length=255)
    department_id: Optional[uuid.UUID] = None
    team_id: Optional[uuid.UUID] = None
    leader_user_id: Optional[uuid.UUID] = None


class GroupResponse(BaseSchema):
    id: uuid.UUID
    name: str
    department_id: Optional[uuid.UUID] = None
    team_id: Optional[uuid.UUID] = None
    leader_user_id: Optional[uuid.UUID] = None
    created_at: datetime
    updated_at: datetime


class GroupSummary(BaseSchema):
    id: uuid.UUID
    name: str
    team_id: Optional[uuid.UUID] = None
    leader_user_id: Optional[uuid.UUID] = None


# ── Assignment Schemas ─────────────────────────────────────────────────────────

class MemberAssignRequest(BaseSchema):
    assignment_type: str = Field(..., pattern="^(DEPARTMENT|TEAM|GROUP)$")
    assignment_id: uuid.UUID
    role_in_assignment: Optional[str] = Field(None, max_length=100)


class MemberAssignmentResponse(BaseSchema):
    id: uuid.UUID
    member_id: uuid.UUID
    assignment_type: str
    assignment_id: uuid.UUID
    role_in_assignment: Optional[str] = None
    joined_at: datetime
    left_at: Optional[datetime] = None
    created_at: datetime


# Rebuild models for forward references
DepartmentDetailResponse.model_rebuild()
