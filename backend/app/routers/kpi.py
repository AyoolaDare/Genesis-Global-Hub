"""
Genesis Global CMS — KPI Tracking Router

Endpoints:
  GET    /kpi/definitions                      List KPI definitions (scoped)
  POST   /kpi/definitions                      Create KPI
  PUT    /kpi/definitions/{id}                 Update target
  DELETE /kpi/definitions/{id}                 Soft delete

  POST   /kpi/records                          Record KPI value
  GET    /kpi/records                          List records

  GET    /kpi/dashboard/{entity_type}/{id}     KPI dashboard
"""
import uuid
from typing import Optional

from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy.orm import Session

from app.auth.dependencies import get_current_user, require_role
from app.auth.models import AppUser
from app.core.responses import paginated_response, success_response
from app.database import get_db
from app.schemas.kpi import KpiDefinitionCreate, KpiDefinitionUpdate, KpiRecordCreate
from app.services.kpi_service import (
    create_kpi_definition,
    create_kpi_record,
    delete_kpi_definition,
    get_kpi_dashboard,
    get_kpi_definition,
    list_kpi_definitions,
    list_kpi_records,
    update_kpi_definition,
)

router = APIRouter(prefix="/kpi", tags=["KPI"])


@router.get("/definitions", summary="List KPI definitions (scoped)")
async def list_kpi_definitions_endpoint(
    request: Request,
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    entity_type: Optional[str] = Query(None),
    entity_id: Optional[uuid.UUID] = Query(None),
    current_user: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    items, total = list_kpi_definitions(db, current_user, request, page, per_page, entity_type, entity_id)
    data = [
        {
            "id": k.id,
            "name": k.name,
            "description": k.description,
            "entity_type": k.entity_type,
            "entity_id": k.entity_id,
            "target_value": float(k.target_value) if k.target_value is not None else None,
            "target_unit": k.target_unit,
            "period": k.period,
            "is_active": k.is_active,
            "created_by": k.created_by,
            "created_at": k.created_at,
        }
        for k in items
    ]
    return paginated_response(data=data, total=total, page=page, per_page=per_page)


@router.post("/definitions", summary="Create KPI definition", status_code=201)
async def create_kpi_definition_endpoint(
    body: KpiDefinitionCreate,
    current_user: AppUser = Depends(
        require_role("SUPER_ADMIN", "PASTOR", "DEPARTMENT_HEAD", "TEAM_LEADER", "GROUP_LEADER")
    ),
    db: Session = Depends(get_db),
):
    kpi = create_kpi_definition(body, current_user, db)
    return success_response(
        data={
            "id": kpi.id,
            "name": kpi.name,
            "entity_type": kpi.entity_type,
            "entity_id": kpi.entity_id,
            "target_value": float(kpi.target_value) if kpi.target_value is not None else None,
            "period": kpi.period,
            "is_active": kpi.is_active,
        },
        message="KPI definition created.",
    )


@router.put("/definitions/{kpi_id}", summary="Update KPI definition")
async def update_kpi_definition_endpoint(
    kpi_id: uuid.UUID,
    body: KpiDefinitionUpdate,
    current_user: AppUser = Depends(
        require_role("SUPER_ADMIN", "PASTOR", "DEPARTMENT_HEAD", "TEAM_LEADER", "GROUP_LEADER")
    ),
    db: Session = Depends(get_db),
):
    kpi = get_kpi_definition(kpi_id, db)
    kpi = update_kpi_definition(kpi, body, db)
    return success_response(
        data={"id": kpi.id, "name": kpi.name, "is_active": kpi.is_active},
        message="KPI definition updated.",
    )


@router.delete("/definitions/{kpi_id}", summary="Soft delete KPI definition")
async def delete_kpi_definition_endpoint(
    kpi_id: uuid.UUID,
    current_user: AppUser = Depends(require_role("SUPER_ADMIN", "PASTOR")),
    db: Session = Depends(get_db),
):
    kpi = get_kpi_definition(kpi_id, db)
    delete_kpi_definition(kpi, db)
    return success_response(message="KPI definition deleted.")


@router.post("/records", summary="Record KPI value for a period", status_code=201)
async def create_kpi_record_endpoint(
    body: KpiRecordCreate,
    current_user: AppUser = Depends(
        require_role("SUPER_ADMIN", "PASTOR", "DEPARTMENT_HEAD", "TEAM_LEADER", "GROUP_LEADER")
    ),
    db: Session = Depends(get_db),
):
    record = create_kpi_record(body, current_user, db)
    return success_response(
        data={
            "id": record.id,
            "kpi_definition_id": record.kpi_definition_id,
            "period_start": record.period_start,
            "period_end": record.period_end,
            "actual_value": float(record.actual_value) if record.actual_value is not None else None,
            "notes": record.notes,
            "recorded_by": record.recorded_by,
            "created_at": record.created_at,
        },
        message="KPI record saved.",
    )


@router.get("/records", summary="List KPI records")
async def list_kpi_records_endpoint(
    request: Request,
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    kpi_definition_id: Optional[uuid.UUID] = Query(None),
    current_user: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    items, total = list_kpi_records(db, current_user, request, page, per_page, kpi_definition_id)
    data = [
        {
            "id": r.id,
            "kpi_definition_id": r.kpi_definition_id,
            "period_start": r.period_start,
            "period_end": r.period_end,
            "actual_value": float(r.actual_value) if r.actual_value is not None else None,
            "notes": r.notes,
            "recorded_by": r.recorded_by,
            "created_at": r.created_at,
        }
        for r in items
    ]
    return paginated_response(data=data, total=total, page=page, per_page=per_page)


@router.get("/dashboard/{entity_type}/{entity_id}", summary="KPI dashboard for entity")
async def kpi_dashboard_endpoint(
    entity_type: str,
    entity_id: uuid.UUID,
    current_user: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    dashboard = get_kpi_dashboard(entity_type, entity_id, db)
    return success_response(data=dashboard)
