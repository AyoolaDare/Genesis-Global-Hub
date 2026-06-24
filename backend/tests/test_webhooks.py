"""
Genesis Global CMS — Flutterwave Webhook Tests

Covers:
1.  Valid HMAC-SHA256 signature → webhook accepted (200)
2.  Invalid/missing signature → webhook rejected (400)
3.  Valid signature but empty/malformed body → 200 (Flutterwave should not be punished)
4.  charge.completed event with valid payload → accepted
5.  Unknown event type → accepted gracefully
6.  Payment verification endpoint (GET /verify/{tx_ref})
7.  Very short tx_ref → 400
"""
import hashlib
import hmac
import json
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from tests.conftest import auth_headers


# ── HMAC Signature Helper ──────────────────────────────────────────────────────

def _make_signature(body: bytes, secret: str) -> str:
    """Generate a valid HMAC-SHA256 hex signature for a payload."""
    return hmac.new(secret.encode("utf-8"), body, hashlib.sha256).hexdigest()


def _webhook_payload(event: str = "charge.completed", tx_ref: str = "genesis-test-uuid-1234") -> dict:
    return {
        "event": event,
        "data": {
            "tx_ref": tx_ref,
            "amount": 50000,
            "currency": "NGN",
            "status": "successful",
            "id": 12345,
        },
    }


# ── Valid Signature Tests ──────────────────────────────────────────────────────

def test_valid_signature_webhook_accepted(client):
    """Webhook with correct HMAC-SHA256 signature must be accepted (200)."""
    payload = _webhook_payload()
    body = json.dumps(payload).encode()

    # The test uses an empty FLUTTERWAVE_SECRET_KEY by default
    # We patch the verify method to return True for a clean test
    with patch(
        "app.integrations.flutterwave.FlutterwaveClient.verify_webhook_signature",
        return_value=True,
    ), patch(
        "app.workers.tasks.payment_tasks.process_webhook_payment"
    ) as mock_task:
        mock_task.delay = MagicMock()
        response = client.post(
            "/api/v1/webhooks/flutterwave",
            content=body,
            headers={
                "verif-hash": "valid-signature-value",
                "Content-Type": "application/json",
            },
        )

    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert data["message"] == "Webhook received"


def test_invalid_signature_webhook_rejected(client):
    """Webhook with wrong signature must be rejected with 400."""
    payload = _webhook_payload()
    body = json.dumps(payload).encode()

    with patch(
        "app.integrations.flutterwave.FlutterwaveClient.verify_webhook_signature",
        return_value=False,
    ):
        response = client.post(
            "/api/v1/webhooks/flutterwave",
            content=body,
            headers={
                "verif-hash": "wrong-signature-value",
                "Content-Type": "application/json",
            },
        )

    assert response.status_code == 400


def test_missing_signature_header_rejected(client):
    """Webhook without verif-hash header must be rejected."""
    payload = _webhook_payload()
    body = json.dumps(payload).encode()

    with patch(
        "app.integrations.flutterwave.FlutterwaveClient.verify_webhook_signature",
        return_value=False,  # empty string signature → fails
    ):
        response = client.post(
            "/api/v1/webhooks/flutterwave",
            content=body,
            headers={"Content-Type": "application/json"},
            # No verif-hash header
        )

    assert response.status_code == 400


# ── Payload Variations ─────────────────────────────────────────────────────────

def test_charge_completed_event_queued(client):
    """charge.completed event should be queued to Celery."""
    payload = _webhook_payload("charge.completed", "genesis-sponsor-abc123")
    body = json.dumps(payload).encode()

    with patch(
        "app.integrations.flutterwave.FlutterwaveClient.verify_webhook_signature",
        return_value=True,
    ), patch(
        "app.workers.tasks.payment_tasks.process_webhook_payment"
    ) as mock_task:
        mock_task.delay = MagicMock()

        response = client.post(
            "/api/v1/webhooks/flutterwave",
            content=body,
            headers={"verif-hash": "valid", "Content-Type": "application/json"},
        )

        assert response.status_code == 200
        # Celery task should have been queued
        mock_task.delay.assert_called_once_with(payload)


