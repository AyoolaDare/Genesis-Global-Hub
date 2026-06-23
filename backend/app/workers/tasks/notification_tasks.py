"""
Genesis Global CMS — Notification Celery Tasks

Handles all outbound communication:
  - Single SMS dispatch via Termii
  - Welcome SMS on member creation
  - Payment thank-you (SMS/WhatsApp/Email by channel preference)
  - Payment reminders
  - Admin email notifications
  - Processing the notification_queue table
"""
import asyncio
import logging
import uuid
from datetime import datetime, timezone
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


@celery_app.task(
    name="send_sms",
    bind=True,
    max_retries=3,
    default_retry_delay=60,
    acks_late=True,
)
def send_sms_task(
    self,
    phone: str,
    message: str,
    channel: str = "generic",
    notification_queue_id: Optional[str] = None,
) -> dict:
    """
    Send a single SMS (or WhatsApp) message via Termii.

    Retries up to 3 times with 60-second delays on failure.
    If notification_queue_id is provided, updates the queue record with
    SENT / FAILED status and sent_at timestamp.

    Args:
        phone:                 Recipient phone number (raw, will be normalized).
        message:               SMS body text.
        channel:               Termii channel: 'generic', 'dnd', 'whatsapp'.
        notification_queue_id: Optional UUID string of the NotificationQueue row to update.

    Returns:
        Dict with keys: success, message_id, channel, to.
    """
    from app.integrations.termii import termii

    result = {"success": False, "message_id": None, "channel": channel, "to": phone}
    try:
        response = _run_async(termii.send_sms(to=phone, message=message, channel=channel))
        result["success"] = True
        result["message_id"] = response.get("message_id")

        if notification_queue_id:
            _update_notification_status(notification_queue_id, status="SENT")

        logger.info("send_sms_task succeeded: to=%s channel=%s", phone, channel)
        return result

    except Exception as exc:
        logger.warning(
            "send_sms_task failed (attempt %s/%s): phone=%s error=%s",
            self.request.retries + 1,
            self.max_retries + 1,
            phone,
            str(exc),
        )
        if notification_queue_id:
            _update_notification_status(
                notification_queue_id,
                status="FAILED",
                error_message=str(exc),
            )
        try:
            raise self.retry(exc=exc, countdown=60 * (2 ** self.request.retries))
        except self.MaxRetriesExceededError:
            logger.error(
                "send_sms_task max retries exceeded: phone=%s channel=%s", phone, channel
            )
            result["error"] = str(exc)
            return result


@celery_app.task(name="send_welcome_sms", acks_late=True)
def send_welcome_sms(member_id: str) -> dict:
    """
    Load a member from the database and send them a welcome SMS.

    Args:
        member_id: UUID string of the MemberModel record.

    Returns:
        Dict with keys: success, member_id, message.
    """
    from app.integrations.termii import termii
    from app.models.member import MemberModel

    result = {"success": False, "member_id": member_id, "message": ""}
    try:
        with get_db_context() as db:
            member = db.query(MemberModel).filter(
                MemberModel.id == uuid.UUID(member_id),
                MemberModel.deleted_at.is_(None),
            ).first()

            if not member:
                result["message"] = f"Member {member_id} not found"
                logger.warning("send_welcome_sms: member not found: %s", member_id)
                return result

            if not member.phone:
                result["message"] = "Member has no phone number"
                logger.info("send_welcome_sms: member %s has no phone", member_id)
                return result

            _run_async(
                termii.send_templated_message(
                    to=member.phone,
                    template_key="welcome_member",
                    template_vars={"name": member.full_name.split()[0]},
                    channel="generic",
                )
            )

        result["success"] = True
        result["message"] = "Welcome SMS sent"
        logger.info("send_welcome_sms: sent to member=%s", member_id)
        return result

    except Exception as exc:
        logger.error("send_welcome_sms error: member=%s error=%s", member_id, str(exc))
        result["message"] = str(exc)
        return result


