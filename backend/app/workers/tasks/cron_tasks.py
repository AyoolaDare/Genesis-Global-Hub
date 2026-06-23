"""
Genesis Global CMS — Miscellaneous Cron Tasks

Additional scheduled jobs that do not fit neatly into payment or follow-up
categories:
  - Quarterly review notification
  - Duplicate member merge review digest
  - General system health digest
"""
import logging
from datetime import date, datetime, timezone

from app.workers.celery_app import celery_app
from app.database import get_db_context

logger = logging.getLogger(__name__)


@celery_app.task(name="send_quarterly_review_reminders", acks_late=True)
def send_quarterly_review_reminders() -> dict:
    """
    Quarterly job — notify supervisors that quarterly performance reviews are due
    for workers in their departments.

    Triggered by the beat schedule on the first day of each quarter
    (Jan, Apr, Jul, Oct at 8 AM Lagos time).

    Returns:
        Dict with keys: notifications_sent, departments_notified.
    """
    from app.models.hr import Worker
    from app.models.structure import Department
    from app.auth.models import AppUser, UserRole
    from app.workers.tasks.notification_tasks import send_admin_notification

    stats: dict = {"notifications_sent": 0, "departments_notified": 0}

    try:
        with get_db_context() as db:
            departments = (
                db.query(Department)
                .filter(Department.deleted_at.is_(None))
                .all()
            )

            for dept in departments:
                if not dept.head_user_id:
                    continue

                dept_head: AppUser = db.query(AppUser).filter(
                    AppUser.id == dept.head_user_id,
                    AppUser.is_active.is_(True),
                ).first()

                if not dept_head or not dept_head.email:
                    continue

                worker_count = (
                    db.query(Worker)
                    .filter(
                        Worker.department_id == dept.id,
                        Worker.deleted_at.is_(None),
                        Worker.status == "ACTIVE",
                    )
                    .count()
                )

                if worker_count == 0:
                    continue

                current_quarter = (date.today().month - 1) // 3 + 1
                send_admin_notification.delay(
                    admin_email=dept_head.email,
                    subject=f"Q{current_quarter} Performance Reviews Due — {dept.name}",
                    message=(
                        f"Dear {dept_head.email.split('@')[0]},\n\n"
                        f"Quarterly performance reviews are now due for the {dept.name} department.\n"
                        f"Active Workers: {worker_count}\n\n"
                        f"Please log in to Genesis Global CMS to complete the reviews.\n\n"
                        f"Reviews should be completed within 2 weeks.\n\n"
                        f"Thank you,\nGenesis Global HR System"
                    ),
                )
                stats["notifications_sent"] += 1
                stats["departments_notified"] += 1
                logger.info(
                    "send_quarterly_review_reminders: notified dept=%s head=%s workers=%s",
                    dept.name,
                    dept_head.email,
                    worker_count,
                )

    except Exception as exc:
        logger.error("send_quarterly_review_reminders error: %s", str(exc), exc_info=True)
        stats["error"] = str(exc)

    logger.info("send_quarterly_review_reminders stats: %s", stats)
    return stats


@celery_app.task(name="send_duplicate_member_digest", acks_late=True)
def send_duplicate_member_digest() -> dict:
    """
    Weekly job — send admins a digest of pending member duplicate reviews
    that need resolution.

    Returns:
        Dict with keys: pending_count, admin_notified.
    """
    from app.models.member import MemberDuplicate
    from app.workers.tasks.notification_tasks import send_admin_notification

    stats: dict = {"pending_count": 0, "admin_notified": False}

    try:
        with get_db_context() as db:
            pending_duplicates = (
                db.query(MemberDuplicate)
                .filter(MemberDuplicate.status == "PENDING")
                .count()
            )

            stats["pending_count"] = pending_duplicates

            if pending_duplicates > 0:
                send_admin_notification.delay(
                    admin_email=None,
                    subject=f"Action Required: {pending_duplicates} Pending Duplicate Member Reviews",
                    message=(
                        f"There are currently {pending_duplicates} pending duplicate member "
                        f"records in Genesis Global CMS that require admin review.\n\n"
                        f"Please log in and resolve these duplicates to keep member records clean.\n\n"
                        f"Genesis Global CMS — Weekly Digest"
                    ),
                )
                stats["admin_notified"] = True
                logger.info(
                    "send_duplicate_member_digest: %s pending duplicates — notified admins",
                    pending_duplicates,
                )
            else:
                logger.info("send_duplicate_member_digest: no pending duplicates")

    except Exception as exc:
        logger.error("send_duplicate_member_digest error: %s", str(exc), exc_info=True)
        stats["error"] = str(exc)

    return stats


@celery_app.task(name="send_annual_sponsor_reports_batch", acks_late=True)
def send_annual_sponsor_reports_batch(year: int) -> dict:
    """
    Annual job — generate and email giving reports to all active sponsors
    who have an email address on file.

    This task is manually triggered (or scheduled for Jan 1) each year.

    Args:
        year: The calendar year for which to generate reports.

    Returns:
        Dict with keys: reports_sent, sponsors_skipped.
    """
    from app.models.sponsor import Sponsor, SponsorPayment, PaymentStatusEnum
    from app.integrations.sendgrid import sendgrid_client
    from sqlalchemy import func as sa_func
    import asyncio

    stats: dict = {"reports_sent": 0, "sponsors_skipped": 0}
    loop = asyncio.new_event_loop()

    try:
        with get_db_context() as db:
            # Get all sponsors with email addresses
            sponsors = (
                db.query(Sponsor)
                .filter(
                    Sponsor.deleted_at.is_(None),
                    Sponsor.email.isnot(None),
                    Sponsor.email != "",
                )
                .all()
            )

            for sponsor in sponsors:
                try:
                    # Sum completed payments in the given year
                    totals = (
                        db.query(
                            sa_func.sum(SponsorPayment.amount).label("total"),
                            sa_func.count(SponsorPayment.id).label("count"),
                        )
                        .filter(
                            SponsorPayment.sponsor_id == sponsor.id,
                            SponsorPayment.status == PaymentStatusEnum.COMPLETED,
                            sa_func.extract("year", SponsorPayment.payment_date) == year,
                        )
                        .first()
                    )

                    total_given = float(totals.total or 0)
                    payment_count = int(totals.count or 0)

                    if payment_count == 0:
                        stats["sponsors_skipped"] += 1
                        continue

                    sent = loop.run_until_complete(
                        sendgrid_client.send_annual_sponsor_report(
                            to_email=sponsor.email,
                            sponsor_name=sponsor.full_name,
                            total_given=total_given,
                            payment_count=payment_count,
                            year=year,
                        )
                    )

                    if sent:
                        stats["reports_sent"] += 1
                    else:
                        stats["sponsors_skipped"] += 1

                except Exception as sponsor_exc:
                    logger.error(
                        "send_annual_sponsor_reports_batch: error for sponsor=%s: %s",
                        sponsor.id,
                        str(sponsor_exc),
                    )
                    stats["sponsors_skipped"] += 1

    except Exception as exc:
        logger.error(
            "send_annual_sponsor_reports_batch fatal error: %s", str(exc), exc_info=True
        )
        stats["error"] = str(exc)
    finally:
        loop.close()

    logger.info("send_annual_sponsor_reports_batch stats: %s", stats)
    return stats
