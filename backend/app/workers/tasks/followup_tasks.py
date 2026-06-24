"""
Genesis Global CMS — Follow-Up Celery Tasks

Handles:
  - Escalating overdue follow-up tasks to supervisors
  - Daily reminders to follow-up workers
  - Flagging inactive members as "At Risk"
"""
import asyncio
import logging
import uuid
from datetime import date, datetime, timedelta, timezone
from typing import Optional

from app.workers.celery_app import celery_app
from app.database import get_db_context

logger = logging.getLogger(__name__)


def _run_async(coro):
    """Run an async coroutine from a sync Celery task."""
    loop = asyncio.new_event_loop()
    try:
        return loop.run_until_complete(coro)
    finally:
        loop.close()


@celery_app.task(name="escalate_overdue_followups", acks_late=True)
def escalate_overdue_followups() -> dict:
    """
    Escalate follow-up tasks that are overdue by more than 72 hours.

    Criteria:
      - stage = FIRST_CONTACT
      - created_at < NOW() - 72 hours
      - completed_at IS NULL
      - escalated_at IS NULL

    Steps for each qualifying task:
      1. Set escalated_at = NOW()
      2. Find the department head or a SUPER_ADMIN / PASTOR as supervisor
      3. Update escalated_to on the task
      4. Send escalation SMS to the assigned worker (if they have a phone)
      5. Send escalation email to the supervisor
      6. Insert a notification_queue record for in-app notification

    Returns:
        Dict with keys: escalated, errors.
    """
    from app.models.follow_up import FollowUpTask, FollowUpStageEnum, FollowUpContact
    from app.auth.models import AppUser, UserRole
    from app.models.notification import NotificationQueue
    from app.integrations.termii import termii
    from app.integrations.sendgrid import sendgrid_client

    stats = {"escalated": 0, "errors": 0}
    cutoff = datetime.now(timezone.utc) - timedelta(hours=72)

    try:
        with get_db_context() as db:
            overdue_tasks = (
                db.query(FollowUpTask)
                .filter(
                    FollowUpTask.stage == FollowUpStageEnum.FIRST_CONTACT,
                    FollowUpTask.created_at <= cutoff,
                    FollowUpTask.completed_at.is_(None),
                    FollowUpTask.escalated_at.is_(None),
                    FollowUpTask.deleted_at.is_(None),
                )
                .all()
            )

            for task in overdue_tasks:
                try:
                    # Load the assigned worker's user record
                    assigned_user: Optional[AppUser] = (
                        db.query(AppUser)
                        .filter(AppUser.id == task.assigned_to)
                        .first()
                    )

                    # Find supervisor: prefer DEPARTMENT_HEAD, then PASTOR, then SUPER_ADMIN
                    supervisor: Optional[AppUser] = (
                        db.query(AppUser)
                        .filter(
                            AppUser.role.in_([
                                UserRole.DEPARTMENT_HEAD,
                                UserRole.PASTOR,
                                UserRole.SUPER_ADMIN,
                            ]),
                            AppUser.is_active.is_(True),
                        )
                        .order_by(AppUser.role)  # DEPARTMENT_HEAD sorts before PASTOR
                        .first()
                    )

                    # Load contact for context
                    contact: Optional[FollowUpContact] = (
                        db.query(FollowUpContact)
                        .filter(FollowUpContact.id == task.contact_id)
                        .first()
                    )
                    contact_name = contact.full_name if contact else "Unknown Contact"

                    # Mark task as escalated
                    task.escalated_at = datetime.now(timezone.utc)
                    if supervisor:
                        task.escalated_to = supervisor.id

                    # Send escalation SMS to assigned worker
                    if assigned_user and assigned_user.email:
                        hours_overdue = int(
                            (datetime.now(timezone.utc) - task.created_at).total_seconds() / 3600
                        )

                        # Try to get worker's phone via member link if available
                        worker_phone: Optional[str] = None
                        if assigned_user.member_id:
                            from app.models.member import MemberModel
                            member = db.query(MemberModel).filter(
                                MemberModel.id == assigned_user.member_id
                            ).first()
                            if member:
                                worker_phone = member.phone

                        if worker_phone:
                            try:
                                _run_async(
                                    termii.send_templated_message(
                                        to=worker_phone,
                                        template_key="follow_up_reminder",
                                        template_vars={
                                            "name": assigned_user.email.split("@")[0],
                                            "count": 1,
                                        },
                                        channel="generic",
                                    )
                                )
                            except Exception as sms_exc:
                                logger.error(
                                    "escalate_overdue_followups SMS error: task=%s error=%s",
                                    task.id,
                                    str(sms_exc),
                                )

                        # Send escalation email to supervisor
                        if supervisor and supervisor.email:
                            worker_name = (
                                assigned_user.email.split("@")[0]
                                if assigned_user
                                else "Unknown Worker"
                            )
                            _run_async(
                                sendgrid_client.send_follow_up_escalation(
                                    supervisor_email=supervisor.email,
                                    worker_name=worker_name,
                                    contact_name=contact_name,
                                    hours_overdue=hours_overdue,
                                )
                            )

                    # Insert in-app notification_queue record
                    notification = NotificationQueue(
                        recipient_type="USER",
                        recipient_id=task.assigned_to if task.assigned_to else uuid.uuid4(),
                        channel="IN_APP",
                        template_key="follow_up_escalation",
                        payload={
                            "task_id": str(task.id),
                            "contact_name": contact_name,
                            "escalated_to": str(supervisor.id) if supervisor else None,
                        },
                        status="PENDING",
                    )
                    db.add(notification)

                    db.flush()
                    stats["escalated"] += 1
                    logger.info(
                        "escalate_overdue_followups: escalated task=%s contact=%s",
                        task.id,
                        contact_name,
                    )

                except Exception as task_exc:
                    logger.error(
                        "escalate_overdue_followups: error processing task=%s: %s",
                        task.id,
                        str(task_exc),
                        exc_info=True,
                    )
                    stats["errors"] += 1

    except Exception as exc:
        logger.error("escalate_overdue_followups fatal error: %s", str(exc), exc_info=True)
        stats["error"] = str(exc)

    logger.info("escalate_overdue_followups stats: %s", stats)
    return stats


