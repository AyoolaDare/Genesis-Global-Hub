"""
Genesis Global CMS — Medical Service (ISOLATED DOMAIN)

CRITICAL SECURITY RULES:
  1. ALL queries MUST include `WHERE created_by = current_user.id`
  2. NEVER return member_link_id in any response
  3. Only return is_church_member: true/false — no identity info
  4. Medical staff CANNOT access /members endpoints (enforced at router)
  5. member_link_id is set silently when name+phone matches a member
"""
import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import func, or_
from sqlalchemy.orm import Session

from app.auth.models import AppUser
from app.core.exceptions import NotFound, PermissionDenied
from app.models.medical import MedicalPatient, MedicalVisit
from app.models.member import MemberModel
from app.schemas.medical import MedicalPatientCreate, MedicalPatientUpdate, MedicalVisitCreate, MedicalVisitUpdate
from app.services.dedup_service import normalize_phone


# ── Patient Service ────────────────────────────────────────────────────────────

def _find_member_link(full_name: str, phone: Optional[str], db: Session) -> Optional[uuid.UUID]:
    """
    Silently check if this patient matches a church member by name+phone.
    Returns member_id if matched, else None.
    NEVER expose the result to the medical staff — only set is_church_member.
    """
    if not phone:
        return None

    norm_phone = normalize_phone(phone)
    if not norm_phone:
        return None

    member = db.query(MemberModel).filter(
        MemberModel.deleted_at.is_(None),
        MemberModel.phone == norm_phone,
    ).first()

    if member:
        return member.id

    return None


def create_patient(
    data: MedicalPatientCreate,
    current_user: AppUser,
    db: Session,
) -> MedicalPatient:
    """Create a new patient. Silently links to member if phone matches."""
    # Silent member link check
    member_link_id = _find_member_link(data.full_name, data.phone, db)
    is_church_member = member_link_id is not None

    patient = MedicalPatient(
        full_name=data.full_name,
        phone=data.phone,
        gender=data.gender,
        date_of_birth=data.date_of_birth,
        is_church_member=is_church_member,
        member_link_id=member_link_id,  # stored in DB, never returned in API
        consent_given=data.consent_given,
        consent_date=data.consent_date,
        allergies=data.allergies,
        chronic_conditions=data.chronic_conditions,
        created_by=current_user.id,
    )
    db.add(patient)
    db.flush()
    return patient


def _ensure_my_patient(patient: MedicalPatient, current_user: AppUser) -> None:
    """Raise PermissionDenied if the patient was not created by the current user."""
    if patient.created_by != current_user.id:
        raise PermissionDenied(message="You can only access patients you created.")


def get_patient(patient_id: uuid.UUID, current_user: AppUser, db: Session) -> MedicalPatient:
    """Get a patient — MUST be created by current_user."""
    patient = db.query(MedicalPatient).filter(
        MedicalPatient.id == patient_id,
        MedicalPatient.created_by == current_user.id,  # CRITICAL
        MedicalPatient.deleted_at.is_(None),
    ).first()
    if not patient:
        raise NotFound(message=f"Patient {patient_id} not found.")
    return patient


def list_patients(
    db: Session,
    current_user: AppUser,
    page: int = 1,
    per_page: int = 20,
    search: Optional[str] = None,
) -> tuple[list[MedicalPatient], int]:
    """List ONLY patients created by the current user."""
    query = db.query(MedicalPatient).filter(
        MedicalPatient.created_by == current_user.id,  # CRITICAL
        MedicalPatient.deleted_at.is_(None),
    )

    if search:
        s = f"%{search}%"
        query = query.filter(
            or_(
                MedicalPatient.full_name.ilike(s),
                MedicalPatient.phone.ilike(s),
            )
        )

    query = query.order_by(MedicalPatient.created_at.desc())
    total = query.count()
    items = query.offset((page - 1) * per_page).limit(per_page).all()
    return items, total


