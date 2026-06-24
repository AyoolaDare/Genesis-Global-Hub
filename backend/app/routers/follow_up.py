"""
Genesis Global CMS — Follow-Up & Onboarding Router

Endpoints:
  POST   /follow-up/contacts             Register new convert
  GET    /follow-up/contacts             List contacts
  GET    /follow-up/contacts/{id}        Get contact detail

  POST   /follow-up/tasks                Create task
  GET    /follow-up/tasks                List tasks (mine or all for admin)
  GET    /follow-up/tasks/today          Today's tasks
  GET    /follow-up/tasks/overdue        Overdue tasks (supervisor)
  PUT    /follow-up/tasks/{id}           Update task
  POST   /follow-up/tasks/{id}/complete  Mark complete
  POST   /follow-up/tasks/{id}/escalate  Escalate to supervisor

  POST   /follow-up/notes                Add note
  GET    /follow-up/notes/{task_id}      Get notes for task
"""
import uuid
from typing import Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.auth.dependencies import require_role
from app.auth.models import AppUser
from app.core.responses import paginated_response, success_response
from app.database import get_db
from app.schemas.follow_up import (
    EscalateTaskRequest,
    FollowUpContactCreate,
    FollowUpNoteCreate,
    FollowUpTaskCreate,
    FollowUpTaskUpdate,
)
from app.services.follow_up_service import (
    complete_task,
    create_contact,
    create_note,
    create_task,
    escalate_task,
    get_contact,
    get_task,
    list_contacts,
    list_overdue_tasks,
    list_task_notes,
    list_tasks,
    list_tasks_today,
    update_task,
)

router = APIRouter(prefix="/follow-up", tags=["Follow-Up"])

_FOLLOW_UP_ROLES = ("SUPER_ADMIN", "PASTOR", "FOLLOW_UP")


# ── Contacts ───────────────────────────────────────────────────────────────────

@router.post("/contacts", summary="Register a new follow-up contact (convert)", status_code=201)
async def create_contact_endpoint(
    body: FollowUpContactCreate,
    current_user: AppUser = Depends(require_role(*_FOLLOW_UP_ROLES)),
    db: Session = Depends(get_db),
):
    contact = create_contact(body, current_user, db)
    return success_response(
        data={
            "id": contact.id,
            "full_name": contact.full_name,
            "phone": contact.phone,
            "address": contact.address,
            "registered_by": contact.registered_by,
            "created_at": contact.created_at,
        },
        message="Contact registered. Follow-up task created automatically.",
    )


@router.get("/contacts", summary="List follow-up contacts")
async def list_contacts_endpoint(
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    search: Optional[str] = Query(None),
    current_user: AppUser = Depends(require_role(*_FOLLOW_UP_ROLES)),
    db: Session = Depends(get_db),
):
    items, total = list_contacts(db, current_user, page, per_page, search)
    data = [
        {
            "id": c.id,
            "full_name": c.full_name,
            "phone": c.phone,
            "address": c.address,
            "how_heard": c.how_heard,
            "registered_by": c.registered_by,
            "member_id": c.member_id,
            "created_at": c.created_at,
        }
        for c in items
    ]
    return paginated_response(data=data, total=total, page=page, per_page=per_page)


@router.get("/contacts/{contact_id}", summary="Get contact detail")
async def get_contact_endpoint(
    contact_id: uuid.UUID,
    current_user: AppUser = Depends(require_role(*_FOLLOW_UP_ROLES)),
    db: Session = Depends(get_db),
):
    contact = get_contact(contact_id, db)
    return success_response(data={
        "id": contact.id,
        "full_name": contact.full_name,
        "phone": contact.phone,
        "address": contact.address,
        "prayer_requests": contact.prayer_requests,
        "how_heard": contact.how_heard,
        "registered_by": contact.registered_by,
        "member_id": contact.member_id,
        "created_at": contact.created_at,
        "updated_at": contact.updated_at,
    })


# ── Tasks ──────────────────────────────────────────────────────────────────────

@router.post("/tasks", summary="Create a follow-up task", status_code=201)
async def create_task_endpoint(
    body: FollowUpTaskCreate,
    current_user: AppUser = Depends(require_role(*_FOLLOW_UP_ROLES)),
    db: Session = Depends(get_db),
):
    task = create_task(body, current_user, db)
    return success_response(
        data={
            "id": task.id,
            "contact_id": task.contact_id,
            "assigned_to": task.assigned_to,
            "stage": task.stage,
            "due_date": task.due_date,
            "created_at": task.created_at,
        },
        message="Task created.",
    )


