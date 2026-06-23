"""
Genesis Global CMS — HR & Volunteers Router (ISOLATED DOMAIN)

CRITICAL:
  - member_link_id NEVER returned
  - NO salary fields
  - HR_ADMIN and SUPER_ADMIN only

Endpoints:
  GET    /hr/workers                     List workers
  POST   /hr/workers                     Create worker
  GET    /hr/workers/{id}                Worker detail
  PUT    /hr/workers/{id}                Update worker

  POST   /hr/workers/{id}/reviews        Create review
  GET    /hr/workers/{id}/reviews        Review history
  GET    /hr/workers/{id}/reviews/{rid}  Single review

  POST   /hr/workers/{id}/leave          Submit leave request
  GET    /hr/workers/{id}/leave          Leave history
  PUT    /hr/leave/{id}/approve          Approve/reject leave

  POST   /hr/workers/{id}/recognitions   Award recognition
  GET    /hr/workers/{id}/recognitions   Recognition history

  GET    /hr/dashboard                   HR dashboard
"""
import uuid
from typing import Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.auth.dependencies import get_current_user, require_role
from app.auth.models import AppUser
from app.core.responses import paginated_response, success_response
from app.database import get_db
from app.schemas.hr import (
    LeaveApprovalRequest,
    LeaveRequestCreate,
    RecognitionCreate,
    WorkerCreate,
    WorkerReviewCreate,
    WorkerUpdate,
)
from app.services.hr_service import (
    approve_leave_request,
    award_recognition,
    create_leave_request,
    create_review,
    create_worker,
    get_hr_dashboard,
    get_leave_request,
    get_review,
    get_worker,
    list_leave_requests,
    list_recognitions,
    list_reviews,
    list_workers,
    update_worker,
)

router = APIRouter(prefix="/hr", tags=["HR & Volunteers"])

_HR_ROLES = ("SUPER_ADMIN", "HR_ADMIN")


def _serialize_worker(worker) -> dict:
    """Serialize worker WITHOUT member_link_id."""
    return {
        "id": worker.id,
        "full_name": worker.full_name,
        "phone": worker.phone,
        "email": worker.email,
        "department_id": worker.department_id,
        "role_title": worker.role_title,
        "employment_type": worker.employment_type,
        "start_date": worker.start_date,
        "status": worker.status,
        "time_commitment_hours_per_week": worker.time_commitment_hours_per_week,
        "skills": worker.skills,
        "interests": worker.interests,
        "created_by": worker.created_by,
        "created_at": worker.created_at,
        "updated_at": worker.updated_at,
        # member_link_id intentionally excluded
    }


# ── Workers ────────────────────────────────────────────────────────────────────

@router.get("/workers", summary="List workers (HR Admin only)")
async def list_workers_endpoint(
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    search: Optional[str] = Query(None),
    department_id: Optional[uuid.UUID] = Query(None),
    employment_type: Optional[str] = Query(None),
    status: Optional[str] = Query(None),
    current_user: AppUser = Depends(require_role(*_HR_ROLES)),
    db: Session = Depends(get_db),
):
    items, total = list_workers(db, page, per_page, search, department_id, employment_type, status)
    data = [_serialize_worker(w) for w in items]
    return paginated_response(data=data, total=total, page=page, per_page=per_page)


@router.post("/workers", summary="Create a worker record", status_code=201)
async def create_worker_endpoint(
    body: WorkerCreate,
    current_user: AppUser = Depends(require_role(*_HR_ROLES)),
    db: Session = Depends(get_db),
):
    worker = create_worker(body, current_user, db)
    return success_response(data=_serialize_worker(worker), message="Worker record created.")


@router.get("/workers/{worker_id}", summary="Get worker detail")
async def get_worker_endpoint(
    worker_id: uuid.UUID,
    current_user: AppUser = Depends(require_role(*_HR_ROLES)),
    db: Session = Depends(get_db),
):
    worker = get_worker(worker_id, db)
    return success_response(data=_serialize_worker(worker))


@router.put("/workers/{worker_id}", summary="Update worker record")
async def update_worker_endpoint(
    worker_id: uuid.UUID,
    body: WorkerUpdate,
    current_user: AppUser = Depends(require_role(*_HR_ROLES)),
    db: Session = Depends(get_db),
):
    worker = get_worker(worker_id, db)
    worker = update_worker(worker, body, db)
    return success_response(data=_serialize_worker(worker), message="Worker updated.")


# ── Reviews ────────────────────────────────────────────────────────────────────

@router.post("/workers/{worker_id}/reviews", summary="Create performance review", status_code=201)
async def create_review_endpoint(
    worker_id: uuid.UUID,
    body: WorkerReviewCreate,
    current_user: AppUser = Depends(require_role(*_HR_ROLES)),
    db: Session = Depends(get_db),
):
    worker = get_worker(worker_id, db)
    review = create_review(worker, body, current_user, db)
    return success_response(data={
        "id": review.id,
        "worker_id": review.worker_id,
        "review_period_start": review.review_period_start,
        "review_period_end": review.review_period_end,
        "reviewer_id": review.reviewer_id,
        "overall_score": float(review.overall_score) if review.overall_score else None,
        "created_at": review.created_at,
    }, message="Performance review created.")