@celery_app.task(name="send_payment_thank_you", acks_late=True)
def send_payment_thank_you(payment_id: str) -> dict:
    """
    Load a SponsorPayment and its Sponsor from the database, then send
    a thank-you notification via the sponsor's preferred channel.

    Marks thank_you_sent_at on the payment record on success.

    Args:
        payment_id: UUID string of the SponsorPayment record.

    Returns:
        Dict with keys: success, payment_id, channel, message.
    """
    from app.integrations.termii import termii
    from app.integrations.sendgrid import sendgrid_client
    from app.models.sponsor import SponsorPayment, Sponsor

    result = {"success": False, "payment_id": payment_id, "channel": None, "message": ""}
    try:
        with get_db_context() as db:
            payment = db.query(SponsorPayment).filter(
                SponsorPayment.id == uuid.UUID(payment_id)
            ).first()

            if not payment:
                result["message"] = f"Payment {payment_id} not found"
                logger.warning("send_payment_thank_you: payment not found: %s", payment_id)
                return result

            sponsor: Optional[Sponsor] = db.query(Sponsor).filter(
                Sponsor.id == payment.sponsor_id,
                Sponsor.deleted_at.is_(None),
            ).first()

            if not sponsor:
                result["message"] = "Sponsor not found"
                logger.warning("send_payment_thank_you: sponsor not found for payment=%s", payment_id)
                return result

            first_name = sponsor.full_name.split()[0]
            amount_str = f"{payment.amount:,.0f}"
            channel = sponsor.preferred_channel.value.lower() if sponsor.preferred_channel else "sms"
            result["channel"] = channel

            sent = False

            if channel == "email" and sponsor.email:
                # Send via SendGrid
                sent = _run_async(
                    sendgrid_client.send_annual_sponsor_report(
                        to_email=sponsor.email,
                        sponsor_name=sponsor.full_name,
                        total_given=payment.amount,
                        payment_count=1,
                        year=datetime.now().year,
                    )
                )
                # Override with a simple thank-you email instead
                from sendgrid.helpers.mail import Mail
                from app.config import get_settings
                _settings = get_settings()
                from sendgrid import SendGridAPIClient
                mail = Mail(
                    from_email=_settings.FROM_EMAIL,
                    to_emails=sponsor.email,
                    subject="Thank You for Your Generosity — Genesis Global",
                    html_content=(
                        f"<p>Dear {sponsor.full_name},</p>"
                        f"<p>Thank you for your generous contribution of "
                        f"<strong>₦{amount_str}</strong> to Genesis Global. "
                        f"Your support makes a real difference. God bless you!</p>"
                        f"<p>The Genesis Global Finance Team</p>"
                    ),
                )
                try:
                    sg = SendGridAPIClient(_settings.SENDGRID_API_KEY)
                    resp = sg.send(mail)
                    sent = 200 <= resp.status_code < 300
                except Exception as email_exc:
                    logger.error("send_payment_thank_you email error: %s", str(email_exc))
                    sent = False

            elif channel == "whatsapp" and sponsor.phone:
                _run_async(
                    termii.send_templated_message(
                        to=sponsor.phone,
                        template_key="payment_thank_you",
                        template_vars={"name": first_name, "amount": amount_str},
                        channel="whatsapp",
                    )
                )
                sent = True

            elif sponsor.phone:
                # Default to SMS
                _run_async(
                    termii.send_templated_message(
                        to=sponsor.phone,
                        template_key="payment_thank_you",
                        template_vars={"name": first_name, "amount": amount_str},
                        channel="generic",
                    )
                )
                sent = True

            else:
                result["message"] = "Sponsor has no contact info for notifications"
                logger.warning(
                    "send_payment_thank_you: sponsor=%s has no phone or email", sponsor.id
                )
                return result

            if sent:
                # Update thank_you_sent_at
                payment.thank_you_sent_at = datetime.now(timezone.utc)
                db.flush()

        result["success"] = sent
        result["message"] = "Thank-you notification sent" if sent else "Notification failed"
        logger.info(
            "send_payment_thank_you: payment=%s channel=%s success=%s",
            payment_id,
            channel,
            sent,
        )
        return result

    except Exception as exc:
        logger.error(
            "send_payment_thank_you error: payment=%s error=%s", payment_id, str(exc),
            exc_info=True,
        )
        result["message"] = str(exc)
        return result


