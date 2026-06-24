"""
Genesis Global CMS — Attendance Service

Business logic for meetings and attendance tracking.
"""
import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.auth.models import AppUser
from app.core.exceptions import NotFound
from app.models.attendance import AttendanceRecord, AttendanceStatusEnum, Meeting
from app.models.member import MemberModel
from app.schemas.attendance import MarkAttendanceRequest, MeetingCreate


# ── Meeting Service ────────────────────────────────────────────────────────────

def create_meeting(data: MeetingCreate, current_user: AppUser, db: Session) -> Meeting:
    meeting = Meeting(
        title=data.title,
        meeting_date=data.meeting_date,
        meeting_type=data.meeting_type,
        entity_id=data.entity_id,
        notes=data.notes,
        created_by=current_user.id,
    )
    db.add(meeting)
    db.flush()
    return meeting


def list_meetings(
    db: Session,
    current_user: AppUser,
    request,
    page: int = 1,
    per_page: int = 20,
    entity_type: Optional[str] = None,
    entity_id: Optional[uuid.UUID] = None,
) -> tuple[list[Meeting], int]:
    query = db.query(Meeting).filter(Meeting.deleted_at.is_(None))

    if entity_type:
        query = query.filter(Meeting.meeting_type == entity_type)
    if entity_id:
        query = query.filter(Meeting.entity_id == entity_id)

    # Scope: non-admin users can only see meetings they created or for their entity
    from app.auth.models import UserRole
    if current_user.role not in (UserRole.SUPER_ADMIN, UserRole.PASTOR):
        payload = getattr(request.state, "token_payload", {})
        scope = payload.get("scope", {}) or {}
        allowed_entities = (
            scope.get("departments", [])
            + scope.get("teams", [])
            + scope.get("groups", [])
        )
        if allowed_entities:
            from sqlalchemy import or_
            query = query.filter(
                or_(
                    Meeting.created_by == current_user.id,
                    Meeting.entity_id.in_([uuid.UUID(i) for i in allowed_entities]),
                )
            )
        else:
            query = query.filter(Meeting.created_by == current_user.id)

    query = query.order_by(Meeting.meeting_date.desc())
    total = query.count()
    items = query.offset((page - 1) * per_page).limit(per_page).all()
    return items, total


def get_meeting(meeting_id: uuid.UUID, db: Session) -> Meeting:
    meeting = db.query(Meeting).filter(
        Meeting.id == meeting_id, Meeting.deleted_at.is_(None)
    ).first()
    if not meeting:
        raise NotFound(message=f"Meeting {meeting_id} not found.")
    return meeting


# ── Attendance Marking ─────────────────────────────────────────────────────────

def mark_attendance(
    meeting: Meeting,
    data: MarkAttendanceRequest,
    current_user: AppUser,
    db: Session,
) -> list[AttendanceRecord]:
    """
    Upsert attendance records for a list of members.
    If a record already exists for (meeting, member), update it.
    """
    now = datetime.utcnow()
    results = []

    for entry in data.attendances:
        # Verify member exists
        member = db.query(MemberModel).filter(
            MemberModel.id == entry.member_id,
            MemberModel.deleted_at.is_(None),
        ).first()
        if not member:
            raise NotFound(message=f"Member {entry.member_id} not found.")

        existing = db.query(AttendanceRecord).filter(
            AttendanceRecord.meeting_id == meeting.id,
            AttendanceRecord.member_id == entry.member_id,
        ).first()

        if existing:
            existing.status = entry.status
            existing.notes = entry.notes
            existing.marked_by = current_user.id
            existing.marked_at = now
            results.append(existing)
        else:
            record = AttendanceRecord(
                meeting_id=meeting.id,
                member_id=entry.member_id,
                status=entry.status,
                marked_by=current_user.id,
                marked_at=now,
                notes=entry.notes,
            )
            db.add(record)
            results.append(record)

    db.flush()
    return results


