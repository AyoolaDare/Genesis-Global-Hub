"""
Genesis Global CMS — Pydantic v2 Schemas: KPI Domain
"""
import uuid
from datetime import date, datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field

from app.models.kpi import KpiPeriodEnum


class BaseSchema(BaseModel):
    model_config = ConfigDict(from_attributes=True, use_enum_values=True)


# ── KPI Definition Schemas ─────────────────────────────────────────────────────

class KpiDefinitionCreate(BaseSchema):
    name: str = Field(..., min_length=2, max_length=255)
    description: Optional[str] = None
    entity_type: str = Field(..., pattern="^(DEPARTMENT|TEAM|GROUP)$")
    entity_id: uuid.UUID
    target_value: Optional[float] = Field(None, ge=0)
    target_unit: Optional[str] = Field(None, max_length=50)
    period: KpiPeriodEnum = KpiPeriodEnum.MONTHLY
    is_active: bool = True


class KpiDefinitionUpdate(BaseSchema):
    name: Optional[str] = Field(None, min_length=2, max_length=255)
    description: Optional[str] = None
    target_value: Optional[float] = Field(None, ge=0)
    target_unit: Optional[str] = Field(None, max_length=50)
    period: Optional[KpiPeriodEnum] = None
    is_active: Optional[bool] = None


class KpiDefinitionResponse(BaseSchema):
    id: uuid.UUID
    name: str
    description: Optional[str] = None
    entity_type: str
    entity_id: uuid.UUID
    target_value: Optional[float] = None
    target_unit: Optional[str] = None
    period: str
    is_active: bool
    created_by: Optional[uuid.UUID] = None
    created_at: datetime
    updated_at: datetime


# ── KPI Record Schemas ─────────────────────────────────────────────────────────

class KpiRecordCreate(BaseSchema):
    kpi_definition_id: uuid.UUID
    period_start: date
    period_end: date
    actual_value: Optional[float] = Field(None, ge=0)
    notes: Optional[str] = None


class KpiRecordResponse(BaseSchema):
    id: uuid.UUID
    kpi_definition_id: uuid.UUID
    period_start: date
    period_end: date
    actual_value: Optional[float] = None
    notes: Optional[str] = None
    recorded_by: Optional[uuid.UUID] = None
    created_at: datetime
    updated_at: datetime


# ── Dashboard Schemas ──────────────────────────────────────────────────────────

class KpiTrendPoint(BaseSchema):
    period_start: date
    period_end: date
    actual_value: Optional[float] = None
    target_value: Optional[float] = None


class KpiDashboardItem(BaseSchema):
    kpi_id: uuid.UUID
    name: str
    description: Optional[str] = None
    entity_type: str
    entity_id: uuid.UUID
    target_value: Optional[float] = None
    target_unit: Optional[str] = None
    current_value: Optional[float] = None
    percent_achieved: Optional[float] = None
    period: str
    is_active: bool
    trend: list[KpiTrendPoint] = []


class KpiDashboardResponse(BaseSchema):
    entity_type: str
    entity_id: uuid.UUID
    kpis: list[KpiDashboardItem] = []