@router.get("/workers/{worker_id}/reviews", summary="Review history for a worker")
async def list_reviews_endpoint(
    worker_id: uuid.UUID,
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    current_user: AppUser = Depends(require_role(*_HR_ROLES)),
    db: Session = Depends(get_db),
):
    items, total = list_reviews(worker_id, db, page, per_page)
    data = [
        {
            "id": r.id,
            "worker_id": r.worker_id,
            "review_period_start": r.review_period_start,
            "review_period_end": r.review_period_end,
            "reviewer_id": r.reviewer_id,
            "self_score": r.self_score,
            "peer_score": float(r.peer_score) if r.peer_score else None,
            "supervisor_score": r.supervisor_score,
            "overall_score": float(r.overall_score) if r.overall_score else None,
            "strengths": r.strengths,
            "areas_for_growth": r.areas_for_growth,
            "goals": r.goals,
            "notes": r.notes,
            "created_at": r.created_at,
        }
        for r in items
    ]
    return paginated_response(data=data, total=total, page=page, per_page=per_page)


@router.get("/workers/{worker_id}/reviews/{review_id}", summary="Get a single review")
async def get_review_endpoint(
    worker_id: uuid.UUID,
    review_id: uuid.UUID,
    current_user: AppUser = Depends(require_role(*_HR_ROLES)),
    db: Session = Depends(get_db),
):
    review = get_review(review_id, db)
    return success_response(data={
        "id": review.id,
        "worker_id": review.worker_id,
        "review_period_start": review.review_period_start,
        "review_period_end": review.review_period_end,
        "reviewer_id": review.reviewer_id,
        "self_score": review.self_score,
        "peer_score": float(review.peer_score) if review.peer_score else None,
        "supervisor_score": review.supervisor_score,
        "overall_score": float(review.overall_score) if review.overall_score else None,
        "strengths": review.strengths,
        "areas_for_growth": review.areas_for_growth,
        "goals": review.goals,
        "notes": review.notes,
        "created_at": review.created_at,
        "updated_at": review.updated_at,
    })


# ── Leave Requests ─────────────────────────────────────────────────────────────

@router.post("/workers/{worker_id}/leave", summary="Submit leave request", status_code=201)
async def create_leave_endpoint(
    worker_id: uuid.UUID,
    body: LeaveRequestCreate,
    current_user: AppUser = Depends(require_role(*_HR_ROLES)),
    db: Session = Depends(get_db),
):
    worker = get_worker(worker_id, db)
    leave = create_leave_request(worker, body, db)
    return success_response(data={
        "id": leave.id,
        "worker_id": leave.worker_id,
        "leave_type": leave.leave_type,
        "start_date": leave.start_date,
        "end_date": leave.end_date,
        "reason": leave.reason,
        "status": leave.status,
        "created_at": leave.created_at,
    }, message="Leave request submitted.")


@router.get("/workers/{worker_id}/leave", summary="Leave history for a worker")
async def list_leave_endpoint(
    worker_id: uuid.UUID,
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    current_user: AppUser = Depends(require_role(*_HR_ROLES)),
    db: Session = Depends(get_db),
):
    items, total = list_leave_requests(worker_id, db, page, per_page)
    data = [
        {
            "id": l.id,
            "worker_id": l.worker_id,
            "leave_type": l.leave_type,
            "start_date": l.start_date,
            "end_date": l.end_date,
            "reason": l.reason,
            "status": l.status,
            "approved_by": l.approved_by,
            "approved_at": l.approved_at,
            "created_at": l.created_at,
        }
        for l in items
    ]
    return paginated_response(data=data, total=total, page=page, per_page=per_page)


@router.put("/leave/{leave_id}/approve", summary="Approve or reject a leave request")
async def approve_leave_endpoint(
    leave_id: uuid.UUID,
    body: LeaveApprovalRequest,
    current_user: AppUser = Depends(require_role(*_HR_ROLES)),
    db: Session = Depends(get_db),
):
    leave = get_leave_request(leave_id, db)
    leave = approve_leave_request(leave, body, current_user, db)
    return success_response(data={
        "id": leave.id,
        "status": leave.status,
        "approved_by": leave.approved_by,
        "approved_at": leave.approved_at,
    }, message=f"Leave request {leave.status.lower()}.")


# ── Recognitions ───────────────────────────────────────────────────────────────

@router.post("/workers/{worker_id}/recognitions", summary="Award recognition to worker", status_code=201)
async def award_recognition_endpoint(
    worker_id: uuid.UUID,
    body: RecognitionCreate,
    current_user: AppUser = Depends(require_role(*_HR_ROLES)),
    db: Session = Depends(get_db),
):
    worker = get_worker(worker_id, db)
    recognition = award_recognition(worker, body, current_user, db)
    return success_response(data={
        "id": recognition.id,
        "worker_id": recognition.worker_id,
        "recognition_type": recognition.recognition_type,
        "title": recognition.title,
        "description": recognition.description,
        "awarded_by": recognition.awarded_by,
        "awarded_at": recognition.awarded_at,
        "created_at": recognition.created_at,
    }, message="Recognition awarded.")


@router.get("/workers/{worker_id}/recognitions", summary="Recognition history for a worker")
async def list_recognitions_endpoint(
    worker_id: uuid.UUID,
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    current_user: AppUser = Depends(require_role(*_HR_ROLES)),
    db: Session = Depends(get_db),
):
    items, total = list_recognitions(worker_id, db, page, per_page)
    data = [
        {
            "id": r.id,
            "worker_id": r.worker_id,
            "recognition_type": r.recognition_type,
            "title": r.title,
            "description": r.description,
            "awarded_by": r.awarded_by,
            "awarded_at": r.awarded_at,
            "created_at": r.created_at,
        }
        for r in items
    ]
    return paginated_response(data=data, total=total, page=page, per_page=per_page)


# ── Dashboard ──────────────────────────────────────────────────────────────────

@router.get("/dashboard", summary="HR dashboard")
async def hr_dashboard_endpoint(
    current_user: AppUser = Depends(require_role(*_HR_ROLES)),
    db: Session = Depends(get_db),
):
    dashboard = get_hr_dashboard(db)
    return success_response(data=dashboard)
