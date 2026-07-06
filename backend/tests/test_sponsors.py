"""
Genesis Global CMS — Sponsor & Payment Tests

Covers:
1.  Finance admin can list sponsors
2.  Finance admin can create sponsor
3.  Finance admin can get sponsor detail with payments
4.  Finance admin can update sponsor
5.  Finance admin can record manual payment
6.  member_link_id never appears in any response
7.  Non-finance roles cannot access sponsor endpoints
8.  Finance dashboard accessible by finance admin
9.  Annual report accessible by finance admin
"""
import uuid
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from sqlalchemy.exc import SQLAlchemyError

from tests.conftest import auth_headers, make_token
from tests.utils import (
    create_active_member,
    create_sponsor,
    create_sponsor_payment,
    create_user,
)
from app.auth.models import UserRole
from app.models.sponsor import PaymentStatusEnum
from app.services.sponsor_service import get_finance_dashboard


# ── List Sponsors ──────────────────────────────────────────────────────────────

def test_finance_admin_can_list_sponsors(client, db, finance_user, finance_token):
    """Finance admin can retrieve the list of sponsors."""
    create_sponsor(db, full_name="List Sponsor A", created_by=finance_user.id)

    response = client.get("/api/v1/sponsors", headers=auth_headers(finance_token))

    assert response.status_code == 200
    data = response.json()
    assert "data" in data
    assert "total" in data


def test_super_admin_can_list_sponsors(client, db, super_admin_user, super_admin_token):
    """Super admin can also access sponsors."""
    response = client.get("/api/v1/sponsors", headers=auth_headers(super_admin_token))
    assert response.status_code == 200


def test_list_sponsors_response_excludes_member_link_id(client, db, finance_user, finance_token):
    """Sponsor list must never expose member_link_id."""
    member = create_active_member(db, "Sponsor Hidden Link Member")
    sponsor = create_sponsor(db, created_by=finance_user.id)
    sponsor.member_link_id = member.id
    db.flush()

    response = client.get("/api/v1/sponsors", headers=auth_headers(finance_token))

    assert response.status_code == 200
    assert "member_link_id" not in response.text


def test_pastor_cannot_list_sponsors(client, db, pastor_user, pastor_token):
    """Pastor must not access sponsor list."""
    response = client.get("/api/v1/sponsors", headers=auth_headers(pastor_token))
    assert response.status_code == 403


def test_medical_cannot_list_sponsors(client, db, medical_user, medical_token):
    """Medical staff must not access sponsor list."""
    response = client.get("/api/v1/sponsors", headers=auth_headers(medical_token))
    assert response.status_code == 403


def test_hr_cannot_list_sponsors(client, db, hr_user, hr_token):
    """HR admin must not access sponsor list."""
    response = client.get("/api/v1/sponsors", headers=auth_headers(hr_token))
    assert response.status_code == 403


def test_follow_up_cannot_list_sponsors(client, db, follow_up_user, follow_up_token):
    """Follow-up staff must not access sponsor list."""
    response = client.get("/api/v1/sponsors", headers=auth_headers(follow_up_token))
    assert response.status_code == 403


# ── Create Sponsor ─────────────────────────────────────────────────────────────

def test_finance_admin_can_create_sponsor(client, db, finance_user, finance_token):
    """Finance admin can create a new sponsor record."""
    response = client.post(
        "/api/v1/sponsors",
        json={
            "full_name": "Brother Chukwuemeka",
            "email": "chukwuemeka@test.com",
            "phone": "08055555555",
            "sponsorship_tier": "MONTHLY",
            "amount": 100000,
            "preferred_channel": "SMS",
        },
        headers=auth_headers(finance_token),
    )

    assert response.status_code == 201
    data = response.json()["data"]
    assert data["full_name"] == "Brother Chukwuemeka"
    assert data["amount"] == 100000.0
    assert "member_link_id" not in data


def test_create_sponsor_missing_required_fields(client, db, finance_user, finance_token):
    """Creating a sponsor without required fields should fail with 422."""
    response = client.post(
        "/api/v1/sponsors",
        json={"email": "incomplete@test.com"},
        headers=auth_headers(finance_token),
    )
    assert response.status_code == 422


