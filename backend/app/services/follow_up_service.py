"""
Genesis Global CMS — Follow-Up Service

Business logic for follow-up contacts, tasks, and notes.
Includes auto-task creation on contact registration.
"""
import uuid
from datetime import datetime, timedelta, timezone
from typing import Optional

from sqlalchemy import func, or_
from sqlalchemy.orm import Session

from app.auth.models import AppUser, UserRole
from app.core.exceptions import NotFound, PermissionDenied
from app.models.follow_up import FollowUpContact, FollowUpNote, FollowUpStageEnum, FollowUpTask
from app.schemas.follow_up import (
    EscalateTaskRequest,
    FollowUpContactCreate,
    FollowUpNoteCreate,
    FollowUpTaskCreate,
    FollowUpTaskUpdate,
)
from app.services.notification_service import queue_notification


# ── Contact Service ────────────────────────────────────────────────────────────

def create_contact(
    data: FollowUpContactCreate,
    current_user: AppUser,
    db: Session,
) -> FollowUpContact:
    """Register a new follow-up contact and auto-create a task."""
    contact = FollowUpContact(
        full_name=data.full_name,
        phone=data.phone,
        address=data.address,
        prayer_requests=data.prayer_requests,
        how_heard=data.how_heard,
        registered_by=current_user.id,
    )
    db.add(contact)
    db.flush()

    # Auto-create follow-up task
    assigned_worker = _pick_follow_up_worker(db)

    if assigned_worker:
        task = FollowUpTask(
            contact_id=contact.id,
            assigned_to=assigned_worker.id,
            stage=FollowUpStageEnum.FIRST_CONTACT,
            due_date=datetime.now(timezone.utc) + timedelta(hours=72),
        )
        db.add(task)
        db.flush()

        # Notify the assigned worker
        queue_notification(
            db=db,
            recipient_type="USER",
            recipient_id=assigned_worker.id,
            channel="SMS",
            template_key="FOLLOW_UP_TASK_ASSIGNED",
            payload={
                "contact_name": contact.full_name,
                "contact_phone": contact.phone or "N/A",
                "due_date": task.due_date.isoformat() if task.due_date else None,
            },
        )

    return contact


def _pick_follow_up_worker(db: Session) -> Optional[AppUser]:
    """
    Round-robin selection: pick the follow-up worker with the fewest active tasks.
    Falls back to any active FOLLOW_UP user if none have tasks.
    """
    from app.auth.models import AppUser

    # Count active tasks per follow-up worker
    worker_task_counts = (
        db.query(
            FollowUpTask.assigned_to,
            func.count(FollowUpTask.id).label("task_count"),
        )
        .filter(
            FollowUpTask.completed_at.is_(None),
            FollowUpTask.deleted_at.is_(None),
        )
        .group_by(FollowUpTask.assigned_to)
        .subquery()
    )

    # Get all active follow-up users with their task count
    worker = (
        db.query(AppUser)
        .outerjoin(worker_task_counts, AppUser.id == worker_task_counts.c.assigned_to)
        .filter(
            AppUser.role == UserRole.FOLLOW_UP,
            AppUser.is_active.is_(True),
        )
        .order_by(
            func.coalesce(worker_task_counts.c.task_count, 0).asc()
        )
        .first()
    )
    return worker


def list_contacts(
    db: Session,
    current_user: AppUser,
    page: int = 1,
    per_page: int = 20,
    search: Optional[str] = None,
) -> tuple[list[FollowUpContact], int]:
    query = db.query(FollowUpContact).filter(FollowUpContact.deleted_at.is_(None))

    # Admin sees all; follow-up worker sees all contacts (they handle them all)
    # Contacts are not scoped by assignment — all follow-up staff can see them

    if search:
        s = f"%{search}%"
        query = query.filter(
            or_(
                FollowUpContact.full_name.ilike(s),
                FollowUpContact.phone.ilike(s),
            )
        )

    query = query.order_by(FollowUpContact.created_at.desc())
    total = query.count()
    items = query.offset((page - 1) * per_page).limit(per_page).all()
    return items, total


def get_contact(contact_id: uuid.UUID, db: Session) -> FollowUpContact:
    contact = db.query(FollowUpContact).filter(
        FollowUpContact.id == contact_id,
        FollowUpContact.deleted_at.is_(None),
    ).first()
    if not contact:
        raise NotFound(message=f"Contact {contact_id} not found.")
    return contact


# ── Task Service ───────────────────────────────────────────────────────────────

def create_task(
    data: FollowUpTaskCreate,
    current_user: AppUser,
    db: Session,
) -> FollowUpTask:
    # Verify contact exists
    get_contact(data.contact_id, db)

    task = FollowUpTask(
        contact_id=data.contact_id,
        assigned_to=data.assigned_to,
        stage=data.stage,
        due_date=data.due_date,
        notes=data.notes,
    )
    db.add(task)
    db.flush()
    return task


def list_tasks(
    db: Session,
    current_user: AppUser,
    page: int = 1,
    per_page: int = 20,
    search: Optional[str] = None,
) -> tuple[list[dict], int]:
    """List tasks. Follow-up workers see only their own; admins see all."""
    query = db.query(FollowUpTask, FollowUpContact).join(
        FollowUpContact, FollowUpTask.contact_id == FollowUpContact.id
    ).filter(
        FollowUpTask.deleted_at.is_(None),
        FollowUpContact.deleted_at.is_(None),
    )

    if current_user.role == UserRole.FOLLOW_UP:
        query = query.filter(FollowUpTask.assigned_to == current_user.id)

    if search:
        s = f"%{search}%"
        query = query.filter(FollowUpContact.full_name.ilike(s))

    query = query.order_by(FollowUpTask.due_date.asc())
    total = query.count()
    rows = query.offset((page - 1) * per_page).limit(per_page).all()

    result = []
    for task, contact in rows:
        t = {
            "id": task.id,
            "contact_id": task.contact_id,
            "member_id": task.member_id,
            "assigned_to": task.assigned_to,
            "stage": task.stage,
            "due_date": task.due_date,
            "completed_at": task.completed_at,
            "notes": task.notes,
            "escalated_at": task.escalated_at,
            "escalated_to": task.escalated_to,
            "created_at": task.created_at,
            "updated_at": task.updated_at,
            "contact_name": contact.full_name,
            "contact_phone": contact.phone,
        }
        result.append(t)
    return result, total


