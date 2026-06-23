"""
Genesis Global CMS — Medical Records Router (ISOLATED DOMAIN)

CRITICAL SECURITY:
  - ALL endpoints require MEDICAL or SUPER_ADMIN role
  - member_link_id is NEVER returned in any response
  - Only is_church_member: bool is exposed (no identity)

Endpoints:
  GET    /medical/patients               List MY patients
  POST   /medical/patients               Create patient
  GET    /medical/patients/search        Search MY patients
  GET    /medical/patients/{id}          Get patient (must be mine)
  PUT    /medical/patients/{id}          Update patient

  POST   /medical/patients/{id}/visits   Record new visit
  GET    /medical/patients/{id}/visits   Visit history
  GET    /medical/visits/{id}            Single visit
  PUT    /medical/visits/{id}            Update visit

  GET    /medical/dashboard              My patient stats
"""
import uuid
from typing import Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.auth.dependencies import get_current_user, require_role
from app.auth.models import AppUser
from app.core.responses import paginated_response, success_response
from app.database import get_db
from app.schemas.medical import (
    MedicalPatientCreate,
    MedicalPatientUpdate,
    MedicalVisitCreate,
    MedicalVisitUpdate,
)
from app.services.medical_service import (
    create_patient,
    create_visit,
    get_dashboard,
    get_patient,
    get_visit,
    list_patients,
    list_visits,
    update_patient,
    update_visit,
)

router = APIRouter(prefix="/medical", tags=["Medical"])

_MEDICAL_ROLES = ("SUPER_ADMIN", "MEDICAL")


def _serialize_patient(patient) -> dict:
    """Serialize patient WITHOUT member_link_id."""
    return {
        "id": patient.id,
        "full_name": patient.full_name,
        "phone": patient.phone,
        "gender": patient.gender,
        "date_of_birth": patient.date_of_birth,
        "is_church_member": patient.is_church_member,
        "consent_given": patient.consent_given,
        "consent_date": patient.consent_date,
        "allergies": patient.allergies,
        "chronic_conditions": patient.chronic_conditions,
        "created_by": patient.created_by,
        "created_at": patient.created_at,
        "updated_at": patient.updated_at,
        # member_link_id intentionally excluded
    }


def _serialize_visit(visit) -> dict:
    return {
        "id": visit.id,
        "patient_id": visit.patient_id,
        "visit_date": visit.visit_date,
        "complaints": visit.complaints,
        "diagnosis": visit.diagnosis,
        "treatment": visit.treatment,
        "medications": visit.medications,
        "follow_up_date": visit.follow_up_date,
        "notes": visit.notes,
        "attended_by": visit.attended_by,
        "created_at": visit.created_at,
        "updated_at": visit.updated_at,
    }


# ── Patients ───────────────────────────────────────────────────────────────────

@router.get("/patients", summary="List my patients only")
async def list_patients_endpoint(
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    search: Optional[str] = Query(None),
    current_user: AppUser = Depends(require_role(*_MEDICAL_ROLES)),
    db: Session = Depends(get_db),
):
    items, total = list_patients(db, current_user, page, per_page, search)
    data = [_serialize_patient(p) for p in items]
    return paginated_response(data=data, total=total, page=page, per_page=per_page)


@router.post("/patients", summary="Create a new patient", status_code=201)
async def create_patient_endpoint(
    body: MedicalPatientCreate,
    current_user: AppUser = Depends(require_role(*_MEDICAL_ROLES)),
    db: Session = Depends(get_db),
):
    patient = create_patient(body, current_user, db)
    return success_response(
        data=_serialize_patient(patient),
        message="Patient record created.",
    )


@router.get("/patients/search", summary="Search my patients by name or phone")
async def search_patients_endpoint(
    q: str = Query(..., min_length=2),
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    current_user: AppUser = Depends(require_role(*_MEDICAL_ROLES)),
    db: Session = Depends(get_db),
):
    items, total = list_patients(db, current_user, page, per_page, search=q)
    data = [_serialize_patient(p) for p in items]
    return paginated_response(data=data, total=total, page=page, per_page=per_page)


@router.get("/patients/{patient_id}", summary="Get patient (must be my patient)")
async def get_patient_endpoint(
    patient_id: uuid.UUID,
    current_user: AppUser = Depends(require_role(*_MEDICAL_ROLES)),
    db: Session = Depends(get_db),
):
    patient = get_patient(patient_id, current_user, db)
    return success_response(data=_serialize_patient(patient))


@router.put("/patients/{patient_id}", summary="Update patient record")
async def update_patient_endpoint(
    patient_id: uuid.UUID,
    body: MedicalPatientUpdate,
    current_user: AppUser = Depends(require_role(*_MEDICAL_ROLES)),
    db: Session = Depends(get_db),
):
    patient = get_patient(patient_id, current_user, db)
    patient = update_patient(patient, body, current_user, db)
    return success_response(data=_serialize_patient(patient), message="Patient updated.")


# ── Visits ─────────────────────────────────────────────────────────────────────

@router.post("/patients/{patient_id}/visits", summary="Record a new visit", status_code=201)
async def create_visit_endpoint(
    patient_id: uuid.UUID,
    body: MedicalVisitCreate,
    current_user: AppUser = Depends(require_role(*_MEDICAL_ROLES)),
    db: Session = Depends(get_db),
):
    patient = get_patient(patient_id, current_user, db)
    visit = create_visit(patient, body, current_user, db)
    return success_response(data=_serialize_visit(visit), message="Visit recorded.")


@router.get("/patients/{patient_id}/visits", summary="Get visit history for a patient")
async def list_visits_endpoint(
    patient_id: uuid.UUID,
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    current_user: AppUser = Depends(require_role(*_MEDICAL_ROLES)),
    db: Session = Depends(get_db),
):
    patient = get_patient(patient_id, current_user, db)
    items, total = list_visits(patient, current_user, db, page, per_page)
    data = [_serialize_visit(v) for v in items]
    return paginated_response(data=data, total=total, page=page, per_page=per_page)


@router.get("/visits/{visit_id}", summary="Get a single visit")
async def get_visit_endpoint(
    visit_id: uuid.UUID,
    current_user: AppUser = Depends(require_role(*_MEDICAL_ROLES)),
    db: Session = Depends(get_db),
):
    visit = get_visit(visit_id, current_user, db)
    return success_response(data=_serialize_visit(visit))


@router.put("/visits/{visit_id}", summary="Update a visit record")
async def update_visit_endpoint(
    visit_id: uuid.UUID,
    body: MedicalVisitUpdate,
    current_user: AppUser = Depends(require_role(*_MEDICAL_ROLES)),
    db: Session = Depends(get_db),
):
    visit = get_visit(visit_id, current_user, db)
    visit = update_visit(visit, body, current_user, db)
    return success_response(data=_serialize_visit(visit), message="Visit updated.")


# ── Dashboard ──────────────────────────────────────────────────────────────────

@router.get("/dashboard", summary="My patient statistics")
async def medical_dashboard_endpoint(
    current_user: AppUser = Depends(require_role(*_MEDICAL_ROLES)),
    db: Session = Depends(get_db),
):
    stats = get_dashboard(current_user, db)
    return success_response(data=stats)
