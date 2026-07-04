"""
Genesis Global CMS — Notification Queue Helper

Provides a simple helper to insert jobs into the notification_queue table.
Actual sending is done by a separate worker process.
"""
import logging
import uuid
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy.orm import Session

from app.models.notification import NotificationQueue

logger = logging.getLogger(__name__)


class NotificationService:
    """Facade for sending SMS and email notifications."""

    def __init__(self) -> None:
        try:
            from app.integrations.termii import TermiiClient
            self._termii = TermiiClient()
        except Exception as exc:
            logger.error("NotificationService: Termii client init failed: %s", exc)
            self._termii = None

        try:
            from app.integrations.brevo import BrevoClient
            self._brevo = BrevoClient()
        except Exception as exc:
            logger.error("NotificationService: Brevo client init failed: %s", exc)
            self._brevo = None

    def queue_sms(self, phone: Optional[str], message: str) -> None:
        """
        Dispatch an SMS via the Celery send_sms task (which retries with
        backoff and records failures). Failures are logged loudly — never
        swallowed silently — but do not propagate to the caller.
        """
        if not phone:
            logger.warning("queue_sms: no phone number provided — SMS not sent")
            return
        try:
            from app.workers.tasks.notification_tasks import send_sms_task
            send_sms_task.delay(phone=phone, message=message)
        except Exception as exc:
            logger.error(
                "queue_sms: failed to enqueue SMS to %s (broker unavailable?): %s",
                phone,
                exc,
                exc_info=True,
            )

    def queue_email(self, to_email: str, subject: str, body: str) -> None:
        """
        Send a transactional email via Brevo. Failures are logged with the
        recipient and subject — never swallowed silently — but do not
        propagate to the caller.
        """
        if not self._brevo:
            logger.error("queue_email: Brevo client unavailable — email to %s not sent", to_email)
            return
        try:
            sent = self._brevo.send_email(
                to_email=to_email,
                subject=subject,
                html_content=body,
            )
            if not sent:
                logger.error("queue_email: Brevo rejected email to %s (subject=%s)", to_email, subject)
        except Exception as exc:
            logger.error(
                "queue_email: send to %s failed: %s", to_email, exc, exc_info=True
            )


def queue_notification(
    db: Session,
    recipient_type: str,
    recipient_id: uuid.UUID,
    channel: str,
    template_key: str,
    payload: Optional[dict] = None,
    scheduled_for: Optional[datetime] = None,
) -> NotificationQueue:
    """
    Insert a notification job into the notification_queue table.

    Args:
        db:             Database session.
        recipient_type: 'USER', 'MEMBER', or 'SPONSOR'.
        recipient_id:   UUID of the recipient entity.
        channel:        'SMS', 'EMAIL', 'WHATSAPP', or 'IN_APP'.
        template_key:   Identifies the message template.
        payload:        Template variables as a dict.
        scheduled_for:  When to send. Defaults to now (immediate).

    Returns:
        The newly created NotificationQueue record (not yet committed).
    """
    notification = NotificationQueue(
        recipient_type=recipient_type,
        recipient_id=recipient_id,
        channel=channel,
        template_key=template_key,
        payload=payload or {},
        status="PENDING",
        scheduled_for=scheduled_for or datetime.now(timezone.utc),
    )
    db.add(notification)
    return notification
