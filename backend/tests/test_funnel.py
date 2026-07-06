"""
Genesis Global CMS — Donor Payment Funnel Tests

Covers:
1.  Funnel endpoint: status classification (PAID / PENDING / OVERDUE)
2.  Funnel endpoint: tenure bucketing and summary matrix
3.  Funnel config: defaults, update, validation, access control
4.  Staged reminder task: stage 1 → 2 → 3 fire once each per cycle
"""
import uuid
from contextlib import contextmanager
from datetime import date, datetime, timedelta, timezone
from unittest.mock import MagicMock, patch

import pytest

from tests.conftest import auth_headers
from tests.utils import create_sponsor, create_sponsor_payment
from app.models.sponsor import PaymentStatusEnum, SponsorshipTierEnum


# ── Funnel analytics endpoint ─────────────────────────────────────────────────

def test_funnel_classifies_paid_pending_overdue(client, db, finance_user, finance_token):
    """Donors are classified PAID (future due), OVERDUE (past due), PENDING (never paid)."""
    today = date.today()

    paid = create_sponsor(db, full_name="Paid Donor", created_by=finance_user.id)
    create_sponsor_payment(
        db, sponsor_id=paid.id, amount=5000,
        payment_date=datetime.now(timezone.utc),
        next_due_date=today + timedelta(days=10),
    )

    overdue = create_sponsor(db, full_name="Overdue Donor", created_by=finance_user.id)
    create_sponsor_payment(
        db, sponsor_id=overdue.id, amount=5000,
        payment_date=datetime.now(timezone.utc) - timedelta(days=40),
        next_due_date=today - timedelta(days=10),
    )

    create_sponsor(db, full_name="Never Paid Donor", created_by=finance_user.id)

    response = client.get("/api/v1/giving/funnel", headers=auth_headers(finance_token))

    assert response.status_code == 200
    data = response.json()["data"]
    statuses = {d["full_name"]: d["status"] for d in data["donors"]}
    assert statuses["Paid Donor"] == "PAID"
    assert statuses["Overdue Donor"] == "OVERDUE"
    assert statuses["Never Paid Donor"] == "PENDING"
    assert data["summary"]["paid"] >= 1
    assert data["summary"]["overdue"] >= 1
    assert data["summary"]["pending"] >= 1

    overdue_entry = next(d for d in data["donors"] if d["full_name"] == "Overdue Donor")
    assert overdue_entry["days_overdue"] == 10


def test_funnel_buckets_tenure(client, db, finance_user, finance_token):
    """A donor giving for 14 months lands in the 1_YEAR_PLUS bucket."""
    veteran = create_sponsor(db, full_name="Veteran Donor", created_by=finance_user.id)
    first = datetime.now(timezone.utc) - timedelta(days=430)
    create_sponsor_payment(
        db, sponsor_id=veteran.id, amount=5000,
        payment_date=first,
        next_due_date=date.today() + timedelta(days=5),
    )
    create_sponsor_payment(
        db, sponsor_id=veteran.id, amount=5000,
        payment_date=datetime.now(timezone.utc) - timedelta(days=20),
        next_due_date=date.today() + timedelta(days=10),
    )

    response = client.get("/api/v1/giving/funnel", headers=auth_headers(finance_token))

    assert response.status_code == 200
    data = response.json()["data"]
    entry = next(d for d in data["donors"] if d["full_name"] == "Veteran Donor")
    assert entry["tenure_bucket"] == "1_YEAR_PLUS"
    assert entry["tenure_months"] >= 12
    assert entry["payments_count"] == 2
    assert data["tenure_matrix"]["1_YEAR_PLUS"]["total"] >= 1


def test_funnel_blocked_for_non_finance(client, db, hr_user, hr_token):
    response = client.get("/api/v1/giving/funnel", headers=auth_headers(hr_token))
    assert response.status_code == 403


# ── Funnel config endpoints ───────────────────────────────────────────────────

def test_funnel_config_defaults(client, db, finance_user, finance_token):
    """Config endpoint returns defaults when nothing is stored."""
    response = client.get(
        "/api/v1/giving/funnel/config", headers=auth_headers(finance_token)
    )
    assert response.status_code == 200
    data = response.json()["data"]
    assert data["stage1_days_before_due"] == 7
    assert data["stage2_days_overdue"] == 14
    assert data["stage3_days_overdue"] == 21
    assert data["enabled"] is True


def test_funnel_config_update_and_persist(client, db, finance_user, finance_token):
    """Updating the schedule persists and is returned on the next GET."""
    response = client.put(
        "/api/v1/giving/funnel/config",
        json={"stage1_days_before_due": 5, "stage2_days_overdue": 10,
              "stage3_days_overdue": 25},
        headers=auth_headers(finance_token),
    )
    assert response.status_code == 200
    assert response.json()["data"]["stage2_days_overdue"] == 10

    response = client.get(
        "/api/v1/giving/funnel/config", headers=auth_headers(finance_token)
    )
    assert response.json()["data"]["stage3_days_overdue"] == 25