def test_unknown_event_type_still_returns_200(client):
    """Unknown Flutterwave events should be accepted gracefully (200)."""
    payload = _webhook_payload("transfer.completed", "genesis-test-999")
    body = json.dumps(payload).encode()

    with patch(
        "app.integrations.flutterwave.FlutterwaveClient.verify_webhook_signature",
        return_value=True,
    ), patch(
        "app.workers.tasks.payment_tasks.process_webhook_payment"
    ) as mock_task:
        mock_task.delay = MagicMock()

        response = client.post(
            "/api/v1/webhooks/flutterwave",
            content=body,
            headers={"verif-hash": "valid", "Content-Type": "application/json"},
        )

    assert response.status_code == 200


def test_malformed_json_body_returns_200(client):
    """
    Malformed JSON body with valid signature should still return 200.
    Flutterwave should not be penalized for edge-case parsing errors.
    """
    body = b"this is not valid json {"

    with patch(
        "app.integrations.flutterwave.FlutterwaveClient.verify_webhook_signature",
        return_value=True,
    ):
        response = client.post(
            "/api/v1/webhooks/flutterwave",
            content=body,
            headers={"verif-hash": "valid", "Content-Type": "application/json"},
        )

    # Should still return 200 (we log the error but don't return a non-200 to FW)
    assert response.status_code == 200


def test_empty_body_with_valid_signature(client):
    """Empty body with valid signature should still return 200."""
    body = b"{}"

    with patch(
        "app.integrations.flutterwave.FlutterwaveClient.verify_webhook_signature",
        return_value=True,
    ), patch(
        "app.workers.tasks.payment_tasks.process_webhook_payment"
    ) as mock_task:
        mock_task.delay = MagicMock()

        response = client.post(
            "/api/v1/webhooks/flutterwave",
            content=body,
            headers={"verif-hash": "valid", "Content-Type": "application/json"},
        )

    assert response.status_code == 200


# ── Real HMAC Verification Unit Test ──────────────────────────────────────────

def test_flutterwave_verify_webhook_signature_correct_secret():
    """Unit test the HMAC signature verification function directly."""
    from app.integrations.flutterwave import FlutterwaveClient

    client_instance = FlutterwaveClient()
    secret = "test-webhook-secret-key"
    body = b'{"event":"charge.completed","data":{"tx_ref":"test-ref"}}'

    # Generate the correct signature
    expected_sig = hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()

    with patch("app.integrations.flutterwave.settings") as mock_settings:
        mock_settings.FLUTTERWAVE_SECRET_KEY = secret
        result = client_instance.verify_webhook_signature(body, expected_sig)

    assert result is True


def test_flutterwave_verify_webhook_signature_wrong_secret():
    """Signature generated with a different secret must return False."""
    from app.integrations.flutterwave import FlutterwaveClient

    client_instance = FlutterwaveClient()
    secret = "actual-secret-key"
    wrong_secret = "wrong-secret-key"
    body = b'{"event":"charge.completed"}'

    wrong_sig = hmac.new(wrong_secret.encode(), body, hashlib.sha256).hexdigest()

    with patch("app.integrations.flutterwave.settings") as mock_settings:
        mock_settings.FLUTTERWAVE_SECRET_KEY = secret
        result = client_instance.verify_webhook_signature(body, wrong_sig)

    assert result is False


def test_flutterwave_verify_empty_signature_returns_false():
    """Empty signature string must return False."""
    from app.integrations.flutterwave import FlutterwaveClient

    client_instance = FlutterwaveClient()
    body = b'{"event":"charge.completed"}'

    with patch("app.integrations.flutterwave.settings") as mock_settings:
        mock_settings.FLUTTERWAVE_SECRET_KEY = "some-secret"
        result = client_instance.verify_webhook_signature(body, "")

    assert result is False


# ── Payment Verification Endpoint ─────────────────────────────────────────────

