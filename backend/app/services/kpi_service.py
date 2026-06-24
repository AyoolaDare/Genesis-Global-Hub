"""
Genesis Global CMS — KPI Service

Business logic for KPI definitions and records.
"""
import uuid
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy.orm import Session

from app.auth.models import AppUser, UserRole
from app.core.exceptions import DuplicateRecord, NotFound
from app.models.kpi import KpiDefinition, KpiRecord
from app.schemas.kpi import KpiDefinitionCreate, KpiDefinitionUpdate, KpiRecordCreate


# ── KPI Definition Service ─────────────────────────────────────────────────────

def list_kpi_definitions(
    db: Session,
    current_user: AppUser,
    request,
    page: int = 1,
    per_page: int = 20,
    entity_type: Optional[str] = None,
    entity_id: Optional[uuid.UUID] = None,
) -> tuple[list[KpiDefinition], int]:
    query = db.query(KpiDefinition).filter(KpiDefinition.deleted_at.is_(None))

    # Scope filtering for non-admin roles
    if current_user.role not in (UserRole.SUPER_ADMIN, UserRole.PASTOR):
        payload = getattr(request.state, "token_payload", {})
        scope = payload.get("scope", {}) or {}

        from sqlalchemy import or_
        conditions = []
        dept_ids = scope.get("departments", [])
        team_ids = scope.get("teams", [])
        group_ids = scope.get("groups", [])

        if dept_ids:
            conditions.append(
                (KpiDefinition.entity_type == "DEPARTMENT")
                & KpiDefinition.entity_id.in_([uuid.UUID(i) for i in dept_ids])
            )
        if team_ids:
            conditions.append(
                (KpiDefinition.entity_type == "TEAM")
                & KpiDefinition.entity_id.in_([uuid.UUID(i) for i in team_ids])
            )
        if group_ids:
            conditions.append(
                (KpiDefinition.entity_type == "GROUP")
                & KpiDefinition.entity_id.in_([uuid.UUID(i) for i in group_ids])
            )

        if conditions:
            query = query.filter(or_(*conditions))
        else:
            query = query.filter(False)

    if entity_type:
        query = query.filter(KpiDefinition.entity_type == entity_type)
    if entity_id:
        query = query.filter(KpiDefinition.entity_id == entity_id)

    query = query.order_by(KpiDefinition.name)
    total = query.count()
    items = query.offset((page - 1) * per_page).limit(per_page).all()
    return items, total


def get_kpi_definition(kpi_id: uuid.UUID, db: Session) -> KpiDefinition:
    kpi = db.query(KpiDefinition).filter(
        KpiDefinition.id == kpi_id, KpiDefinition.deleted_at.is_(None)
    ).first()
    if not kpi:
        raise NotFound(message=f"KPI definition {kpi_id} not found.")
    return kpi


def create_kpi_definition(
    data: KpiDefinitionCreate,
    current_user: AppUser,
    db: Session,
) -> KpiDefinition:
    kpi = KpiDefinition(
        name=data.name,
        description=data.description,
        entity_type=data.entity_type,
        entity_id=data.entity_id,
        target_value=data.target_value,
        target_unit=data.target_unit,
        period=data.period,
        is_active=data.is_active,
        created_by=current_user.id,
    )
    db.add(kpi)
    db.flush()
    return kpi


def update_kpi_definition(
    kpi: KpiDefinition,
    data: KpiDefinitionUpdate,
    db: Session,
) -> KpiDefinition:
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(kpi, field, value)
    db.flush()
    return kpi


def delete_kpi_definition(kpi: KpiDefinition, db: Session) -> None:
    kpi.deleted_at = datetime.now(timezone.utc)
    db.flush()


# ── KPI Record Service ─────────────────────────────────────────────────────────

def create_kpi_record(
    data: KpiRecordCreate,
    current_user: AppUser,
    db: Session,
) -> KpiRecord:
    # Verify KPI definition exists
    get_kpi_definition(data.kpi_definition_id, db)

    # Check for existing record in same period
    existing = db.query(KpiRecord).filter(
        KpiRecord.kpi_definition_id == data.kpi_definition_id,
        KpiRecord.period_start == data.period_start,
    ).first()
    if existing:
        raise DuplicateRecord(
            message="A KPI record for this period already exists. Use update instead."
        )

    record = KpiRecord(
        kpi_definition_id=data.kpi_definition_id,
        period_start=data.period_start,
        period_end=data.period_end,
        actual_value=data.actual_value,
        notes=data.notes,
        recorded_by=current_user.id,
    )
    db.add(record)
    db.flush()
    return record


def list_kpi_records(
    db: Session,
    current_user: AppUser,
    request,
    page: int = 1,
    per_page: int = 20,
    kpi_definition_id: Optional[uuid.UUID] = None,
) -> tuple[list[KpiRecord], int]:
    query = db.query(KpiRecord)

    if kpi_definition_id:
        query = query.filter(KpiRecord.kpi_definition_id == kpi_definition_id)

    query = query.order_by(KpiRecord.period_start.desc())
    total = query.count()
    items = query.offset((page - 1) * per_page).limit(per_page).all()
    return items, total


# ── KPI Dashboard ──────────────────────────────────────────────────────────────

def get_kpi_dashboard(
    entity_type: str,
    entity_id: uuid.UUID,
    db: Session,
) -> dict:
    """
    Build KPI dashboard for an entity.
    Returns each KPI with current value, target, % achieved, and 6-period trend.
    """
    kpi_defs = db.query(KpiDefinition).filter(
        KpiDefinition.entity_type == entity_type,
        KpiDefinition.entity_id == entity_id,
        KpiDefinition.deleted_at.is_(None),
        KpiDefinition.is_active.is_(True),
    ).all()

    dashboard_items = []

    for kpi in kpi_defs:
        # Get last 6 records (most recent periods)
        recent_records = (
            db.query(KpiRecord)
            .filter(KpiRecord.kpi_definition_id == kpi.id)
            .order_by(KpiRecord.period_start.desc())
            .limit(6)
            .all()
        )

        # Most recent value
        current_value = recent_records[0].actual_value if recent_records else None

        # Percentage achieved
        percent_achieved = None
        if kpi.target_value and current_value is not None and kpi.target_value > 0:
            percent_achieved = round((current_value / kpi.target_value) * 100.0, 1)

        trend = [
            {
                "period_start": r.period_start,
                "period_end": r.period_end,
                "actual_value": float(r.actual_value) if r.actual_value is not None else None,
                "target_value": float(kpi.target_value) if kpi.target_value is not None else None,
            }
            for r in reversed(recent_records)  # chronological order for trend
        ]

        dashboard_items.append({
            "kpi_id": kpi.id,
            "name": kpi.name,
            "description": kpi.description,
            "entity_type": kpi.entity_type,
            "entity_id": kpi.entity_id,
            "target_value": float(kpi.target_value) if kpi.target_value is not None else None,
            "target_unit": kpi.target_unit,
            "current_value": float(current_value) if current_value is not None else None,
            "percent_achieved": percent_achieved,
            "period": kpi.period,
            "is_active": kpi.is_active,
            "trend": trend,
        })

    return {
        "entity_type": entity_type,
        "entity_id": entity_id,
        "kpis": dashboard_items,
    }