@celery_app.task(name="send_daily_followup_reminders", acks_late=True)
def send_daily_followup_reminders() -> dict:
    """
    Daily 8:00 AM job — send SMS reminders to each active follow-up worker
    about the number of pending/overdue tasks due today or earlier.

    Steps:
      1. Get all distinct assigned_to user IDs from active (non-completed) tasks
      2. For each worker, count tasks where due_date <= today and completed_at IS NULL
      3. If count > 0, send "You have {count} pending follow-ups" SMS

    Returns:
        Dict with keys: workers_notified, total_tasks.
    """
    from app.models.follow_up import FollowUpTask
    from app.auth.models import AppUser
    from app.models.member import MemberModel
    from app.integrations.termii import termii

    stats = {"workers_notified": 0, "total_tasks": 0}
    today = date.today()

    try:
        with get_db_context() as db:
            # Get all workers with pending tasks due today or overdue
            pending_tasks = (
                db.query(FollowUpTask)
                .filter(
                    FollowUpTask.completed_at.is_(None),
                    FollowUpTask.deleted_at.is_(None),
                    FollowUpTask.due_date <= datetime.combine(
                        today, datetime.min.time()
                    ).replace(tzinfo=timezone.utc),
                )
                .all()
            )

            # Group by assigned worker
            worker_task_counts: dict = {}
            for task in pending_tasks:
                worker_id = str(task.assigned_to)
                worker_task_counts[worker_id] = worker_task_counts.get(worker_id, 0) + 1
                stats["total_tasks"] += 1

            for worker_id_str, count in worker_task_counts.items():
                try:
                    worker_uuid = uuid.UUID(worker_id_str)
                    user: Optional[AppUser] = db.query(AppUser).filter(
                        AppUser.id == worker_uuid,
                        AppUser.is_active.is_(True),
                    ).first()

                    if not user:
                        continue

                    # Find worker's phone via their member link
                    worker_phone: Optional[str] = None
                    if user.member_id:
                        member = db.query(MemberModel).filter(
                            MemberModel.id == user.member_id,
                            MemberModel.deleted_at.is_(None),
                        ).first()
                        if member:
                            worker_phone = member.phone

                    if not worker_phone:
                        logger.info(
                            "send_daily_followup_reminders: no phone for user=%s", worker_id_str
                        )
                        continue

                    _run_async(
                        termii.send_templated_message(
                            to=worker_phone,
                            template_key="follow_up_reminder",
                            template_vars={
                                "name": user.email.split("@")[0],
                                "count": count,
                            },
                            channel="generic",
                        )
                    )
                    stats["workers_notified"] += 1
                    logger.info(
                        "send_daily_followup_reminders: notified worker=%s count=%s",
                        worker_id_str,
                        count,
                    )

                except Exception as worker_exc:
                    logger.error(
                        "send_daily_followup_reminders: error for worker=%s: %s",
                        worker_id_str,
                        str(worker_exc),
                    )

    except Exception as exc:
        logger.error("send_daily_followup_reminders fatal error: %s", str(exc), exc_info=True)
        stats["error"] = str(exc)

    logger.info("send_daily_followup_reminders stats: %s", stats)
    return stats