def list_tasks_today(db: Session, current_user: AppUser) -> list[dict]:
    """List tasks due today for the current follow-up worker."""
    today_start = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
    today_end = today_start + timedelta(days=1)

    rows = (
        db.query(FollowUpTask, FollowUpContact)
        .join(FollowUpContact, FollowUpTask.contact_id == FollowUpContact.id)
        .filter(
            FollowUpTask.assigned_to == current_user.id,
            FollowUpTask.completed_at.is_(None),
            FollowUpTask.deleted_at.is_(None),
            FollowUpTask.due_date >= today_start,
            FollowUpTask.due_date < today_end,
        )
        .order_by(FollowUpTask.due_date.asc())
        .all()
    )

    result = []
    for task, contact in rows:
        result.append({
            "id": task.id,
            "contact_id": task.contact_id,
            "assigned_to": task.assigned_to,
            "stage": task.stage,
            "due_date": task.due_date,
            "notes": task.notes,
            "created_at": task.created_at,
            "updated_at": task.updated_at,
            "contact_name": contact.full_name,
            "contact_phone": contact.phone,
        })
    return result


def list_overdue_tasks(db: Session) -> list[dict]:
    """List tasks past due date that are not completed."""
    now = datetime.now(timezone.utc)

    rows = (
        db.query(FollowUpTask, FollowUpContact)
        .join(FollowUpContact, FollowUpTask.contact_id == FollowUpContact.id)
        .filter(
            FollowUpTask.completed_at.is_(None),
            FollowUpTask.deleted_at.is_(None),
            FollowUpTask.due_date < now,
        )
        .order_by(FollowUpTask.due_date.asc())
        .all()
    )

    result = []
    for task, contact in rows:
        result.append({
            "id": task.id,
            "contact_id": task.contact_id,
            "assigned_to": task.assigned_to,
            "stage": task.stage,
            "due_date": task.due_date,
            "escalated_at": task.escalated_at,
            "notes": task.notes,
            "created_at": task.created_at,
            "updated_at": task.updated_at,
            "contact_name": contact.full_name,
            "contact_phone": contact.phone,
        })
    return result


def get_task(task_id: uuid.UUID, db: Session) -> FollowUpTask:
    task = db.query(FollowUpTask).filter(
        FollowUpTask.id == task_id, FollowUpTask.deleted_at.is_(None)
    ).first()
    if not task:
        raise NotFound(message=f"Task {task_id} not found.")
    return task


def update_task(
    task: FollowUpTask,
    data: FollowUpTaskUpdate,
    current_user: AppUser,
    db: Session,
) -> FollowUpTask:
    # Follow-up workers can only update tasks assigned to them
    if current_user.role == UserRole.FOLLOW_UP and task.assigned_to != current_user.id:
        raise PermissionDenied(message="You can only update tasks assigned to you.")

    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(task, field, value)
    db.flush()
    return task


def complete_task(
    task: FollowUpTask,
    current_user: AppUser,
    db: Session,
) -> FollowUpTask:
    if current_user.role == UserRole.FOLLOW_UP and task.assigned_to != current_user.id:
        raise PermissionDenied(message="You can only complete tasks assigned to you.")

    task.completed_at = datetime.now(timezone.utc)
    db.flush()
    return task


def escalate_task(
    task: FollowUpTask,
    data: EscalateTaskRequest,
    current_user: AppUser,
    db: Session,
) -> FollowUpTask:
    """Escalate a task to a supervisor."""
    task.escalated_at = datetime.now(timezone.utc)
    task.escalated_to = data.escalate_to

    if data.reason:
        task.notes = (task.notes or "") + f"\n[ESCALATION]: {data.reason}"

    db.flush()

    # Notify supervisor
    queue_notification(
        db=db,
        recipient_type="USER",
        recipient_id=data.escalate_to,
        channel="IN_APP",
        template_key="TASK_ESCALATED",
        payload={
            "task_id": str(task.id),
            "escalated_by": str(current_user.id),
            "reason": data.reason or "",
        },
    )

    return task


# ── Notes Service ──────────────────────────────────────────────────────────────

def create_note(
    data: FollowUpNoteCreate,
    current_user: AppUser,
    db: Session,
) -> FollowUpNote:
    # Verify task exists and belongs to the worker
    task = get_task(data.task_id, db)
    if current_user.role == UserRole.FOLLOW_UP and task.assigned_to != current_user.id:
        raise PermissionDenied(message="You can only add notes to tasks assigned to you.")

    note = FollowUpNote(
        task_id=data.task_id,
        contact_id=data.contact_id,
        member_id=data.member_id,
        note_type=data.note_type,
        content=data.content,
        recorded_by=current_user.id,
    )
    db.add(note)
    db.flush()
    return note


def list_task_notes(task_id: uuid.UUID, db: Session) -> list[FollowUpNote]:
    # Verify task exists
    get_task(task_id, db)
    return (
        db.query(FollowUpNote)
        .filter(FollowUpNote.task_id == task_id)
        .order_by(FollowUpNote.created_at.desc())
        .all()
    )
