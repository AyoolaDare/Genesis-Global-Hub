"""
Genesis Global CMS — Payment Celery Tasks

Handles:
  - Processing Flutterwave webhook payloads asynchronously
  - Daily overdue payment detection and reminders
  - Escalation alerts for sponsors overdue > 7 days
"""
import asyncio
import logging
from datetime import date, datetime, timedelta, timezone

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


@celery_app.task(
    name="process_webhook_payment",
    bind=True,
    max_retries=3,
    default_retry_delay=30,
    acks_late=True,
)
def process_webhook_payment(self, payload: dict) -> dict:
    """
    Process a Flutterwave webhook payload asynchronously.

    This task is queued immediately by the /webhooks/flutterwave endpoint
    so the HTTP response returns 200 without waiting for DB operations.

    Args:
        payload: Parsed JSON payload from the Flutterwave webhook.

    Returns:
        Dict with keys: success, event, tx_ref.
    """
    from app.integrations.webhook_handlers import handle_flutterwave_payment

    result = {
        "success": False,
        "event": payload.get("event", ""),
        "tx_ref": payload.get("data", {}).get("tx_ref", ""),
    }
    try:
        with get_db_context() as db:
            _run_async(handle_flutterwave_payment(payload=payload, db=db))
        result["success"] = True
        logger.info(
            "process_webhook_payment: completed for event=%s tx_ref=%s",
            result["event"],
            result["tx_ref"],
        )
        return result

    except Exception as exc:
        logger.error(
            "process_webhook_payment error: event=%s tx_ref=%s error=%s",
            result["event"],
            result["tx_ref"],
            str(exc),
            exc_info=True,
        )
        try:
            raise self.retry(exc=exc, countdown=30 * (2 ** self.request.retries))
        except self.MaxRetriesExceededError:
            logger.critical(
                "process_webhook_payment max retries exceeded: tx_ref=%s", result["tx_ref"]
            )
            result["error"] = str(exc)
            return result


@celery_app.task(name="check_overdue_payments", acks_late=True)
def check_overdue_payments() -> dict:
    """
    Daily cron job to check for overdue sponsor payments.

    Logic:
      - 3 days BEFORE due: send reminder (if not sent in last 30 days)
      - 1-6 days AFTER due: send overdue reminder
      - 7+ days AFTER due: send escalation alert to finance coordinator + overdue SMS

    Returns:
        Dict with keys: reminders_sent, overdue_alerts_sent, escalations_sent.
    """
    from app.models.sponsor import Sponsor, SponsorshipTierEnum
    from app.integrations.termii import termii
    from app.workers.tasks.notification_tasks import send_payment_reminder

    stats = {"reminders_sent": 0, "overdue_alerts_sent": 0, "escalations_sent": 0}
    today = date.today()
    thirty_days_ago = today - timedelta(days=30)

    try:
        with get_db_context() as db:
            # Fetch all active sponsors with a next_due_date set
            active_sponsors = (
                db.query(Sponsor)
                .filter(
                    Sponsor.is_active.is_(True),
                    Sponsor.deleted_at.is_(None),
                    Sponsor.sponsorship_tier != SponsorshipTierEnum.ONE_TIME,
                    Sponsor.next_due_date.isnot(None),
                )
                .all()
            )

            for sponsor in active_sponsors:
                due_date = sponsor.next_due_date
                days_until_due = (due_date - today).days   # negative = overdue
                days_overdue = -days_until_due              # positive = overdue

                # Check if we sent a reminder recently (within 30 days)
                recently_reminded = (
                    sponsor.reminder_sent_at is not None
                    and sponsor.reminder_sent_at.date() > thirty_days_ago
                )

                # 1. 3 days before due — send upcoming reminder
                if 0 <= days_until_due <= 3 and not recently_reminded:
                    send_payment_reminder.delay(str(sponsor.id))
                    stats["reminders_sent"] += 1
                    logger.info(
                        "check_overdue_payments: queued reminder for sponsor=%s due=%s",
                        sponsor.id,
                        due_date,
                    )

                # 2. 1-6 days overdue — send gentle overdue SMS
                elif 1 <= days_overdue <= 6 and not recently_reminded:
                    if sponsor.phone:
                        try:
                            _run_async(
                                termii.send_templated_message(
                                    to=sponsor.phone,
                                    template_key="payment_overdue",
                                    template_vars={
                                        "name": sponsor.full_name.split()[0],
                                        "amount": f"{sponsor.amount_per_period:,.0f}",
                                        "date": due_date.strftime("%d %b %Y"),
                                    },
                                    channel="generic",
                                )
                            )
                            sponsor.reminder_sent_at = datetime.now(timezone.utc)
                            db.flush()
                            stats["overdue_alerts_sent"] += 1
                        except Exception as sms_exc:
                            logger.error(
                                "check_overdue_payments SMS error: sponsor=%s error=%s",
                                sponsor.id,
                                str(sms_exc),
                            )

                # 3. 7+ days overdue — escalate to coordinator + send SMS
                elif days_overdue >= 7 and not recently_reminded:
                    if sponsor.phone:
                        try:
                            _run_async(
                                termii.send_templated_message(
                                    to=sponsor.phone,
                                    template_key="payment_overdue",
                                    template_vars={
                                        "name": sponsor.full_name.split()[0],
                                        "amount": f"{sponsor.amount_per_period:,.0f}",
                                        "date": due_date.strftime("%d %b %Y"),
                                    },
                                    channel="generic",
                                )
                            )
                            sponsor.reminder_sent_at = datetime.now(timezone.utc)
                            db.flush()
                        except Exception as sms_exc:
                            logger.error(
                                "check_overdue_payments escalation SMS error: sponsor=%s error=%s",
                                sponsor.id,
                                str(sms_exc),
                            )

                    # Notify finance admin via email
                    from app.workers.tasks.notification_tasks import send_admin_notification
                    send_admin_notification.delay(
                        admin_email=None,
                        subject=f"Overdue Sponsorship Alert — {sponsor.full_name}",
                        message=(
                            f"Sponsor: {sponsor.full_name}\n"
                            f"Phone: {sponsor.phone or 'N/A'}\n"
                            f"Email: {sponsor.email or 'N/A'}\n"
                            f"Amount: ₦{sponsor.amount_per_period:,.2f}\n"
                            f"Tier: {sponsor.sponsorship_tier.value}\n"
                            f"Due Date: {due_date}\n"
                            f"Days Overdue: {days_overdue}\n\n"
                            f"Please follow up with this sponsor."
                        ),
                    )
                    stats["escalations_sent"] += 1
                    logger.info(
                        "check_overdue_payments: escalated sponsor=%s days_overdue=%s",
                        sponsor.id,
                        days_overdue,
                    )

    except Exception as exc:
        logger.error("check_overdue_payments fatal error: %s", str(exc), exc_info=True)
        stats["error"] = str(exc)

    logger.info("check_overdue_payments stats: %s", stats)
    return stats