@celery_app.task(name="flag_inactive_members", acks_late=True)
def flag_inactive_members() -> dict:
    """
    Weekly job — find members not in any attendance_record in the last 30 days,
    add them to the notification_queue for follow-up, and add a NotificationQueue
    record alerting the follow-up team.

    Note: This does not mutate MemberModel.membership_status to avoid conflicting
    with the approval workflow. Instead it inserts a NotificationQueue record
    for the follow-up team to action.

    Returns:
        Dict with keys: flagged, already_followed_up.
    """
    from app.models.member import MemberModel, MemberStatusEnum
    from app.models.attendance import AttendanceRecord, Meeting
    from app.models.follow_up import FollowUpContact, FollowUpTask, FollowUpStageEnum
    from app.auth.models import AppUser, UserRole

    stats = {"flagged": 0, "already_in_followup": 0, "errors": 0}
    thirty_days_ago = datetime.now(timezone.utc) - timedelta(days=30)

    try:
        with get_db_context() as db:
            # Get all active members
            active_members = (
                db.query(MemberModel)
                .filter(
                    MemberModel.membership_status == MemberStatusEnum.ACTIVE,
                    MemberModel.deleted_at.is_(None),
                )
                .all()
            )

            # Get member IDs present in attendance records in the last 30 days
            recent_attendee_ids = set(
                row[0]
                for row in db.query(AttendanceRecord.member_id)
                .join(Meeting, Meeting.id == AttendanceRecord.meeting_id)
                .filter(Meeting.meeting_date >= thirty_days_ago.date())
                .distinct()
                .all()
            )

            # Find follow-up team lead to assign tasks to
            followup_lead: Optional[AppUser] = (
                db.query(AppUser)
                .filter(
                    AppUser.role == UserRole.FOLLOW_UP,
                    AppUser.is_active.is_(True),
                )
                .first()
            )

            for member in active_members:
                if member.id in recent_attendee_ids:
                    continue  # Member has recent attendance — skip

                try:
                    # Check if this member is already in follow_up_contacts
                    existing_contact = (
                        db.query(FollowUpContact)
                        .filter(
                            FollowUpContact.member_id == member.id,
                            FollowUpContact.deleted_at.is_(None),
                        )
                        .first()
                    )

                    if existing_contact:
                        stats["already_in_followup"] += 1
                        # Still insert a notification so the team knows it's urgent
                        _add_at_risk_notification(db, member, existing_contact)
                        continue

                    # Create a new FollowUpContact record
                    contact = FollowUpContact(
                        member_id=member.id,
                        full_name=member.full_name,
                        phone=member.phone,
                        prayer_requests=None,
                        how_heard="Inactive Member (30 days)",
                    )
                    db.add(contact)
                    db.flush()  # Get contact.id

                    # Assign a follow-up task
                    if followup_lead:
                        task = FollowUpTask(
                            contact_id=contact.id,
                            member_id=member.id,
                            assigned_to=followup_lead.id,
                            stage=FollowUpStageEnum.FIRST_CONTACT,
                            notes=f"Auto-flagged: not attended in 30 days. Member: {member.full_name}",
                        )
                        db.add(task)

                    _add_at_risk_notification(db, member, contact)
                    db.flush()

                    stats["flagged"] += 1
                    logger.info(
                        "flag_inactive_members: flagged member=%s name=%s",
                        member.id,
                        member.full_name,
                    )

                except Exception as member_exc:
                    logger.error(
                        "flag_inactive_members: error for member=%s: %s",
                        member.id,
                        str(member_exc),
                        exc_info=True,
                    )
                    stats["errors"] += 1

    except Exception as exc:
        logger.error("flag_inactive_members fatal error: %s", str(exc), exc_info=True)
        stats["error"] = str(exc)

    logger.info("flag_inactive_members stats: %s", stats)
    return stats


# ── Internal Helpers ───────────────────────────────────────────────────────────

def _add_at_risk_notification(db, member, contact) -> None:
    """Insert a NotificationQueue record marking a member as At Risk."""
    from app.models.notification import NotificationQueue
    try:
        notification = NotificationQueue(
            recipient_type="TEAM",
            recipient_id=contact.id,
            channel="IN_APP",
            template_key="inactive_member_alert",
            payload={
                "member_id": str(member.id),
                "member_name": member.full_name,
                "contact_id": str(contact.id),
                "reason": "No attendance in last 30 days",
            },
            status="PENDING",
        )
        db.add(notification)
    except Exception as exc:
        logger.error(
            "_add_at_risk_notification error: member=%s error=%s", member.id, str(exc)
        )