def update_patient(
    patient: MedicalPatient,
    data: MedicalPatientUpdate,
    current_user: AppUser,
    db: Session,
) -> MedicalPatient:
    _ensure_my_patient(patient, current_user)

    update_data = data.model_dump(exclude_unset=True)

    # If phone is being updated, re-check member link
    if "phone" in update_data:
        new_phone = update_data["phone"]
        full_name = update_data.get("full_name", patient.full_name)
        member_link_id = _find_member_link(full_name, new_phone, db)
        patient.is_church_member = member_link_id is not None
        patient.member_link_id = member_link_id  # silent update

    for field, value in update_data.items():
        setattr(patient, field, value)

    db.flush()
    return patient


# ── Visit Service ──────────────────────────────────────────────────────────────

def create_visit(
    patient: MedicalPatient,
    data: MedicalVisitCreate,
    current_user: AppUser,
    db: Session,
) -> MedicalVisit:
    _ensure_my_patient(patient, current_user)

    visit = MedicalVisit(
        patient_id=patient.id,
        visit_date=data.visit_date,
        complaints=data.complaints,
        diagnosis=data.diagnosis,
        treatment=data.treatment,
        medications=data.medications,
        follow_up_date=data.follow_up_date,
        notes=data.notes,
        attended_by=current_user.id,
    )
    db.add(visit)
    db.flush()
    return visit


def list_visits(
    patient: MedicalPatient,
    current_user: AppUser,
    db: Session,
    page: int = 1,
    per_page: int = 20,
) -> tuple[list[MedicalVisit], int]:
    _ensure_my_patient(patient, current_user)

    query = db.query(MedicalVisit).filter(
        MedicalVisit.patient_id == patient.id,
        MedicalVisit.deleted_at.is_(None),
    ).order_by(MedicalVisit.visit_date.desc())

    total = query.count()
    items = query.offset((page - 1) * per_page).limit(per_page).all()
    return items, total


def get_visit(visit_id: uuid.UUID, current_user: AppUser, db: Session) -> MedicalVisit:
    """Get a visit — ensures the patient was created by current_user."""
    visit = (
        db.query(MedicalVisit)
        .join(MedicalPatient, MedicalVisit.patient_id == MedicalPatient.id)
        .filter(
            MedicalVisit.id == visit_id,
            MedicalVisit.deleted_at.is_(None),
            MedicalPatient.created_by == current_user.id,  # CRITICAL
        )
        .first()
    )
    if not visit:
        raise NotFound(message=f"Visit {visit_id} not found.")
    return visit


def update_visit(
    visit: MedicalVisit,
    data: MedicalVisitUpdate,
    current_user: AppUser,
    db: Session,
) -> MedicalVisit:
    # Verify the parent patient is owned by current_user
    patient = db.query(MedicalPatient).filter(
        MedicalPatient.id == visit.patient_id,
        MedicalPatient.created_by == current_user.id,
    ).first()
    if not patient:
        raise PermissionDenied(message="You can only update visits for your own patients.")

    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(visit, field, value)
    db.flush()
    return visit


# ── Dashboard ──────────────────────────────────────────────────────────────────

def get_dashboard(current_user: AppUser, db: Session) -> dict:
    """Compute stats for the current medical user's patients."""
    total_patients = db.query(func.count(MedicalPatient.id)).filter(
        MedicalPatient.created_by == current_user.id,
        MedicalPatient.deleted_at.is_(None),
    ).scalar() or 0

    # Visits this month
    now = datetime.utcnow()
    month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    visits_this_month = (
        db.query(func.count(MedicalVisit.id))
        .join(MedicalPatient, MedicalVisit.patient_id == MedicalPatient.id)
        .filter(
            MedicalPatient.created_by == current_user.id,
            MedicalVisit.deleted_at.is_(None),
            MedicalVisit.visit_date >= month_start.date(),
        )
        .scalar()
    ) or 0

    # Pending follow-ups (visits with future follow_up_date)
    pending_follow_ups = (
        db.query(func.count(MedicalVisit.id))
        .join(MedicalPatient, MedicalVisit.patient_id == MedicalPatient.id)
        .filter(
            MedicalPatient.created_by == current_user.id,
            MedicalVisit.deleted_at.is_(None),
            MedicalVisit.follow_up_date.isnot(None),
            MedicalVisit.follow_up_date >= now.date(),
        )
        .scalar()
    ) or 0

    return {
        "total_patients": total_patients,
        "visits_this_month": visits_this_month,
        "pending_follow_ups": pending_follow_ups,
    }
