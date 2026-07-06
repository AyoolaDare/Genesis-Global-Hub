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


def generate_sponsor_payment_link(db, sponsor) -> "str | None":
    """
    Create a fresh Flutterwave checkout link for a sponsor's standard amount.

    Reuses the same initiation path as the admin UI (creates a PENDING
    SponsorPayment row tied to a unique tx_ref) but suppresses the
    payment-link notification task — callers embed the link in their own
    reminder message instead.

    Returns the hosted checkout URL, or None if Flutterwave is unavailable
    (callers should still send their message, just without a link).
    """
    from app.services.sponsor_service import initiate_flutterwave_payment

    try:
        result = _run_async(
            initiate_flutterwave_payment(
                sponsor_id=sponsor.id,
                amount=float(sponsor.amount),
                redirect_url=None,
                db=db,
                notify_sponsor=False,
            )
        )
        return result.get("payment_link")
    except Exception as exc:
        logger.warning(
            "generate_sponsor_payment_link: could not create link for sponsor=%s: %s",
            sponsor.id,
            str(exc),
        )
        return None


def _sponsors_with_latest_due(db) -> list:
    """
    Return (sponsor, latest_completed_payment) pairs for active recurring
    sponsors. Due-date tracking lives on sponsor_payments.next_due_date —
    the sponsors table has no such column.
    """
    from app.models.sponsor import (
        PaymentStatusEnum,
        Sponsor,
        SponsorPayment,
        SponsorshipTierEnum,
    )

    rows = (
        db.query(Sponsor, SponsorPayment)
        .join(SponsorPayment, SponsorPayment.sponsor_id == Sponsor.id)
        .filter(
            Sponsor.is_active.is_(True),
            Sponsor.deleted_at.is_(None),
            Sponsor.sponsorship_tier != SponsorshipTierEnum.ONE_TIME,
            SponsorPayment.deleted_at.is_(None),
            SponsorPayment.status == PaymentStatusEnum.COMPLETED,
            SponsorPayment.next_due_date.isnot(None),
        )
        .order_by(Sponsor.id, SponsorPayment.payment_date.desc().nulls_last())
        .all()
    )

    latest: dict = {}
    for sponsor, payment in rows:
        latest.setdefault(sponsor.id, (sponsor, payment))
    return list(latest.values())


def _send_overdue_sms_with_link(db, sponsor, due_date, template_key: str = "payment_overdue") -> None:
    """
    Render the given overdue template, append a fresh Flutterwave payment
    link (when available), and SMS it to the sponsor. Raises on send failure
    so callers can log per-sponsor errors.
    """
    from app.integrations.termii import termii, TEMPLATES

    link = generate_sponsor_payment_link(db, sponsor)
    message = TEMPLATES[template_key].format(
        name=sponsor.full_name.split()[0],
        amount=f"{float(sponsor.amount):,.0f}",
        date=due_date.strftime("%d %b %Y"),
    )
    if link:
        message += f" Pay securely here: {link}"
    _run_async(termii.send_sms(to=sponsor.phone, message=message, channel="generic"))


