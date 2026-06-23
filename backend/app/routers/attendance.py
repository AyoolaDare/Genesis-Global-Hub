"""
Genesis Global CMS — Attendance Router

Endpoints:
  POST   /meetings                         Create meeting
  GET    /meetings                         List meetings (scoped)
  GET    /meetings/{id}                    Get meeting + attendance
  POST   /meetings/{id}/mark               Mark attendance for multiple members
  GET    /meetings/{id}/attendance         Get attendance for meeting
  GET    /members/{id}/attendance          Member attendance history
  GET    /attendance/stats/{type}/{id}     Attendance stats for entity
"""
import uuid
from typing import Optional

from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy.orm import Session

from app.auth.dependencies import get_current_user, require_role
from app.auth.models import AppUser
from app.core.responses import paginated_response, success_response
from app.database import get_db
from app.schemas.attendance import MarkAttendanceRequest, MeetingCreate
from app.services.attendance_service import (
    create_meeting,
    get_attendance_stats,
    get_meeting,
    get_meeting_attendance,
    get_member_attendance_history,
    list_meetings,
    mark_attendance,
)

router = APIRouter(tags=["Attendance"])


@router.post("/meetings", summary="Create a meeting", status_code=201)
async def create_meeting_endpoint(
    body: MeetingCreate,
    current_user: AppUser = Depends(
        require_role("SUPER_ADMIN", "PASTOR", "DEPARTMENT_HEAD", "TEAM_LEADER", "GROUP_LEADER")
    ),
    db: Session = Depends(get_db),
):
    meeting = create_meeting(body, current_user, db)
    return success_response(
        data={
            "id": meeting.id,
            "title": meeting.title,
            "meeting_date": meeting.meeting_date,
            "meeting_type": meeting.meeting_type,
            "entity_id": meeting.entity_id,
            "notes": meeting.notes,
            "created_by": meeting.created_by,
            "created_at": meeting.created_at,
        },
        message="Meeting created.",
    )


@router.get("/meetings", summary="List meetings (scoped by entity)")
async def list_meetings_endpoint(
    request: Request,
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    entity_type: Optional[str] = Query(None),
    entity_id: Optional[uuid.UUID] = Query(None),
    current_user: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    items, total = list_meetings(db, current_user, request, page, per_page, entity_type, entity_id)
    data = [
        {
            "id": m.id,
            "title": m.title,
            "meeting_date": m.meeting_date,
            "meeting_type": m.meeting_type,
            "entity_id": m.entity_id,
            "notes": m.notes,
            "created_by": m.created_by,
            "created_at": m.created_at,
        }
        for m in items
    ]
    return paginated_response(data=data, total=total, page=page, per_page=per_page)


@router.get("/meetings/{meeting_id}", summary="Get meeting with attendance records")
async def get_meeting_endpoint(
    meeting_id: uuid.UUID,
    current_user: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    meeting = get_meeting(meeting_id, db)
    attendance = get_meeting_attendance(meeting_id, db)
    return success_response(data={
        "id": meeting.id,
        "title": meeting.title,
        "meeting_date": meeting.meeting_date,
        "meeting_type": meeting.meeting_type,
        "entity_id": meeting.entity_id,
        "notes": meeting.notes,
        "created_by": meeting.created_by,
        "created_at": meeting.created_at,
        "updated_at": meeting.updated_at,
        "attendance_records": [
            {
                "id": r.id,
                "meeting_id": r.meeting_id,
                "member_id": r.member_id,
                "status": r.status,
                "marked_by": r.marked_by,
                "marked_at": r.marked_at,
                "notes": r.notes,
            }
            for r in attendance
        ],
    })


@router.post("/meetings/{meeting_id}/mark", summary="Mark attendance for multiple members")
async def mark_attendance_endpoint(
    meeting_id: uuid.UUID,
    body: MarkAttendanceRequest,
    current_user: AppUser = Depends(
        require_role("SUPER_ADMIN", "PASTOR", "DEPARTMENT_HEAD", "TEAM_LEADER", "GROUP_LEADER")
    ),
    db: Session = Depends(get_db),
):
    meeting = get_meeting(meeting_id, db)
    records = mark_attendance(meeting, body, current_user, db)
    return success_response(
        data={"marked": len(records), "meeting_id": meeting_id},
        message=f"Attendance marked for {len(records)} member(s).",
    )


@router.get("/meetings/{meeting_id}/attendance", summary="Get attendance list for a meeting")
async def meeting_attendance_endpoint(
    meeting_id: uuid.UUID,
    current_user: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    records = get_meeting_attendance(meeting_id, db)
    data = [
        {
            "id": r.id,
            "member_id": r.member_id,
            "status": r.status,
            "marked_by": r.marked_by,
            "marked_at": r.marked_at,
            "notes": r.notes,
        }
        for r in records
    ]
    return success_response(data=data)


@router.get("/members/{member_id}/attendance", summary="Get attendance history for a member")
async def member_attendance_endpoint(
    member_id: uuid.UUID,
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    current_user: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    history, total = get_member_attendance_history(member_id, db, page, per_page)
    return paginated_response(data=history, total=total, page=page, per_page=per_page)


@router.get(
    "/attendance/stats/{entity_type}/{entity_id}",
    summary="Get attendance statistics for an entity",
)
async def attendance_stats_endpoint(
    entity_type: str,
    entity_id: uuid.UUID,
    current_user: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    stats = get_attendance_stats(entity_type, entity_id, db)
    return success_response(data=stats)
