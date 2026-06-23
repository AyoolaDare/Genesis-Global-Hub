"""
Genesis Global CMS — Celery Application Configuration

Configures a Celery application backed by Upstash Redis (TLS) as both
broker and result backend. The timezone is set to Africa/Lagos so that
scheduled jobs (beat) fire at the correct local times.
"""
import ssl

from celery import Celery

from app.config import get_settings

settings = get_settings()

# ── Application Instance ───────────────────────────────────────────────────────

celery_app = Celery(
    "genesis_global",
    broker=settings.UPSTASH_REDIS_URL,
    backend=settings.UPSTASH_REDIS_URL,
    include=[
        "app.workers.tasks.payment_tasks",
        "app.workers.tasks.followup_tasks",
        "app.workers.tasks.notification_tasks",
        "app.workers.tasks.cron_tasks",
    ],
)

# ── Configuration ──────────────────────────────────────────────────────────────

celery_app.conf.update(
    # Serialization
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",

    # Time zone — tasks scheduled via beat use Africa/Lagos wall time
    timezone="Africa/Lagos",
    enable_utc=True,

    # Reliability
    task_track_started=True,
    task_acks_late=True,
    worker_prefetch_multiplier=1,   # one task at a time per worker process

    # Result expiry — keep results for 24 hours
    result_expires=86400,

    # Upstash Redis requires TLS; ssl_cert_reqs=None skips hostname verification
    # which is necessary for Upstash's shared TLS certificates.
    broker_use_ssl={
        "ssl_cert_reqs": ssl.CERT_NONE,
    },
    redis_backend_use_ssl={
        "ssl_cert_reqs": ssl.CERT_NONE,
    },

    # Retry policy for broker connection
    broker_connection_retry_on_startup=True,
    broker_connection_max_retries=10,
)

# NOTE: The beat schedule is defined in app/workers/beat_schedule.py.
# It is imported lazily by Celery beat at startup — do NOT import it here
# as that would create a circular import (beat_schedule imports celery_app).
