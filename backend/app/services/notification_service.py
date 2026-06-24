"""
Genesis Global CMS — Notification Queue Helper

Provides a simple helper to insert jobs into the notification_queue table.
Actual sending is done by a separate worker process.
"""
import uuid
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy.orm import Session

from app.models.notification import NotificationQueue


class NotificationService:
    """Facade for sending SMS and email notifications."""

    def __init__(self) -> None:
        try:
            from app.integrations.termii import TermiiClient
            self._termii = TermiiClient()
        except Exception:
            self._termii = None

        try:
            from app.integrations.sendgrid import SendGridClient
            self._sendgrid = SendGridClient()
        except Exception:
            self._sendgrid = None

    def queue_sms(self, phone: Optional[str], message: str) -> None:
        if not phone or not self._termii:
            return
        try:
            self._termii.send_sms(phone, message)
        except Exception:
            pass

    def queue_email(self, to_email: str, subject: str, body: str) -> None:
        if not self._sendgrid:
            return
        try:
            self._sendgrid.send_email(to_email=to_email, subject=subject, body=body)
        except Exception:
            pass


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