def test_funnel_config_rejects_bad_ordering(client, db, finance_user, finance_token):
    """Final notice must come after the week-3 nudge."""
    response = client.put(
        "/api/v1/giving/funnel/config",
        json={"stage2_days_overdue": 20, "stage3_days_overdue": 15},
        headers=auth_headers(finance_token),
    )
    assert response.status_code == 422


def test_funnel_config_blocked_for_non_finance(client, db, hr_user, hr_token):
    response = client.put(
        "/api/v1/giving/funnel/config",
        json={"stage1_days_before_due": 3},
        headers=auth_headers(hr_token),
    )
    assert response.status_code == 403


# ── Staged reminder task ──────────────────────────────────────────────────────

@contextmanager
def _test_db_context(db):
    yield db


def _run_funnel_with(db):
    """Run check_overdue_payments against the test session with sends mocked."""
    from app.workers.tasks import payment_tasks

    with patch.object(
        payment_tasks, "get_db_context", lambda: _test_db_context(db)
    ), patch.object(
        payment_tasks, "_send_overdue_sms_with_link"
    ) as mock_sms, patch(
        "app.workers.tasks.notification_tasks.send_payment_reminder"
    ) as mock_reminder, patch(
        "app.workers.tasks.notification_tasks.send_admin_notification"
    ) as mock_admin:
        mock_reminder.delay = MagicMock()
        mock_admin.delay = MagicMock()
        stats = payment_tasks.check_overdue_payments()
    return stats, mock_sms, mock_reminder, mock_admin


def test_funnel_stage1_fires_before_due(db, finance_user):
    """A donor due within 7 days gets the stage-1 reminder exactly once."""
    sponsor = create_sponsor(db, full_name="Stage1 Donor", created_by=finance_user.id)
    sponsor.phone = "08011111111"
    payment = create_sponsor_payment(
        db, sponsor_id=sponsor.id, amount=5000,
        payment_date=datetime.now(timezone.utc) - timedelta(days=25),
        next_due_date=date.today() + timedelta(days=3),
    )
    db.flush()

    stats, _, mock_reminder, _ = _run_funnel_with(db)
    assert stats["stage1_sent"] == 1
    mock_reminder.delay.assert_called_once_with(str(sponsor.id))
    assert payment.reminder_stage == 1

    # Second run: stage already fired — nothing new
    stats2, _, mock_reminder2, _ = _run_funnel_with(db)
    assert stats2["stage1_sent"] == 0


def test_funnel_stage2_and_stage3_escalate(db, finance_user):
    """14+ days overdue → week-3 nudge; 21+ days → final notice + escalation."""
    sponsor = create_sponsor(db, full_name="Escalate Donor", created_by=finance_user.id)
    sponsor.phone = "08022222222"
    payment = create_sponsor_payment(
        db, sponsor_id=sponsor.id, amount=5000,
        payment_date=datetime.now(timezone.utc) - timedelta(days=50),
        next_due_date=date.today() - timedelta(days=15),
    )
    db.flush()

    stats, mock_sms, _, _ = _run_funnel_with(db)
    assert stats["stage2_sent"] == 1
    assert payment.reminder_stage == 2
    mock_sms.assert_called_once()

    # Push past the final-notice threshold
    payment.next_due_date = date.today() - timedelta(days=22)
    db.flush()

    stats2, mock_sms2, _, mock_admin = _run_funnel_with(db)
    assert stats2["stage3_sent"] == 1
    assert payment.reminder_stage == 3
    mock_admin.delay.assert_called_once()
    # Final notice uses the dedicated template
    assert mock_sms2.call_args.kwargs.get("template_key") == "payment_final_notice"

    # Third run: fully escalated — silent
    stats3, _, _, _ = _run_funnel_with(db)
    assert stats3["stage1_sent"] == 0
    assert stats3["stage2_sent"] == 0
    assert stats3["stage3_sent"] == 0


def test_funnel_disabled_skips_all(db, finance_user):
    """Disabling the funnel in config stops all reminder sends."""
    from app.services.funnel_service import update_funnel_config

    sponsor = create_sponsor(db, full_name="Disabled Donor", created_by=finance_user.id)
    sponsor.phone = "08033333333"
    create_sponsor_payment(
        db, sponsor_id=sponsor.id, amount=5000,
        payment_date=datetime.now(timezone.utc) - timedelta(days=50),
        next_due_date=date.today() - timedelta(days=15),
    )
    update_funnel_config(db, {"enabled": False}, finance_user.id)
    db.flush()

    stats, mock_sms, mock_reminder, _ = _run_funnel_with(db)
    assert stats.get("skipped") == "funnel disabled in config"
    mock_sms.assert_not_called()
    mock_reminder.delay.assert_not_called()