@celery_app.task(name="send_overdue_payment_alerts", acks_late=True)
def send_overdue_payment_alerts() -> dict:
    """
    Query sponsors who are more than 7 days overdue and send
    a follow-up SMS and notify the sponsorship coordinator.

    This is a supplementary task to check_overdue_payments, focused
    specifically on the 7+ day cohort for more urgent action.

    Returns:
        Dict with keys: alerts_sent, coordinator_notified.
    """
    from app.models.sponsor import Sponsor, SponsorshipTierEnum
    from app.integrations.termii import termii

    stats = {"alerts_sent": 0, "coordinator_notified": False}
    today = date.today()
    cutoff = today - timedelta(days=7)

    try:
        with get_db_context() as db:
            overdue_sponsors = (
                db.query(Sponsor)
                .filter(
                    Sponsor.is_active.is_(True),
                    Sponsor.deleted_at.is_(None),
                    Sponsor.sponsorship_tier != SponsorshipTierEnum.ONE_TIME,
                    Sponsor.next_due_date < cutoff,
                    Sponsor.next_due_date.isnot(None),
                )
                .all()
            )

            summary_lines = []
            for sponsor in overdue_sponsors:
                days_overdue = (today - sponsor.next_due_date).days

                if sponsor.phone:
                    try:
                        _run_async(
                            termii.send_templated_message(
                                to=sponsor.phone,
                                template_key="payment_overdue",
                                template_vars={
                                    "name": sponsor.full_name.split()[0],
                                    "amount": f"{sponsor.amount_per_period:,.0f}",
                                    "date": sponsor.next_due_date.strftime("%d %b %Y"),
                                },
                                channel="generic",
                            )
                        )
                        stats["alerts_sent"] += 1
                    except Exception as sms_exc:
                        logger.error(
                            "send_overdue_payment_alerts SMS error: sponsor=%s error=%s",
                            sponsor.id,
                            str(sms_exc),
                        )

                summary_lines.append(
                    f"- {sponsor.full_name}: ₦{sponsor.amount_per_period:,.0f} "
                    f"({days_overdue} days overdue)"
                )

            if summary_lines:
                from app.workers.tasks.notification_tasks import send_admin_notification
                send_admin_notification.delay(
                    admin_email=None,
                    subject=f"Weekly Overdue Sponsorship Report — {len(summary_lines)} Sponsors",
                    message=(
                        "The following sponsors are 7+ days overdue:\n\n"
                        + "\n".join(summary_lines)
                        + "\n\nPlease follow up urgently."
                    ),
                )
                stats["coordinator_notified"] = True

    except Exception as exc:
        logger.error("send_overdue_payment_alerts error: %s", str(exc), exc_info=True)
        stats["error"] = str(exc)

    logger.info("send_overdue_payment_alerts stats: %s", stats)
    return stats