def get_meeting_attendance(
    meeting_id: uuid.UUID,
    db: Session,
) -> list[AttendanceRecord]:
    return (
        db.query(AttendanceRecord)
        .filter(AttendanceRecord.meeting_id == meeting_id)
        .order_by(AttendanceRecord.created_at)
        .all()
    )


def get_member_attendance_history(
    member_id: uuid.UUID,
    db: Session,
    page: int = 1,
    per_page: int = 20,
) -> tuple[list[dict], int]:
    """Return attendance history with meeting details."""
    query = (
        db.query(AttendanceRecord, Meeting)
        .join(Meeting, AttendanceRecord.meeting_id == Meeting.id)
        .filter(
            AttendanceRecord.member_id == member_id,
            Meeting.deleted_at.is_(None),
        )
        .order_by(Meeting.meeting_date.desc())
    )

    total = query.count()
    rows = query.offset((page - 1) * per_page).limit(per_page).all()

    result = []
    for record, meeting in rows:
        result.append({
            "meeting_id": meeting.id,
            "meeting_title": meeting.title,
            "meeting_date": meeting.meeting_date,
            "meeting_type": meeting.meeting_type,
            "status": record.status,
            "notes": record.notes,
        })
    return result, total


# ── Attendance Stats ───────────────────────────────────────────────────────────

def get_attendance_stats(
    entity_type: str,
    entity_id: uuid.UUID,
    db: Session,
) -> dict:
    """
    Compute attendance statistics for a department/team/group.

    Returns overall stats and per-member attendance rates.
    """
    # Get all meetings for this entity
    meetings = db.query(Meeting).filter(
        Meeting.meeting_type == entity_type,
        Meeting.entity_id == entity_id,
        Meeting.deleted_at.is_(None),
    ).all()

    total_meetings = len(meetings)
    if total_meetings == 0:
        return {
            "entity_type": entity_type,
            "entity_id": entity_id,
            "total_meetings": 0,
            "avg_attendance_rate": 0.0,
            "members": [],
        }

    meeting_ids = [m.id for m in meetings]

    # Get all attendance records for these meetings
    _ = (
        db.query(
            AttendanceRecord.member_id,
            MemberModel.full_name,
            func.count(AttendanceRecord.id).label("total"),
            func.sum(
                func.cast(AttendanceRecord.status == AttendanceStatusEnum.PRESENT, db.bind.dialect.type_descriptor(func.count().type).__class__)
            ).label("present_count"),
        )
        .join(MemberModel, AttendanceRecord.member_id == MemberModel.id)
        .filter(AttendanceRecord.meeting_id.in_(meeting_ids))
        .group_by(AttendanceRecord.member_id, MemberModel.full_name)
        .all()
    )

    # Simpler approach — raw count query
    from sqlalchemy import case
    member_stats = (
        db.query(
            AttendanceRecord.member_id,
            MemberModel.full_name,
            func.count(AttendanceRecord.id).label("total"),
            func.count(
                case((AttendanceRecord.status == "PRESENT", AttendanceRecord.id))
            ).label("attended"),
        )
        .join(MemberModel, AttendanceRecord.member_id == MemberModel.id)
        .filter(AttendanceRecord.meeting_id.in_(meeting_ids))
        .group_by(AttendanceRecord.member_id, MemberModel.full_name)
        .all()
    )

    member_rates = []
    total_rate_sum = 0.0

    for row in member_stats:
        rate = (row.attended / total_meetings * 100.0) if total_meetings > 0 else 0.0
        total_rate_sum += rate
        member_rates.append({
            "member_id": row.member_id,
            "member_name": row.full_name,
            "total_meetings": total_meetings,
            "attended": row.attended,
            "rate": round(rate, 1),
        })

    avg_rate = round(total_rate_sum / len(member_rates), 1) if member_rates else 0.0

    return {
        "entity_type": entity_type,
        "entity_id": entity_id,
        "total_meetings": total_meetings,
        "avg_attendance_rate": avg_rate,
        "members": sorted(member_rates, key=lambda x: x["rate"], reverse=True),
    }
