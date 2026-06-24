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
        self._brevo = None

        try:
            from app.integrations.brevo import BrevoClient
            self._brevo = BrevoClient()
        except Exception:
            self._brevo = None

    def queue_sms(self, phone: Optional[str], message: str) -> None:
        if not phone or not self._termii:
            return
        try:
            import asyncio
            loop = asyncio.get_event_loop()
            if loop.is_running():
                loop.create_task(self._termii.send_sms(phone, message))
            else:
                loop.run_until_complete(self._termii.send_sms(phone, message))
        except Exception:
            pass

    def queue_email(self, to_email: str, subject: str, body: str) -> None:
        if not self._brevo:
            return
        try:
            self._brevo.send_email(
                to_email=to_email,
                subject=subject,
                html_content=body,
            )
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
