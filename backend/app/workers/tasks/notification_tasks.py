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
    thank-you notifications by email and phone channel where available.

    Marks thank_you_sent_at on the payment record on success.

    Args:
        payment_id: UUID string of the SponsorPayment record.

    Returns:
        Dict with keys: success, payment_id, channels, message.
    """
    from app.integrations.termii import termii
    from app.models.sponsor import PaymentStatusEnum, SponsorPayment, Sponsor

    result = {
        "success": False,
        "payment_id": payment_id,
        "channel": None,
        "channels": [],
        "message": "",
    }
    try:
        with get_db_context() as db:
            payment = db.query(SponsorPayment).filter(
                SponsorPayment.id == uuid.UUID(payment_id)
            ).first()

            if not payment:
                result["message"] = f"Payment {payment_id} not found"
                logger.warning("send_payment_thank_you: payment not found: %s", payment_id)
                return result

            # Idempotency: webhooks can be re-delivered — never thank twice
            if payment.thank_you_sent_at is not None:
                result["success"] = True
                result["message"] = "Thank-you already sent — skipping duplicate"
                logger.info(
                    "send_payment_thank_you: already sent for payment=%s — skipping", payment_id
                )
                return result

            if payment.status != PaymentStatusEnum.COMPLETED:
                result["message"] = "Payment is not completed - thank-you not sent"
                logger.info(
                    "send_payment_thank_you: payment=%s status=%s - skipping",
                    payment_id,
                    payment.status,
                )
                return result

            sponsor: Optional[Sponsor] = db.query(Sponsor).filter(
                Sponsor.id == payment.sponsor_id,
                Sponsor.deleted_at.is_(None),
            ).first()

            if not sponsor:
                result["message"] = "Sponsor not found"
                logger.warning("send_payment_thank_you: sponsor not found for payment=%s", payment_id)
                return result

            first_name = sponsor.full_name.split()[0] if sponsor.full_name else "Friend"
            amount_str = f"{payment.amount:,.0f}"
            preferred = sponsor.preferred_channel.value.lower() if sponsor.preferred_channel else "sms"

            sent_channels: list[str] = []
            failed_channels: list[str] = []

            if sponsor.email:
                from app.integrations.brevo import BrevoClient
                brevo = BrevoClient()
                html_body = (
                    f"<p>Dear {sponsor.full_name},</p>"
                    f"<p>Thank you for your generous contribution of "
                    f"<strong>₦{amount_str}</strong> to Genesis Global. "
                    f"Your support makes a real difference. God bless you!</p>"
                    f"<p>The Genesis Global Finance Team</p>"
                )
                try:
                    sent = brevo.send_email(
                        to_email=sponsor.email,
                        subject="Thank You for Your Generosity — Genesis Global",
                        html_content=html_body,
                    )
                    if sent:
                        sent_channels.append("EMAIL")
                    else:
                        failed_channels.append("EMAIL")
                except Exception as email_exc:
                    logger.error("send_payment_thank_you email error: %s", str(email_exc))
                    failed_channels.append("EMAIL")

            if sponsor.phone:
                phone_channel = "whatsapp" if preferred == "whatsapp" else "generic"
                channel_name = "WHATSAPP" if phone_channel == "whatsapp" else "SMS"
                try:
                    _run_async(
                        termii.send_templated_message(
                            to=sponsor.phone,
                            template_key="payment_thank_you",
                            template_vars={"name": first_name, "amount": amount_str},
                            channel=phone_channel,
                        )
                    )
                    sent_channels.append(channel_name)
                except Exception as sms_exc:
                    logger.error(
                        "send_payment_thank_you %s error: %s",
                        channel_name.lower(),
                        str(sms_exc),
                    )
                    failed_channels.append(channel_name)

            if not sponsor.phone and not sponsor.email:
                result["message"] = "Sponsor has no contact info for notifications"
                logger.warning(
                    "send_payment_thank_you: sponsor=%s has no phone or email", sponsor.id
                )
                return result

            if sent_channels:
                # Update thank_you_sent_at
                payment.thank_you_sent_at = datetime.now(timezone.utc)
                db.flush()

        result["success"] = bool(sent_channels)
        result["channel"] = ",".join(sent_channels) if sent_channels else None
        result["channels"] = sent_channels
        if sent_channels and failed_channels:
            result["message"] = (
                f"Thank-you sent via {', '.join(sent_channels)}; "
                f"failed via {', '.join(failed_channels)}"
            )
        elif sent_channels:
            result["message"] = f"Thank-you sent via {', '.join(sent_channels)}"
        else:
            result["message"] = "Notification failed"
        logger.info(
            "send_payment_thank_you: payment=%s channels=%s success=%s",
            payment_id,
            sent_channels,
            bool(sent_channels),
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
    from app.models.sponsor import PaymentStatusEnum, Sponsor, SponsorPayment
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

            # Due-date tracking lives on the latest completed payment record
            latest_payment = (
                db.query(SponsorPayment)
                .filter(
                    SponsorPayment.sponsor_id == sponsor.id,
                    SponsorPayment.deleted_at.is_(None),
                    SponsorPayment.status == PaymentStatusEnum.COMPLETED,
                    SponsorPayment.next_due_date.isnot(None),
                )
                .order_by(SponsorPayment.payment_date.desc().nulls_last())
                .first()
            )

            due_date_str = (
                latest_payment.next_due_date.strftime("%d %b %Y")
                if latest_payment
                else "soon"
            )
            amount_str = f"{float(sponsor.amount):,.0f}"
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

            if latest_payment:
                latest_payment.reminder_sent_at = dt.now(timezone.utc)
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
    from app.auth.models import AppUser, UserRole
    from app.integrations.brevo import BrevoClient

    brevo = BrevoClient()
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
                ok = brevo.send_email(
                    to_email=email,
                    subject=subject,
                    html_content=html_body,
                    text_content=message,
                )
                if ok:
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


def _resolve_queue_recipient(db, recipient_type: str, recipient_id) -> tuple:
    """
    Resolve a notification_queue recipient to (name, phone, email).
    Returns (None, None, None) when the recipient cannot be found.
    """
    rtype = (recipient_type or "").upper()

    if rtype == "SPONSOR":
        from app.models.sponsor import Sponsor
        sponsor = db.query(Sponsor).filter(
            Sponsor.id == recipient_id, Sponsor.deleted_at.is_(None)
        ).first()
        if sponsor:
            return sponsor.full_name, sponsor.phone, sponsor.email

    elif rtype == "MEMBER":
        from app.models.member import MemberModel
        member = db.query(MemberModel).filter(
            MemberModel.id == recipient_id, MemberModel.deleted_at.is_(None)
        ).first()
        if member:
            return member.full_name, member.phone, member.email

    elif rtype == "USER":
        from app.auth.models import AppUser
        user = db.get(AppUser, recipient_id)
        if user:
            name = user.member.full_name if getattr(user, "member", None) else user.email
            return name, None, user.email

    return None, None, None


def _render_queue_message(template_key: str, payload: dict, recipient_name: str) -> tuple:
    """
    Render a queued notification into (subject, message_text).

    Known template keys are rendered from the payload's template variables;
    otherwise the payload's explicit subject/message fields are used as-is.
    """
    from app.integrations.termii import TEMPLATES

    key = (template_key or "").upper()
    display_name = (payload.get("sponsor_name") or recipient_name or "Friend").split()[0]

    if key == "PAYMENT_THANK_YOU":
        amount = float(payload.get("amount", 0))
        message = TEMPLATES["payment_thank_you"].format(
            name=display_name, amount=f"{amount:,.0f}"
        )
        return "Thank You for Your Generosity — Genesis Global", message

    if key == "PAYMENT_REMINDER":
        amount = float(payload.get("amount", 0))
        message = TEMPLATES["payment_reminder"].format(
            name=display_name,
            amount=f"{amount:,.0f}",
            date=payload.get("date", "soon"),
        )
        return "Sponsorship Payment Reminder — Genesis Global", message

    if key == "WELCOME_MEMBER":
        message = TEMPLATES["welcome_member"].format(name=display_name)
        return "Welcome to Genesis Global!", message

    # Fallback: payload carries a pre-rendered message
    return (
        payload.get("subject", "Genesis Global Notification"),
        payload.get("message", ""),
    )


@celery_app.task(name="process_notification_queue", acks_late=True)
def process_notification_queue() -> dict:
    """
    Process due PENDING items in the notification_queue table.

    For each pending item:
      - Resolve the recipient's contact info from recipient_type/recipient_id
        (falls back to explicit phone/email in the payload)
      - Render the message from template_key + payload
      - Route to the appropriate channel (SMS, WhatsApp, or Email)
      - Update status to SENT or FAILED
      - Increment retry_count on failure (marked FAILED after 5 retries)

    Rows are claimed with SELECT ... FOR UPDATE SKIP LOCKED so overlapping
    runs never double-send (a no-op on SQLite in tests).

    Returns:
        Dict with keys: processed, sent, failed.
    """
    from app.models.notification import NotificationQueue
    from app.integrations.termii import termii

    stats = {"processed": 0, "sent": 0, "failed": 0}
    now = datetime.now(timezone.utc)

    try:
        with get_db_context() as db:
            pending_items = (
                db.query(NotificationQueue)
                .filter(
                    NotificationQueue.status == "PENDING",
                    NotificationQueue.retry_count < 5,
                    NotificationQueue.scheduled_for <= now,
                )
                .order_by(NotificationQueue.scheduled_for)
                .limit(100)  # Process max 100 per run to avoid timeout
                .with_for_update(skip_locked=True)
                .all()
            )

            for item in pending_items:
                stats["processed"] += 1
                sent = False
                error_msg = ""

                try:
                    payload: dict = item.payload or {}
                    channel = item.channel.lower()

                    name, phone, email = _resolve_queue_recipient(
                        db, item.recipient_type, item.recipient_id
                    )
                    # Explicit contact details in the payload win
                    phone = payload.get("phone") or phone
                    email = payload.get("email") or email

                    subject, message = _render_queue_message(
                        item.template_key, payload, name
                    )

                    if not message:
                        error_msg = f"No message content for template '{item.template_key}'"

                    elif channel in ("sms", "generic", "dnd"):
                        if phone:
                            _run_async(
                                termii.send_sms(
                                    to=phone, message=message, channel="generic"
                                )
                            )
                            sent = True
                        else:
                            error_msg = "Recipient has no phone number"

                    elif channel == "whatsapp":
                        if phone:
                            _run_async(termii.send_whatsapp(to=phone, message=message))
                            sent = True
                        else:
                            error_msg = "Recipient has no phone number"

                    elif channel == "email":
                        if email:
                            from app.integrations.brevo import BrevoClient
                            brevo = BrevoClient()
                            html_content = (
                                f"<html><body><p>{message}</p>"
                                "<hr><p style='color:#666;font-size:12px;'>Genesis Global CMS</p>"
                                "</body></html>"
                            )
                            sent = brevo.send_email(
                                to_email=email,
                                subject=subject,
                                html_content=html_content,
                                text_content=message,
                            )
                            if not sent:
                                error_msg = "Email provider rejected the message"
                        else:
                            error_msg = "Recipient has no email address"

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
                        logger.error(
                            "process_notification_queue: item %s permanently FAILED "
                            "(template=%s channel=%s): %s",
                            item.id,
                            item.template_key,
                            item.channel,
                            error_msg,
                        )
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