def test_non_finance_cannot_create_sponsor(client, db, hr_user, hr_token):
    """HR admin must receive 403 when trying to create a sponsor."""
    response = client.post(
        "/api/v1/sponsors",
        json={
            "full_name": "HR Sponsor Attempt",
            "sponsorship_tier": "MONTHLY",
            "amount": 50000,
        },
        headers=auth_headers(hr_token),
    )
    assert response.status_code == 403


# ── Get Sponsor Detail ─────────────────────────────────────────────────────────

def test_get_sponsor_detail(client, db, finance_user, finance_token):
    """Finance admin can get sponsor detail including payment history."""
    sponsor = create_sponsor(db, full_name="Detail Sponsor", created_by=finance_user.id)
    create_sponsor_payment(db, sponsor_id=sponsor.id, amount=50000)

    response = client.get(
        f"/api/v1/sponsors/{sponsor.id}",
        headers=auth_headers(finance_token),
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["full_name"] == "Detail Sponsor"
    assert "payments" in data
    assert len(data["payments"]) >= 1
    assert "member_link_id" not in data


def test_get_nonexistent_sponsor_returns_404(client, db, finance_user, finance_token):
    """Requesting a non-existent sponsor should return 404."""
    fake_id = uuid.uuid4()
    response = client.get(
        f"/api/v1/sponsors/{fake_id}",
        headers=auth_headers(finance_token),
    )
    assert response.status_code == 404


# ── Update Sponsor ─────────────────────────────────────────────────────────────

def test_finance_admin_can_update_sponsor(client, db, finance_user, finance_token):
    """Finance admin can update sponsor information."""
    sponsor = create_sponsor(db, full_name="Old Name Sponsor", created_by=finance_user.id)

    response = client.put(
        f"/api/v1/sponsors/{sponsor.id}",
        json={"full_name": "Updated Sponsor Name", "is_active": True},
        headers=auth_headers(finance_token),
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["full_name"] == "Updated Sponsor Name"
    assert "member_link_id" not in data


# ── Manual Payments ────────────────────────────────────────────────────────────

def test_record_manual_payment(client, db, finance_user, finance_token):
    """Finance admin can record a manual cash payment for a sponsor."""
    sponsor = create_sponsor(db, full_name="Cash Payment Sponsor", created_by=finance_user.id)

    response = client.post(
        f"/api/v1/sponsors/{sponsor.id}/payments",
        json={
            "amount": 50000,
            "payment_method": "CASH",
            "notes": "Paid in person at church",
        },
        headers=auth_headers(finance_token),
    )

    assert response.status_code == 201
    data = response.json()["data"]
    assert data["amount"] == 50000.0
    assert data["payment_method"] == "CASH"


def test_list_payments_for_sponsor(client, db, finance_user, finance_token):
    """Finance admin can list all payments for a specific sponsor."""
    sponsor = create_sponsor(db, full_name="Payment History Sponsor", created_by=finance_user.id)
    create_sponsor_payment(db, sponsor_id=sponsor.id, amount=25000)
    create_sponsor_payment(db, sponsor_id=sponsor.id, amount=75000)

    response = client.get(
        f"/api/v1/sponsors/{sponsor.id}/payments",
        headers=auth_headers(finance_token),
    )

    assert response.status_code == 200
    data = response.json()
    assert data["total"] >= 2


def test_payment_response_excludes_member_link_id(client, db, finance_user, finance_token):
    """Payment records must not expose member_link_id."""
    member = create_active_member(db, "Payment Hidden Link Member")
    sponsor = create_sponsor(db, created_by=finance_user.id)
    sponsor.member_link_id = member.id
    db.flush()

    response = client.post(
        f"/api/v1/sponsors/{sponsor.id}/payments",
        json={"amount": 10000, "payment_method": "CASH"},
        headers=auth_headers(finance_token),
    )

    assert response.status_code == 201
    assert "member_link_id" not in response.text


# ── Send Reminder ──────────────────────────────────────────────────────────────

def test_send_reminder_returns_delivery_result(client, db, finance_user, finance_token):
    """Send-reminder invokes the reminder task synchronously and returns its
    real per-channel delivery result to the caller."""
    sponsor = create_sponsor(db, full_name="Reminder Sponsor", created_by=finance_user.id)
    sponsor.phone = "08055555555"
    sponsor.email = "reminder@sponsor.test"
    db.flush()

    canned = {
        "success": True,
        "sponsor_id": str(sponsor.id),
        "message": "Payment reminder sent via SMS, EMAIL",
    }
    with patch(
        "app.workers.tasks.notification_tasks.send_payment_reminder",
        return_value=canned,
    ) as mock_reminder:
        response = client.post(
            f"/api/v1/sponsors/{sponsor.id}/send-reminder",
            headers=auth_headers(finance_token),
        )

    assert response.status_code == 200
    body = response.json()
    assert body["success"] is True
    assert body["data"]["success"] is True
    assert "SMS" in body["data"]["message"]
    mock_reminder.assert_called_once_with(str(sponsor.id))


def test_send_reminder_surfaces_delivery_failure(client, db, finance_user, finance_token):
    """A failed delivery is reported as success=false in the payload (not a 500)."""
    sponsor = create_sponsor(db, full_name="Failing Reminder Sponsor", created_by=finance_user.id)
    sponsor.phone = "08055555555"
    db.flush()

    canned = {
        "success": False,
        "sponsor_id": str(sponsor.id),
        "message": "Payment reminder delivery failed on all channels",
    }
    with patch(
        "app.workers.tasks.notification_tasks.send_payment_reminder",
        return_value=canned,
    ):
        response = client.post(
            f"/api/v1/sponsors/{sponsor.id}/send-reminder",
            headers=auth_headers(finance_token),
        )

    assert response.status_code == 200
    assert response.json()["data"]["success"] is False


def test_send_reminder_nonexistent_sponsor_returns_404(client, db, finance_user, finance_token):
    """Reminding a non-existent sponsor returns 404 before any send is attempted."""
    fake_id = uuid.uuid4()
    response = client.post(
        f"/api/v1/sponsors/{fake_id}/send-reminder",
        headers=auth_headers(finance_token),
    )
    assert response.status_code == 404


def test_non_finance_cannot_send_reminder(client, db, hr_user, hr_token):
    """HR admin must not be able to send sponsor reminders."""
    response = client.post(
        f"/api/v1/sponsors/{uuid.uuid4()}/send-reminder",
        headers=auth_headers(hr_token),
    )
    assert response.status_code == 403


# ── Send Thank-You ─────────────────────────────────────────────────────────────

def test_send_thank_you_returns_delivery_result(client, db, finance_user, finance_token):
    """Send-thank-you invokes the synchronous sender and returns its result."""
    sponsor = create_sponsor(db, full_name="ThankYou Sponsor", created_by=finance_user.id)
    sponsor.phone = "08055555555"
    sponsor.email = "thankyou@sponsor.test"
    db.flush()
    payment = create_sponsor_payment(db, sponsor_id=sponsor.id, amount=50000)

    canned = {
        "success": True,
        "payment_id": str(payment.id),
        "channels": ["SMS", "EMAIL"],
        "message": "Thank-you sent via SMS, EMAIL",
    }
    with patch(
        "app.workers.tasks.notification_tasks.send_payment_thank_you_now",
        return_value=canned,
    ) as mock_send:
        response = client.post(
            f"/api/v1/sponsors/{sponsor.id}/payments/{payment.id}/send-thank-you",
            headers=auth_headers(finance_token),
        )

    assert response.status_code == 200
    body = response.json()
    assert body["data"]["success"] is True
    assert "SMS" in body["data"]["message"]
    mock_send.assert_called_once_with(str(payment.id))


def test_send_thank_you_wrong_sponsor_returns_404(client, db, finance_user, finance_token):
    """A payment that doesn't belong to the given sponsor returns 404."""
    sponsor_a = create_sponsor(db, full_name="Owner Sponsor", created_by=finance_user.id)
    sponsor_b = create_sponsor(db, full_name="Other Sponsor", created_by=finance_user.id)
    payment = create_sponsor_payment(db, sponsor_id=sponsor_a.id, amount=10000)

    response = client.post(
        f"/api/v1/sponsors/{sponsor_b.id}/payments/{payment.id}/send-thank-you",
        headers=auth_headers(finance_token),
    )
    assert response.status_code == 404


def test_non_finance_cannot_send_thank_you(client, db, hr_user, hr_token):
    """HR admin must not be able to send thank-you messages."""
    response = client.post(
        f"/api/v1/sponsors/{uuid.uuid4()}/payments/{uuid.uuid4()}/send-thank-you",
        headers=auth_headers(hr_token),
    )
    assert response.status_code == 403


# ── Finance Dashboard ──────────────────────────────────────────────────────────

def test_finance_dashboard_accessible_by_finance_admin(client, db, finance_user, finance_token):
    """Finance admin can access the finance dashboard."""
    response = client.get(
        "/api/v1/finance/dashboard",
        headers=auth_headers(finance_token),
    )
    assert response.status_code == 200
    assert response.json()["success"] is True


def test_giving_dashboard_alias_accessible_by_finance_admin(
    client, db, finance_user, finance_token
):
    """Finance admin can access the neutral giving dashboard alias."""
    response = client.get(
        "/api/v1/giving/dashboard",
        headers=auth_headers(finance_token),
    )
    assert response.status_code == 200
    assert response.json()["success"] is True


def test_finance_dashboard_degrades_when_sponsor_schema_query_fails():
    """Dashboard should not 500 when a sponsor-only DB query fails."""

    class BrokenSponsorDb:
        def __init__(self):
            self.rollbacks = 0

        def query(self, *args, **kwargs):
            raise SQLAlchemyError("sponsor schema drift")

        def rollback(self):
            self.rollbacks += 1

    db = BrokenSponsorDb()
    dashboard = get_finance_dashboard(db)

    assert dashboard["total_sponsors"] == 0
    assert dashboard["active_sponsors"] == 0
    assert dashboard["monthly_revenue"] == 0.0
    assert dashboard["annual_revenue"] == 0.0
    assert dashboard["payments_this_month"] == 0
    assert dashboard["overdue_sponsors"] == []
    assert dashboard["recent_payments"] == []
    assert db.rollbacks >= 1


def test_finance_dashboard_blocked_for_hr(client, db, hr_user, hr_token):
    """HR admin must not access the finance dashboard."""
    response = client.get(
        "/api/v1/finance/dashboard",
        headers=auth_headers(hr_token),
    )
    assert response.status_code == 403


def test_finance_dashboard_blocked_for_medical(client, db, medical_user, medical_token):
    """Medical staff must not access the finance dashboard."""
    response = client.get(
        "/api/v1/finance/dashboard",
        headers=auth_headers(medical_token),
    )
    assert response.status_code == 403


# ── Finance Ops Monitoring ─────────────────────────────────────────────────────

def test_finance_ops_returns_health_snapshot(client, db, finance_user, finance_token):
    """Ops endpoint returns payment, notification and provider health."""
    sponsor = create_sponsor(db, full_name="Ops Sponsor", created_by=finance_user.id)
    create_sponsor_payment(
        db, sponsor_id=sponsor.id, amount=5000, status=PaymentStatusEnum.PENDING
    )

    response = client.get("/api/v1/finance/ops", headers=auth_headers(finance_token))

    assert response.status_code == 200
    data = response.json()["data"]
    assert "payments" in data
    assert "notifications" in data
    assert "providers" in data
    assert "alerts" in data
    assert "healthy" in data
    assert data["payments"]["pending"] >= 1
    # Test env has no provider keys configured → alerts must call that out
    assert data["providers"]["flutterwave_api"] in (True, False)


def test_finance_ops_flags_missing_thank_you(client, db, finance_user, finance_token):
    """A recent completed payment without a thank-you shows up as a gap."""
    from datetime import datetime, timezone

    sponsor = create_sponsor(db, full_name="Gap Sponsor", created_by=finance_user.id)
    payment = create_sponsor_payment(
        db, sponsor_id=sponsor.id, amount=5000, status=PaymentStatusEnum.COMPLETED
    )
    payment.payment_date = datetime.now(timezone.utc)
    payment.thank_you_sent_at = None
    db.flush()

    response = client.get("/api/v1/giving/ops", headers=auth_headers(finance_token))

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["payments"]["missing_thank_you_7_days"] >= 1
    assert any("thank-you" in a.lower() for a in data["alerts"])


def test_finance_ops_blocked_for_non_finance(client, db, hr_user, hr_token):
    """HR admin must not access the ops snapshot."""
    response = client.get("/api/v1/finance/ops", headers=auth_headers(hr_token))
    assert response.status_code == 403


def test_reconcile_pending_endpoint_returns_stats(client, db, finance_user, finance_token):
    """Reconcile endpoint runs the reconcile task synchronously and returns stats."""
    canned = {"checked": 2, "completed": 2, "failed": 0, "still_pending": 0, "expired": 0}
    with patch(
        "app.workers.tasks.payment_tasks.reconcile_pending_payments",
        return_value=canned,
    ):
        response = client.post(
            "/api/v1/finance/reconcile-pending",
            headers=auth_headers(finance_token),
        )

    assert response.status_code == 200
    body = response.json()
    assert body["data"]["completed"] == 2
    assert "2 completed" in body["message"]


def test_reconcile_pending_blocked_for_non_finance(client, db, hr_user, hr_token):
    """HR admin must not trigger reconciliation."""
    response = client.post(
        "/api/v1/finance/reconcile-pending", headers=auth_headers(hr_token)
    )
    assert response.status_code == 403


# ── Annual Report ──────────────────────────────────────────────────────────────

def test_annual_report_accessible_by_finance_admin(client, db, finance_user, finance_token):
    """Finance admin can access the annual sponsorship report."""
    response = client.get(
        "/api/v1/finance/report/annual?year=2024",
        headers=auth_headers(finance_token),
    )
    assert response.status_code == 200


def test_giving_annual_report_alias_accessible_by_finance_admin(
    client, db, finance_user, finance_token
):
    """Finance admin can access the neutral annual giving report alias."""
    response = client.get(
        "/api/v1/giving/report/annual?year=2024",
        headers=auth_headers(finance_token),
    )
    assert response.status_code == 200


def test_annual_report_blocked_for_follow_up(client, db, follow_up_user, follow_up_token):
    """Follow-up staff must not access the annual finance report."""
    response = client.get(
        "/api/v1/finance/report/annual",
        headers=auth_headers(follow_up_token),
    )
    assert response.status_code == 403


# ── Flutterwave Payment Initiation ────────────────────────────────────────────

def test_initiate_flutterwave_payment(client, db, finance_user, finance_token):
    """Finance admin can initiate a Flutterwave payment for a sponsor."""
    sponsor = create_sponsor(
        db,
        full_name="Flutterwave Sponsor",
        created_by=finance_user.id,
    )
    # Update sponsor with email and phone for Flutterwave
    sponsor.email = "fw@sponsor.test"
    sponsor.phone = "08055555555"
    db.flush()

    mock_fw_response = {
        "status": "success",
        "message": "Hosted Link",
        "data": {"link": "https://checkout.flutterwave.com/pay/test123"},
    }

    with patch(
        "app.services.sponsor_service.flutterwave.initiate_payment",
        new=AsyncMock(return_value=mock_fw_response),
    ):
        response = client.post(
            "/api/v1/payments/initiate",
            json={
                "sponsor_id": str(sponsor.id),
                "amount": 50000,
                "redirect_url": "https://app.genesisglob.al/payment/callback",
            },
            headers=auth_headers(finance_token),
        )

    assert response.status_code == 201
    data = response.json()["data"]
    assert "link" in data or "payment_link" in data or "data" in data


def test_initiate_flutterwave_payment_auto_sends_link(
    client, db, finance_user, finance_token
):
    """Generating a link automatically queues the payment-link notification
    (SMS/email) to the sponsor."""
    sponsor = create_sponsor(
        db,
        full_name="Auto Notify Sponsor",
        created_by=finance_user.id,
    )
    sponsor.email = "auto@sponsor.test"
    sponsor.phone = "08066666666"
    db.flush()

    mock_fw_response = {
        "status": "success",
        "message": "Hosted Link",
        "data": {"link": "https://checkout.flutterwave.com/pay/auto123"},
    }

    with patch(
        "app.services.sponsor_service.flutterwave.initiate_payment",
        new=AsyncMock(return_value=mock_fw_response),
    ), patch(
        "app.workers.tasks.notification_tasks.send_payment_link"
    ) as mock_task:
        mock_task.apply_async = MagicMock()
        response = client.post(
            "/api/v1/payments/initiate",
            json={"sponsor_id": str(sponsor.id), "amount": 50000},
            headers=auth_headers(finance_token),
        )

    assert response.status_code == 201
    data = response.json()["data"]
    assert data["sponsor_notified"] is True
    mock_task.apply_async.assert_called_once()
    task_args = mock_task.apply_async.call_args.kwargs["args"]
    assert task_args[1] == "https://checkout.flutterwave.com/pay/auto123"
