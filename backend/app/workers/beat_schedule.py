"""
Genesis Global CMS — Celery Beat Schedule

Defines all periodic tasks for the Genesis Global CMS backend.
All times are in Africa/Lagos (WAT, UTC+1). The celery_app timezone
is set to "Africa/Lagos" so crontab() arguments map to local time.

Schedule summary:
  08:00 daily   — send_daily_followup_reminders
  09:00 daily   — check_overdue_payments
  */4 hours     — escalate_overdue_followups
  Monday 07:00  — flag_inactive_members
  Monday 07:30  — send_duplicate_member_digest
  */5 minutes   — process_notification_queue
  Quarterly     — send_quarterly_review_reminders (Jan/Apr/Jul/Oct 1st at 08:00)
"""
from celery.schedules import crontab

from app.workers.celery_app import celery_app

celery_app.conf.beat_schedule = {
    # ── Daily at 08:00 Lagos time ──────────────────────────────────────────────
    "daily-followup-reminders": {
        "task": "send_daily_followup_reminders",
        "schedule": crontab(hour=8, minute=0),
        "options": {"expires": 3600},   # expire if not consumed within 1 hour
    },

    # ── Daily at 09:00 Lagos time ──────────────────────────────────────────────
    "check-overdue-payments": {
        "task": "check_overdue_payments",
        "schedule": crontab(hour=9, minute=0),
        "options": {"expires": 3600},
    },

    # ── Every 4 hours (00:00, 04:00, 08:00, 12:00, 16:00, 20:00) ─────────────
    "escalate-overdue-followups": {
        "task": "escalate_overdue_followups",
        "schedule": crontab(minute=0, hour="*/4"),
        "options": {"expires": 3600},
    },

    # ── Weekly: Monday at 07:00 Lagos time ────────────────────────────────────
    "flag-inactive-members": {
        "task": "flag_inactive_members",
        "schedule": crontab(hour=7, minute=0, day_of_week=1),
        "options": {"expires": 7200},
    },

    # ── Weekly: Monday at 07:30 Lagos time ────────────────────────────────────
    "send-duplicate-member-digest": {
        "task": "send_duplicate_member_digest",
        "schedule": crontab(hour=7, minute=30, day_of_week=1),
        "options": {"expires": 7200},
    },

    # ── Every 5 minutes ───────────────────────────────────────────────────────
    "process-notification-queue": {
        "task": "process_notification_queue",
        "schedule": crontab(minute="*/5"),
        "options": {"expires": 240},    # expire after 4 minutes if not consumed
    },

    # ── Weekly: Sunday at 20:00 Lagos time — overdue sponsor alerts ───────────
    "weekly-overdue-payment-alerts": {
        "task": "send_overdue_payment_alerts",
        "schedule": crontab(hour=20, minute=0, day_of_week=0),
        "options": {"expires": 3600},
    },

    # ── Quarterly: 1st of Jan, Apr, Jul, Oct at 08:00 Lagos time ─────────────
    "quarterly-review-reminders": {
        "task": "send_quarterly_review_reminders",
        "schedule": crontab(
            hour=8,
            minute=0,
            day_of_month=1,
            month_of_year="1,4,7,10",
        ),
        "options": {"expires": 7200},
    },
}

# Beat schedule timezone must match the application timezone
celery_app.conf.beat_schedule_filename = "celerybeat-schedule"