@celery_app.task(name="send_payment_reminder", acks_late=True)
def send_payment_reminder(sponsor_id: str) -> dict:
    """
    Load a Sponsor from the database and send a payment reminder via SMS.

    Updates reminder_sent_at on the Sponsor record.

    Args:
        sponsor_id: UUID string of the Sponsor record.

    Returns:
        Dict with keys: success, sponsor_id, message.
    """
    from app.integrations.termii import termii
    from app.models.sponsor import Sponsor
    from datetime import datetime as dt

    result = {"success": False, "sponsor_id": sponsor_id, "message": ""}
    try:
        with get_db_context() as db:
            sponsor = db.query(Sponsor).filter(
                Sponsor.id == uuid.UUID(sponsor_id),
                Sponsor.deleted_at.is_(None),
            ).first()

            if not sponsor:
                result["message"] = f"Sponsor {sponsor_id} not found"
                return result

            if not sponsor.phone:
                result["message"] = "Sponsor has no phone number"
                return result

            due_date_str = (
                sponsor.next_due_date.strftime("%d %b %Y")
                if sponsor.next_due_date
                else "soon"
            )
            amount_str = f"{sponsor.amount_per_period:,.0f}"
            first_name = sponsor.full_name.split()[0]

            _run_async(
                termii.send_templated_message(
                    to=sponsor.phone,
                    template_key="payment_reminder",
                    template_vars={
                        "name": first_name,
                        "amount": amount_str,
                        "date": due_date_str,
                    },
                    channel="generic",
                )
            )

            sponsor.reminder_sent_at = dt.now(timezone.utc)
            db.flush()

        result["success"] = True
        result["message"] = "Payment reminder sent"
        logger.info("send_payment_reminder: sent to sponsor=%s", sponsor_id)
        return result

    except Exception as exc:
        logger.error("send_payment_reminder error: sponsor=%s error=%s", sponsor_id, str(exc))
        result["message"] = str(exc)
        return result


@celery_app.task(name="send_admin_notification", acks_late=True)
def send_admin_notification(
    admin_email: Optional[str],
    subject: str,
    message: str,
) -> dict:
    """
    Send an email notification to an admin. If admin_email is None,
    the task looks up all users with FINANCE_ADMIN role.

    Args:
        admin_email: Target email address, or None to look up finance admins.
        subject:     Email subject.
        message:     Plain-text email body.

    Returns:
        Dict with keys: success, emails_sent, message.
    """
    from sendgrid import SendGridAPIClient
    from sendgrid.helpers.mail import Mail
    from app.config import get_settings
    from app.auth.models import AppUser, UserRole

    _settings = get_settings()
    result: dict = {"success": False, "emails_sent": 0, "message": ""}

    try:
        recipients: list[str] = []

        if admin_email:
            recipients = [admin_email]
        else:
            # Look up FINANCE_ADMIN users
            with get_db_context() as db:
                admins = db.query(AppUser).filter(
                    AppUser.role == UserRole.FINANCE_ADMIN,
                    AppUser.is_active.is_(True),
                ).all()
                recipients = [a.email for a in admins if a.email]

            if not recipients:
                # Fallback: look for any SUPER_ADMIN
                with get_db_context() as db:
                    super_admins = db.query(AppUser).filter(
                        AppUser.role == UserRole.SUPER_ADMIN,
                        AppUser.is_active.is_(True),
                    ).all()
                    recipients = [a.email for a in super_admins if a.email]

        if not recipients:
            result["message"] = "No admin recipients found"
            logger.warning("send_admin_notification: no recipients for subject='%s'", subject)
            return result

        sg = SendGridAPIClient(_settings.SENDGRID_API_KEY)
        sent_count = 0

        for email in recipients:
            try:
                html_body = (
                    f"<html><body>"
                    f"<h3>{subject}</h3>"
                    f"<pre style='font-family:sans-serif;white-space:pre-wrap;'>{message}</pre>"
                    f"<hr>"
                    f"<p style='color:#666;font-size:12px;'>Genesis Global CMS — Automated Notification</p>"
                    f"</body></html>"
                )
                mail = Mail(
                    from_email=_settings.FROM_EMAIL,
                    to_emails=email,
                    subject=subject,
                    html_content=html_body,
                )
                mail.plain_text_content = message
                resp = sg.send(mail)
                if 200 <= resp.status_code < 300:
                    sent_count += 1
            except Exception as email_exc:
                logger.error(
                    "send_admin_notification email error: to=%s error=%s", email, str(email_exc)
                )

        result["success"] = sent_count > 0
        result["emails_sent"] = sent_count
        result["message"] = f"Sent to {sent_count}/{len(recipients)} recipients"
        logger.info("send_admin_notification: %s", result["message"])
        return result

    except Exception as exc:
        logger.error("send_admin_notification error: %s", str(exc), exc_info=True)
        result["message"] = str(exc)
        return result


