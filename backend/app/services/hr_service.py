"""
Genesis Global CMS — HR Service (ISOLATED DOMAIN)

CRITICAL:
  - NEVER return member_link_id in any response
  - NO salary fields anywhere
  - Only HR_ADMIN/SUPER_ADMIN can access this domain
"""
import uuid
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import func, or_
from sqlalchemy.orm import Session

from app.auth.models import AppUser
from app.core.exceptions import NotFound, PermissionDenied
from app.models.hr import (
    EmploymentTypeEnum,
    Worker,
    WorkerLeaveRequest,
    WorkerPerformanceReview,
    WorkerRecognition,
)
from app.models.structure import Department
from app.schemas.hr import (
    LeaveApprovalRequest,
    LeaveRequestCreate,
    RecognitionCreate,
    WorkerCreate,
    WorkerReviewCreate,
    WorkerUpdate,
)
from app.services.dedup_service import normalize_phone
from app.models.member import MemberModel


# ── Worker Service ─────────────────────────────────────────────────────────────

def _find_member_link(phone: Optional[str], db: Session) -> Optional[uuid.UUID]:
    """Silently check if this worker matches a church member by phone."""
    if not phone:
        return None
    norm_phone = normalize_phone(phone)
    if not norm_phone:
        return None
    member = db.query(MemberModel).filter(
        MemberModel.deleted_at.is_(None),
        MemberModel.phone == norm_phone,
    ).first()
    return member.id if member else None


def list_workers(
    db: Session,
    page: int = 1,
    per_page: int = 20,
    search: Optional[str] = None,
    department_id: Optional[uuid.UUID] = None,
    employment_type: Optional[str] = None,
    status: Optional[str] = None,
) -> tuple[list[Worker], int]:
    query = db.query(Worker).filter(Worker.deleted_at.is_(None))

    if search:
        s = f"%{search}%"
        query = query.filter(
            or_(
                Worker.full_name.ilike(s),
                Worker.phone.ilike(s),
                Worker.email.ilike(s),
            )
        )

    if department_id:
        query = query.filter(Worker.department_id == department_id)

    if employment_type:
        query = query.filter(Worker.employment_type == employment_type)

    if status:
        query = query.filter(Worker.status == status)

    query = query.order_by(Worker.full_name)
    total = query.count()
    items = query.offset((page - 1) * per_page).limit(per_page).all()
    return items, total


def get_worker(worker_id: uuid.UUID, db: Session) -> Worker:
    worker = db.query(Worker).filter(
        Worker.id == worker_id, Worker.deleted_at.is_(None)
    ).first()
    if not worker:
        raise NotFound(message=f"Worker {worker_id} not found.")
    return worker


def create_worker(
    data: WorkerCreate,
    current_user: AppUser,
    db: Session,
) -> Worker:
    member_link_id = _find_member_link(data.phone, db)

    worker = Worker(
        full_name=data.full_name,
        phone=data.phone,
        email=str(data.email).lower() if data.email else None,
        department_id=data.department_id,
        role_title=data.role_title,
        employment_type=data.employment_type,
        start_date=data.start_date,
        status="ACTIVE",
        time_commitment_hours_per_week=data.time_commitment_hours_per_week,
        skills=data.skills,
        interests=data.interests,
        member_link_id=member_link_id,  # backend-only, never returned
        created_by=current_user.id,
    )
    db.add(worker)
    db.flush()
    return worker


def update_worker(
    worker: Worker,
    data: WorkerUpdate,
    db: Session,
) -> Worker:
    update_data = data.model_dump(exclude_unset=True)

    # Re-check member link if phone changes
    if "phone" in update_data:
        member_link_id = _find_member_link(update_data["phone"], db)
        worker.member_link_id = member_link_id

    for field, value in update_data.items():
        setattr(worker, field, value)
    db.flush()
    return worker


# ── Review Service ─────────────────────────────────────────────────────────────

def create_review(
    worker: Worker,
    data: WorkerReviewCreate,
    current_user: AppUser,
    db: Session,
) -> WorkerPerformanceReview:
    review = WorkerPerformanceReview(
        worker_id=worker.id,
        review_period_start=data.review_period_start,
        review_period_end=data.review_period_end,
        reviewer_id=current_user.id,
        self_score=data.self_score,
        peer_score=data.peer_score,
        supervisor_score=data.supervisor_score,
        overall_score=data.overall_score,
        strengths=data.strengths,
        areas_for_growth=data.areas_for_growth,
        goals=data.goals,
        notes=data.notes,
    )
    db.add(review)
    db.flush()
    return review


def list_reviews(
    worker_id: uuid.UUID,
    db: Session,
    page: int = 1,
    per_page: int = 20,
) -> tuple[list[WorkerPerformanceReview], int]:
    query = db.query(WorkerPerformanceReview).filter(
        WorkerPerformanceReview.worker_id == worker_id
    ).order_by(WorkerPerformanceReview.review_period_start.desc())

    total = query.count()
    items = query.offset((page - 1) * per_page).limit(per_page).all()
    return items, total