@router.get("/tasks", summary="List tasks (mine or all for admin)")
async def list_tasks_endpoint(
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    search: Optional[str] = Query(None),
    current_user: AppUser = Depends(require_role(*_FOLLOW_UP_ROLES)),
    db: Session = Depends(get_db),
):
    items, total = list_tasks(db, current_user, page, per_page, search)
    return paginated_response(data=items, total=total, page=page, per_page=per_page)


@router.get("/tasks/today", summary="Today's tasks for the current follow-up worker")
async def list_tasks_today_endpoint(
    current_user: AppUser = Depends(require_role(*_FOLLOW_UP_ROLES)),
    db: Session = Depends(get_db),
):
    tasks = list_tasks_today(db, current_user)
    return success_response(data=tasks)


@router.get("/tasks/overdue", summary="Overdue tasks (supervisor/admin view)")
async def list_overdue_tasks_endpoint(
    current_user: AppUser = Depends(require_role("SUPER_ADMIN", "PASTOR")),
    db: Session = Depends(get_db),
):
    tasks = list_overdue_tasks(db)
    return success_response(data=tasks)


@router.put("/tasks/{task_id}", summary="Update task stage or notes")
async def update_task_endpoint(
    task_id: uuid.UUID,
    body: FollowUpTaskUpdate,
    current_user: AppUser = Depends(require_role(*_FOLLOW_UP_ROLES)),
    db: Session = Depends(get_db),
):
    task = get_task(task_id, db)
    task = update_task(task, body, current_user, db)
    return success_response(
        data={
            "id": task.id,
            "stage": task.stage,
            "assigned_to": task.assigned_to,
            "due_date": task.due_date,
            "notes": task.notes,
            "updated_at": task.updated_at,
        },
        message="Task updated.",
    )


@router.post("/tasks/{task_id}/complete", summary="Mark task as complete")
async def complete_task_endpoint(
    task_id: uuid.UUID,
    current_user: AppUser = Depends(require_role(*_FOLLOW_UP_ROLES)),
    db: Session = Depends(get_db),
):
    task = get_task(task_id, db)
    task = complete_task(task, current_user, db)
    return success_response(
        data={"id": task.id, "completed_at": task.completed_at},
        message="Task marked complete.",
    )


@router.post("/tasks/{task_id}/escalate", summary="Escalate task to supervisor")
async def escalate_task_endpoint(
    task_id: uuid.UUID,
    body: EscalateTaskRequest,
    current_user: AppUser = Depends(require_role(*_FOLLOW_UP_ROLES)),
    db: Session = Depends(get_db),
):
    task = get_task(task_id, db)
    task = escalate_task(task, body, current_user, db)
    return success_response(
        data={"id": task.id, "escalated_at": task.escalated_at, "escalated_to": task.escalated_to},
        message="Task escalated.",
    )


# ── Notes ──────────────────────────────────────────────────────────────────────

@router.post("/notes", summary="Add a note to a task", status_code=201)
async def create_note_endpoint(
    body: FollowUpNoteCreate,
    current_user: AppUser = Depends(require_role(*_FOLLOW_UP_ROLES)),
    db: Session = Depends(get_db),
):
    note = create_note(body, current_user, db)
    return success_response(
        data={
            "id": note.id,
            "task_id": note.task_id,
            "note_type": note.note_type,
            "content": note.content,
            "recorded_by": note.recorded_by,
            "created_at": note.created_at,
        },
        message="Note recorded.",
    )


@router.get("/notes/{task_id}", summary="Get notes for a task")
async def list_notes_endpoint(
    task_id: uuid.UUID,
    current_user: AppUser = Depends(require_role(*_FOLLOW_UP_ROLES)),
    db: Session = Depends(get_db),
):
    notes = list_task_notes(task_id, db)
    data = [
        {
            "id": n.id,
            "task_id": n.task_id,
            "contact_id": n.contact_id,
            "note_type": n.note_type,
            "content": n.content,
            "recorded_by": n.recorded_by,
            "created_at": n.created_at,
        }
        for n in notes
    ]
    return success_response(data=data)