def test_verify_payment_with_valid_tx_ref(client):
    """GET /webhooks/flutterwave/verify/{tx_ref} with valid tx_ref should return 200."""
    mock_result = {"status": "successful", "tx_ref": "genesis-test-ref-123", "amount": 50000}

    with patch(
        "app.integrations.webhook_handlers.handle_payment_verification",
        new=AsyncMock(return_value=mock_result),
    ):
        response = client.post(
            "/api/v1/webhooks/flutterwave/verify/genesis-test-ref-12345678",
        )

    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True


def test_verify_payment_with_too_short_tx_ref(client):
    """GET /webhooks/flutterwave/verify with a very short tx_ref must return 400."""
    response = client.post("/api/v1/webhooks/flutterwave/verify/abc")
    assert response.status_code == 400


def test_verify_payment_pending_status(client):
    """Pending payment status should return 200 with appropriate message."""
    mock_result = {"status": "pending", "tx_ref": "genesis-pending-ref", "amount": 50000}

    with patch(
        "app.integrations.webhook_handlers.handle_payment_verification",
        new=AsyncMock(return_value=mock_result),
    ):
        response = client.post(
            "/api/v1/webhooks/flutterwave/verify/genesis-pending-ref-12345",
        )

    assert response.status_code == 200
    assert "pending" in response.json()["message"].lower()


def test_verify_payment_failed_status(client):
    """Failed payment status should return 200 with appropriate message."""
    mock_result = {"status": "failed", "tx_ref": "genesis-failed-ref", "amount": 50000}

    with patch(
        "app.integrations.webhook_handlers.handle_payment_verification",
        new=AsyncMock(return_value=mock_result),
    ):
        response = client.post(
            "/api/v1/webhooks/flutterwave/verify/genesis-failed-ref-12345",
        )

    assert response.status_code == 200
    assert "not successful" in response.json()["message"].lower() or "failed" in response.json()["message"].lower()


# ── Flutterwave Client Utilities ───────────────────────────────────────────────

def test_build_tx_ref_format():
    """tx_ref must follow genesis-{sponsor_id}-{uuid} format."""
    from app.integrations.flutterwave import FlutterwaveClient

    client_instance = FlutterwaveClient()
    sponsor_id = str("test-sponsor-uuid")
    tx_ref = client_instance.build_tx_ref(sponsor_id)

    assert tx_ref.startswith(f"genesis-{sponsor_id}-")
    # The suffix should be 12 hex characters
    suffix = tx_ref.split("-")[-1]
    assert len(suffix) == 12


def test_calculate_next_due_date_monthly():
    """Monthly tier should add 1 month to reference date."""
    from app.integrations.flutterwave import FlutterwaveClient
    from datetime import date

    client_instance = FlutterwaveClient()
    from_date = date(2024, 1, 15)
    next_date = client_instance.calculate_next_due_date("MONTHLY", from_date)

    assert next_date == date(2024, 2, 15)


def test_calculate_next_due_date_quarterly():
    """Quarterly tier should add 3 months."""
    from app.integrations.flutterwave import FlutterwaveClient
    from datetime import date

    client_instance = FlutterwaveClient()
    from_date = date(2024, 1, 1)
    next_date = client_instance.calculate_next_due_date("QUARTERLY", from_date)

    assert next_date == date(2024, 4, 1)


def test_calculate_next_due_date_annual():
    """Annual tier should add 1 year."""
    from app.integrations.flutterwave import FlutterwaveClient
    from datetime import date

    client_instance = FlutterwaveClient()
    from_date = date(2024, 3, 10)
    next_date = client_instance.calculate_next_due_date("ANNUAL", from_date)

    assert next_date == date(2025, 3, 10)


def test_calculate_next_due_date_one_time_returns_none():
    """ONE_TIME tier should return None."""
    from app.integrations.flutterwave import FlutterwaveClient
    from datetime import date

    client_instance = FlutterwaveClient()
    result = client_instance.calculate_next_due_date("ONE_TIME", date.today())

    assert result is None