@celery_app.task(name="process_notification_queue", acks_late=True)
def process_notification_queue() -> dict:
    """
    Process all PENDING items in the notification_queue table.

    For each pending item:
      - Route to the appropriate channel (SMS, WhatsApp, or Email)
      - Update status to SENT or FAILED
      - Increment retry_count on failure (skip after 5 retries)

    Returns:
        Dict with keys: processed, sent, failed.
    """
    from app.models.notification import NotificationQueue
    from app.integrations.termii import termii
    from app.integrations.sendgrid import sendgrid_client

    stats = {"processed": 0, "sent": 0, "failed": 0}

    try:
        with get_db_context() as db:
            pending_items = (
                db.query(NotificationQueue)
                .filter(
                    NotificationQueue.status == "PENDING",
                    NotificationQueue.retry_count < 5,
                )
                .limit(100)  # Process max 100 per run to avoid timeout
                .all()
            )

            for item in pending_items:
                stats["processed"] += 1
                sent = False
                error_msg = ""

                try:
                    payload: dict = item.payload or {}
                    channel = item.channel.lower()

                    if channel in ("sms", "generic", "dnd"):
                        phone = payload.get("phone", "")
                        message = payload.get("message", "")
                        if phone and message:
                            _run_async(
                                termii.send_sms(
                                    to=phone, message=message, channel="generic"
                                )
                            )
                            sent = True

                    elif channel == "whatsapp":
                        phone = payload.get("phone", "")
                        message = payload.get("message", "")
                        if phone and message:
                            _run_async(termii.send_whatsapp(to=phone, message=message))
                            sent = True

                    elif channel == "email":
                        to_email = payload.get("email", "")
                        subject = payload.get("subject", "Genesis Global Notification")
                        message = payload.get("message", "")
                        if to_email and message:
                            from sendgrid import SendGridAPIClient
                            from sendgrid.helpers.mail import Mail
                            from app.config import get_settings
                            _settings = get_settings()
                            mail = Mail(
                                from_email=_settings.FROM_EMAIL,
                                to_emails=to_email,
                                subject=subject,
                                plain_text_content=message,
                            )
                            sg = SendGridAPIClient(_settings.SENDGRID_API_KEY)
                            resp = sg.send(mail)
                            sent = 200 <= resp.status_code < 300

                    else:
                        logger.warning(
                            "process_notification_queue: unknown channel '%s' for item %s",
                            channel,
                            item.id,
                        )
                        error_msg = f"Unknown channel: {channel}"

                except Exception as item_exc:
                    error_msg = str(item_exc)
                    logger.error(
                        "process_notification_queue: error for item=%s: %s",
                        item.id,
                        error_msg,
                    )

                # Update item status
                if sent:
                    item.status = "SENT"
                    item.sent_at = datetime.now(timezone.utc)
                    item.error_message = None
                    stats["sent"] += 1
                else:
                    item.retry_count = (item.retry_count or 0) + 1
                    item.error_message = error_msg
                    if item.retry_count >= 5:
                        item.status = "FAILED"
                    stats["failed"] += 1

            db.flush()

    except Exception as exc:
        logger.error("process_notification_queue fatal error: %s", str(exc), exc_info=True)
        stats["error"] = str(exc)

    logger.info("process_notification_queue stats: %s", stats)
    return stats


# ── Internal Helpers ───────────────────────────────────────────────────────────

def _update_notification_status(
    notification_queue_id: str,
    status: str,
    error_message: Optional[str] = None,
) -> None:
    """Update a NotificationQueue row's status and sent_at/error_message."""
    try:
        from app.models.notification import NotificationQueue
        with get_db_context() as db:
            item = db.query(NotificationQueue).filter(
                NotificationQueue.id == uuid.UUID(notification_queue_id)
            ).first()
            if item:
                item.status = status
                if status == "SENT":
                    item.sent_at = datetime.now(timezone.utc)
                if error_message:
                    item.error_message = error_message
                    item.retry_count = (item.retry_count or 0) + 1
                db.flush()
    except Exception as exc:
        logger.error(
            "_update_notification_status error: id=%s error=%s",
            notification_queue_id,
            str(exc),
        )