def get_review(review_id: uuid.UUID, db: Session) -> WorkerPerformanceReview:
    review = db.query(WorkerPerformanceReview).filter(
        WorkerPerformanceReview.id == review_id
    ).first()
    if not review:
        raise NotFound(message=f"Review {review_id} not found.")
    return review


# ── Leave Service ──────────────────────────────────────────────────────────────

def create_leave_request(
    worker: Worker,
    data: LeaveRequestCreate,
    db: Session,
) -> WorkerLeaveRequest:
    leave = WorkerLeaveRequest(
        worker_id=worker.id,
        leave_type=data.leave_type,
        start_date=data.start_date,
        end_date=data.end_date,
        reason=data.reason,
        status="PENDING",
    )
    db.add(leave)
    db.flush()
    return leave


def list_leave_requests(
    worker_id: uuid.UUID,
    db: Session,
    page: int = 1,
    per_page: int = 20,
) -> tuple[list[WorkerLeaveRequest], int]:
    query = db.query(WorkerLeaveRequest).filter(
        WorkerLeaveRequest.worker_id == worker_id
    ).order_by(WorkerLeaveRequest.start_date.desc())

    total = query.count()
    items = query.offset((page - 1) * per_page).limit(per_page).all()
    return items, total


def get_leave_request(leave_id: uuid.UUID, db: Session) -> WorkerLeaveRequest:
    leave = db.query(WorkerLeaveRequest).filter(
        WorkerLeaveRequest.id == leave_id
    ).first()
    if not leave:
        raise NotFound(message=f"Leave request {leave_id} not found.")
    return leave


def approve_leave_request(
    leave: WorkerLeaveRequest,
    data: LeaveApprovalRequest,
    current_user: AppUser,
    db: Session,
) -> WorkerLeaveRequest:
    if leave.status != "PENDING":
        raise PermissionDenied(
            message=f"Cannot process a leave request with status '{leave.status}'."
        )

    leave.status = data.status
    leave.approved_by = current_user.id
    leave.approved_at = datetime.now(timezone.utc)

    if data.status == "APPROVED":
        # Update worker status if on leave
        worker = get_worker(leave.worker_id, db)
        worker.status = "ON_LEAVE"

    db.flush()
    return leave


# ── Recognition Service ────────────────────────────────────────────────────────

def award_recognition(
    worker: Worker,
    data: RecognitionCreate,
    current_user: AppUser,
    db: Session,
) -> WorkerRecognition:
    recognition = WorkerRecognition(
        worker_id=worker.id,
        recognition_type=data.recognition_type,
        title=data.title,
        description=data.description,
        awarded_by=current_user.id,
        awarded_at=data.awarded_at or datetime.now(timezone.utc),
    )
    db.add(recognition)
    db.flush()
    return recognition


def list_recognitions(
    worker_id: uuid.UUID,
    db: Session,
    page: int = 1,
    per_page: int = 20,
) -> tuple[list[WorkerRecognition], int]:
    query = db.query(WorkerRecognition).filter(
        WorkerRecognition.worker_id == worker_id
    ).order_by(WorkerRecognition.awarded_at.desc())

    total = query.count()
    items = query.offset((page - 1) * per_page).limit(per_page).all()
    return items, total


# ── HR Dashboard ───────────────────────────────────────────────────────────────

def get_hr_dashboard(db: Session) -> dict:
    total_workers = db.query(func.count(Worker.id)).filter(
        Worker.deleted_at.is_(None)
    ).scalar() or 0

    active_workers = db.query(func.count(Worker.id)).filter(
        Worker.deleted_at.is_(None),
        Worker.status == "ACTIVE",
    ).scalar() or 0

    volunteers = db.query(func.count(Worker.id)).filter(
        Worker.deleted_at.is_(None),
        Worker.employment_type == EmploymentTypeEnum.VOLUNTEER,
    ).scalar() or 0

    pending_leave = db.query(func.count(WorkerLeaveRequest.id)).filter(
        WorkerLeaveRequest.status == "PENDING"
    ).scalar() or 0

    # By department
    dept_counts = (
        db.query(
            Worker.department_id,
            Department.name.label("department_name"),
            func.count(Worker.id).label("count"),
        )
        .outerjoin(Department, Worker.department_id == Department.id)
        .filter(Worker.deleted_at.is_(None))
        .group_by(Worker.department_id, Department.name)
        .all()
    )

    by_department = [
        {
            "department_id": row.department_id,
            "department_name": row.department_name or "Unassigned",
            "count": row.count,
        }
        for row in dept_counts
    ]

    return {
        "total_workers": total_workers,
        "active_workers": active_workers,
        "volunteers": volunteers,
        "pending_leave": pending_leave,
        "dept_breakdown": by_department,
        "pending_leave_requests": [],
    }