@celery_app.task(name="check_overdue_payments", acks_late=True)
def check_overdue_payments() -> dict:
    """
    Daily reminder funnel for recurring sponsor payments.

    Three configurable stages per payment cycle, keyed off the latest
    COMPLETED payment's next_due_date and tracked via reminder_stage on that
    row (each stage fires exactly once per cycle; a new payment starts a new
    cycle with stage 0):

      Stage 1 — weekly reminder:  within stage1_days_before_due days of the
                due date (or just past it), a friendly reminder with a fresh
                payment link (SMS/WhatsApp + email).
      Stage 2 — week-3 nudge:     once stage2_days_overdue days overdue, a
                firmer overdue SMS with a payment link.
      Stage 3 — final notice:     once stage3_days_overdue days overdue, a
                final-notice SMS with a payment link, plus an escalation
                email to the finance admins.

    The schedule lives in app_settings ("finance.funnel") and is editable
    from the Donor Funnel screen; this task re-reads it on every run.

    Returns:
        Dict with keys: stage1_sent, stage2_sent, stage3_sent, escalations_sent
        (plus legacy aliases reminders_sent / overdue_alerts_sent).
    """
    from app.services.funnel_service import get_funnel_config
    from app.workers.tasks.notification_tasks import send_payment_reminder

    stats = {
        "stage1_sent": 0,
        "stage2_sent": 0,
        "stage3_sent": 0,
        "escalations_sent": 0,
    }
    today = date.today()

    try:
        with get_db_context() as db:
            config = get_funnel_config(db)
            if not config.get("enabled", True):
                stats["skipped"] = "funnel disabled in config"
                logger.info("check_overdue_payments: funnel disabled — skipping run")
                return stats

            s1_before = int(config["stage1_days_before_due"])
            s2_overdue = int(config["stage2_days_overdue"])
            s3_overdue = int(config["stage3_days_overdue"])

            for sponsor, payment in _sponsors_with_latest_due(db):
                due_date = payment.next_due_date
                days_until_due = (due_date - today).days   # negative = overdue
                days_overdue = -days_until_due              # positive = overdue
                stage = int(payment.reminder_stage or 0)

                # Stage 3 — final notice + admin escalation
                if days_overdue >= s3_overdue and stage < 3:
                    if sponsor.phone:
                        try:
                            _send_overdue_sms_with_link(
                                db, sponsor, due_date, template_key="payment_final_notice"
                            )
                        except Exception as sms_exc:
                            logger.error(
                                "funnel stage3 SMS error: sponsor=%s error=%s",
                                sponsor.id,
                                str(sms_exc),
                            )
                    payment.reminder_stage = 3
                    payment.reminder_sent_at = datetime.now(timezone.utc)
                    db.flush()
                    stats["stage3_sent"] += 1

                    from app.workers.tasks.notification_tasks import send_admin_notification
                    send_admin_notification.delay(
                        admin_email=None,
                        subject=f"FINAL NOTICE sent — {sponsor.full_name} still unpaid",
                        message=(
                            f"Sponsor: {sponsor.full_name}\n"
                            f"Phone: {sponsor.phone or 'N/A'}\n"
                            f"Email: {sponsor.email or 'N/A'}\n"
                            f"Amount: ₦{float(sponsor.amount):,.2f}\n"
                            f"Tier: {sponsor.sponsorship_tier.value}\n"
                            f"Due Date: {due_date}\n"
                            f"Days Overdue: {days_overdue}\n\n"
                            f"The final funnel reminder has been sent. "
                            f"Please follow up personally with this sponsor."
                        ),
                    )
                    stats["escalations_sent"] += 1
                    logger.info(
                        "funnel: stage3 final notice sponsor=%s days_overdue=%s",
                        sponsor.id,
                        days_overdue,
                    )

                # Stage 2 — week-3 nudge
                elif days_overdue >= s2_overdue and stage < 2:
                    if sponsor.phone:
                        try:
                            _send_overdue_sms_with_link(db, sponsor, due_date)
                        except Exception as sms_exc:
                            logger.error(
                                "funnel stage2 SMS error: sponsor=%s error=%s",
                                sponsor.id,
                                str(sms_exc),
                            )
                    payment.reminder_stage = 2
                    payment.reminder_sent_at = datetime.now(timezone.utc)
                    db.flush()
                    stats["stage2_sent"] += 1
                    logger.info(
                        "funnel: stage2 nudge sponsor=%s days_overdue=%s",
                        sponsor.id,
                        days_overdue,
                    )

                # Stage 1 — weekly reminder (just before due, or freshly overdue)
                elif days_until_due <= s1_before and days_overdue < s2_overdue and stage < 1:
                    send_payment_reminder.delay(str(sponsor.id))
                    payment.reminder_stage = 1
                    db.flush()
                    stats["stage1_sent"] += 1
                    logger.info(
                        "funnel: stage1 reminder queued sponsor=%s due=%s",
                        sponsor.id,
                        due_date,
                    )

    except Exception as exc:
        logger.error("check_overdue_payments fatal error: %s", str(exc), exc_info=True)
        stats["error"] = str(exc)

    # Legacy aliases so existing dashboards/log parsers keep working
    stats["reminders_sent"] = stats["stage1_sent"]
    stats["overdue_alerts_sent"] = stats["stage2_sent"] + stats["stage3_sent"]
    logger.info("check_overdue_payments (funnel) stats: %s", stats)
    return stats


@celery_app.task(name="reconcile_pending_payments", acks_late=True)
def reconcile_pending_payments() -> dict:
    """
    Hourly safety net for missed webhooks.

    Finds Flutterwave payments still PENDING 15+ minutes after initiation
    (but younger than 30 days) and re-checks each against the Flutterwave
    API via the same verification path the redirect flow uses. Payments
    confirmed successful are credited and the thank-you is queued;
    confirmed failures are marked FAILED.

    Also expires PENDING Flutterwave payments older than 30 days (their
    checkout links are long dead) by marking them CANCELLED, so rows created
    by automated reminder links never accumulate as stale pending revenue.

    Returns:
        Dict with keys: checked, completed, failed, still_pending, expired.
    """
    from app.integrations.webhook_handlers import handle_payment_verification
    from app.models.sponsor import PaymentStatusEnum, SponsorPayment

    stats = {"checked": 0, "completed": 0, "failed": 0, "still_pending": 0, "expired": 0}
    now = datetime.now(timezone.utc)
    min_age = now - timedelta(minutes=15)
    max_age = now - timedelta(days=30)

    try:
        with get_db_context() as db:
            stale_pending = (
                db.query(SponsorPayment)
                .filter(
                    SponsorPayment.status == PaymentStatusEnum.PENDING,
                    SponsorPayment.deleted_at.is_(None),
                    SponsorPayment.tx_ref.isnot(None),
                    SponsorPayment.payment_method == "FLUTTERWAVE",
                    SponsorPayment.created_at <= min_age,
                    SponsorPayment.created_at >= max_age,
                )
                .order_by(SponsorPayment.created_at)
                .limit(100)
                .all()
            )

            for payment in stale_pending:
                stats["checked"] += 1
                try:
                    result = _run_async(
                        handle_payment_verification(tx_ref=payment.tx_ref, db=db)
                    )
                    status = result.get("status")
                    if status == "successful":
                        stats["completed"] += 1
                    elif status == "failed":
                        stats["failed"] += 1
                    else:
                        stats["still_pending"] += 1
                except Exception as exc:
                    logger.error(
                        "reconcile_pending_payments: error for tx_ref=%s: %s",
                        payment.tx_ref,
                        str(exc),
                    )
                    stats["still_pending"] += 1

            # Expire never-paid link payments older than 30 days
            expired_rows = (
                db.query(SponsorPayment)
                .filter(
                    SponsorPayment.status == PaymentStatusEnum.PENDING,
                    SponsorPayment.deleted_at.is_(None),
                    SponsorPayment.payment_method == "FLUTTERWAVE",
                    SponsorPayment.created_at < max_age,
                )
                .limit(500)
                .all()
            )
            for payment in expired_rows:
                payment.status = PaymentStatusEnum.CANCELLED
                payment.notes = (
                    (payment.notes + " " if payment.notes else "")
                    + "Payment link expired without payment (auto-cancelled after 30 days)."
                )
                stats["expired"] += 1
            if expired_rows:
                db.flush()

    except Exception as exc:
        logger.error("reconcile_pending_payments fatal error: %s", str(exc), exc_info=True)
        stats["error"] = str(exc)

    logger.info("reconcile_pending_payments stats: %s", stats)
    return stats


@celery_app.task(name="send_overdue_payment_alerts", acks_late=True)
def send_overdue_payment_alerts() -> dict:
    """
    Query sponsors who are more than 7 days overdue and send
    a follow-up SMS and notify the sponsorship coordinator.

    This is a supplementary task to check_overdue_payments, focused
    specifically on the 7+ day cohort for more urgent action.

    Sponsors who already received a reminder within the last 6 days are
    skipped so the weekly job never double-texts on top of the daily one.

    Returns:
        Dict with keys: alerts_sent, coordinator_notified.
    """
    stats = {"alerts_sent": 0, "coordinator_notified": False}
    today = date.today()
    cutoff = today - timedelta(days=7)
    reminder_dedupe_cutoff = today - timedelta(days=6)

    try:
        with get_db_context() as db:
            summary_lines = []
            for sponsor, payment in _sponsors_with_latest_due(db):
                if payment.next_due_date >= cutoff:
                    continue  # not yet 7+ days overdue

                days_overdue = (today - payment.next_due_date).days

                recently_reminded = (
                    payment.reminder_sent_at is not None
                    and payment.reminder_sent_at.date() > reminder_dedupe_cutoff
                )

                if sponsor.phone and not recently_reminded:
                    try:
                        _send_overdue_sms_with_link(db, sponsor, payment.next_due_date)
                        payment.reminder_sent_at = datetime.now(timezone.utc)
                        db.flush()
                        stats["alerts_sent"] += 1
                    except Exception as sms_exc:
                        logger.error(
                            "send_overdue_payment_alerts SMS error: sponsor=%s error=%s",
                            sponsor.id,
                            str(sms_exc),
                        )

                summary_lines.append(
                    f"- {sponsor.full_name}: ₦{float(sponsor.amount):,.0f} "
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
