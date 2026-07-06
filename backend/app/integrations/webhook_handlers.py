"""
Genesis Global CMS — Webhook Processing Handlers

Contains the business logic for processing incoming webhook payloads.
These functions are called by Celery tasks so that webhook endpoints
return 200 immediately and processing happens asynchronously.
"""
import logging
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy.orm import Session

from app.integrations.flutterwave import flutterwave
from app.models.sponsor import Sponsor, SponsorPayment, PaymentStatusEnum

logger = logging.getLogger(__name__)


async def _send_thank_you_inline(db: Session, payment, sponsor) -> None:
    """
    Deliver the payment thank-you (SMS/WhatsApp + email) immediately from within
    the webhook request, so it never depends on a running Celery worker.

    Stamps thank_you_sent_at when at least one channel succeeds and is
    idempotent (skips if already stamped). Best-effort per channel: a single
    channel failure is logged but never aborts the others or the webhook.
    """
    from app.integrations.termii import termii

    # Idempotency: Flutterwave re-delivers webhooks; never thank twice.
    if payment.thank_you_sent_at is not None:
        return

    if not sponsor.phone and not sponsor.email:
        logger.warning(
            "Flutterwave webhook: sponsor=%s has no phone/email — thank-you skipped",
            sponsor.id,
        )
        return

    first_name = sponsor.full_name.split()[0] if sponsor.full_name else "Friend"
    amount_str = f"{float(payment.amount):,.0f}"
    preferred = (
        sponsor.preferred_channel.value.lower()
        if sponsor.preferred_channel
        else "sms"
    )
    sent = False

    if sponsor.email:
        try:
            from app.integrations.brevo import BrevoClient
            html_body = (
                f"<p>Dear {sponsor.full_name},</p>"
                f"<p>Thank you for your generous contribution of "
                f"<strong>&#8358;{amount_str}</strong> to Genesis Global. "
                f"Your support makes a real difference. God bless you!</p>"
                f"<p>The Genesis Global Finance Team</p>"
            )
            if BrevoClient().send_email(
                to_email=sponsor.email,
                subject="Thank You for Your Generosity — Genesis Global",
                html_content=html_body,
            ):
                sent = True
        except Exception as email_exc:
            logger.error(
                "Flutterwave webhook: inline thank-you email error for sponsor=%s: %s",
                sponsor.id,
                str(email_exc),
            )

    if sponsor.phone:
        phone_channel = "whatsapp" if preferred == "whatsapp" else "generic"
        try:
            await termii.send_templated_message(
                to=sponsor.phone,
                template_key="payment_thank_you",
                template_vars={"name": first_name, "amount": amount_str},
                channel=phone_channel,
            )
            sent = True
        except Exception as sms_exc:
            logger.error(
                "Flutterwave webhook: inline thank-you SMS error for sponsor=%s: %s",
                sponsor.id,
                str(sms_exc),
            )

    if sent:
        payment.thank_you_sent_at = datetime.now(timezone.utc)
        db.flush()
        logger.info(
            "Flutterwave webhook: inline thank-you delivered for payment=%s", payment.id
        )


async def handle_flutterwave_payment(payload: dict, db: Session) -> None:
    """
    Process an incoming Flutterwave webhook payload.

    Expected payload structure (charge.completed event):
    {
      "event": "charge.completed",
      "data": {
        "id": 12345,
        "tx_ref": "genesis-{sponsor_id}-{uuid}",
        "amount": 50000,
        "currency": "NGN",
        "status": "successful",
        "customer": {
          "email": "...",
          "phone_number": "...",
          "name": "..."
        },
        "created_at": "2024-01-01T00:00:00.000Z"
      }
    }

    Steps:
      1. Validate event type is "charge.completed" and status is "successful"
      2. Locate the pending SponsorPayment by tx_ref (created at initiation)
      3. Idempotency guard: already-COMPLETED payments are skipped entirely
      4. RE-VERIFY the transaction with Flutterwave's API (never trust the
         webhook payload's amount/status alone)
      5. Compare verified amount/currency against the expected payment
      6. Update payment: status=COMPLETED, flutterwave_tx_id, payment_date,
         next_due_date
      7. Queue thank-you notification to sponsor
      8. Queue notification to finance admin

    Args:
        payload: Parsed JSON webhook payload dict.
        db:      Active SQLAlchemy session.
    """
    event = payload.get("event", "")
    data = payload.get("data", {})

    if event != "charge.completed":
        logger.info("Flutterwave webhook: ignoring event type '%s'", event)
        return

    payment_status = data.get("status", "")
    if payment_status != "successful":
        logger.info(
            "Flutterwave webhook: payment not successful (status=%s tx_ref=%s)",
            payment_status,
            data.get("tx_ref"),
        )
        return

    tx_ref: Optional[str] = data.get("tx_ref")
    webhook_tx_id: Optional[str] = str(data.get("id", ""))

    if not tx_ref:
        logger.error("Flutterwave webhook: missing tx_ref in payload")
        return

    # Locate the pending SponsorPayment created at initiation time.
    # We deliberately do NOT create payment records for unknown tx_refs —
    # an attacker-supplied reference must never mint revenue rows.
    # Row lock (FOR UPDATE; no-op on SQLite): webhook, redirect-verify and the
    # reconcile job can all process the same tx_ref concurrently at scale —
    # the lock serialises them so a payment is never credited or thanked twice.
    payment: Optional[SponsorPayment] = (
        db.query(SponsorPayment)
        .filter(SponsorPayment.tx_ref == tx_ref, SponsorPayment.deleted_at.is_(None))
        .with_for_update()
        .first()
    )
    if payment is None:
        logger.error(
            "Flutterwave webhook: no local payment record for tx_ref=%s — ignoring", tx_ref
        )
        return

    # Idempotency: Flutterwave retries webhooks; never credit or notify twice
    if payment.status == PaymentStatusEnum.COMPLETED:
        logger.info(
            "Flutterwave webhook: payment tx_ref=%s already COMPLETED — skipping", tx_ref
        )
        return

    sponsor: Optional[Sponsor] = (
        db.query(Sponsor)
        .filter(Sponsor.id == payment.sponsor_id, Sponsor.deleted_at.is_(None))
        .first()
    )
    if not sponsor:
        logger.error(
            "Flutterwave webhook: sponsor not found for payment tx_ref=%s", tx_ref
        )
        return

    # Re-verify with Flutterwave before crediting — the webhook body is not
    # proof of payment. GET /transactions/{id}/verify is the source of truth.
    try:
        verification = await flutterwave.verify_payment(webhook_tx_id)
    except Exception as exc:
        logger.error(
            "Flutterwave webhook: verification API call failed for tx_ref=%s: %s — "
            "raising so Celery retries",
            tx_ref,
            exc,
        )
        raise

    verified = verification.get("data") or {}
    verified_status = verified.get("status", "")
    verified_tx_ref = verified.get("tx_ref", "")
    verified_amount = float(verified.get("amount", 0))
    verified_currency = verified.get("currency", "")

    if verified_status != "successful" or verified_tx_ref != tx_ref:
        logger.warning(
            "Flutterwave webhook: verification mismatch tx_ref=%s (verified status=%s ref=%s)",
            tx_ref,
            verified_status,
            verified_tx_ref,
        )
        return

    expected_amount = float(payment.amount)
    if verified_amount + 0.01 < expected_amount or verified_currency != "NGN":
        payment.flutterwave_response = verified
        payment.notes = (
            f"AMOUNT MISMATCH: expected NGN {expected_amount:,.2f}, "
            f"Flutterwave confirmed {verified_currency} {verified_amount:,.2f}. "
            f"Manual review required."
        )
        db.flush()
        logger.warning(
            "Flutterwave webhook: amount/currency mismatch tx_ref=%s expected=%s got=%s %s",
            tx_ref,
            expected_amount,
            verified_currency,
            verified_amount,
        )
        return

    # Credit the payment
    payment.status = PaymentStatusEnum.COMPLETED
    payment.flutterwave_tx_id = webhook_tx_id
    payment.payment_date = datetime.now(timezone.utc)
    payment.flutterwave_response = verified
    payment.amount = verified_amount

    # Next due date lives on the payment record (sponsors table has no such column)
    from datetime import date as date_type
    next_due = flutterwave.calculate_next_due_date(
        sponsor.sponsorship_tier.value, date_type.today()
    )
    payment.next_due_date = next_due

    db.flush()

    logger.info(
        "Flutterwave webhook: payment completed — sponsor=%s tx_ref=%s amount=%s next_due=%s",
        sponsor.id,
        tx_ref,
        verified_amount,
        next_due,
    )

    # Send the thank-you INLINE (not via Celery) so it does not depend on a
    # running worker — the webhook request itself delivers it.
    try:
        await _send_thank_you_inline(db=db, payment=payment, sponsor=sponsor)
    except Exception as exc:
        logger.error(
            "Flutterwave webhook: inline thank-you failed for payment=%s: %s",
            payment.id,
            str(exc),
        )

    # Queue finance admin notification
    try:
        from app.workers.tasks.notification_tasks import send_admin_notification
        send_admin_notification.delay(
            admin_email=None,  # The task will look up the finance admin email
            subject=f"Sponsorship Payment Received — {sponsor.full_name}",
            message=(
                f"A sponsorship payment of {verified_currency} {verified_amount:,.2f} has been received.\n"
                f"Sponsor: {sponsor.full_name}\n"
                f"Transaction Reference: {tx_ref}\n"
                f"Flutterwave TX ID: {webhook_tx_id}\n"
                f"Next Due Date: {next_due}"
            ),
        )
    except Exception as exc:
        logger.error(
            "Flutterwave webhook: failed to queue admin notification for payment=%s: %s",
            payment.id,
            str(exc),
        )


async def handle_payment_verification(tx_ref: str, db: Session) -> dict:
    """
    Called from the /payments/verify endpoint after a user returns from Flutterwave.

    Verifies the transaction with the Flutterwave API and updates local records.

    Steps:
      1. Query Flutterwave API using tx_ref
      2. Check status
      3. Update local SponsorPayment record
      4. Return structured result for the API response

    Args:
        tx_ref: Our unique transaction reference string.
        db:     Active SQLAlchemy session.

    Returns:
        Dict with keys: status, tx_ref, amount, currency, payment_id, sponsor_id, message.
    """
    result: dict = {
        "status": "unknown",
        "tx_ref": tx_ref,
        "amount": None,
        "currency": None,
        "payment_id": None,
        "sponsor_id": None,
        "message": "",
    }

    # Look up local payment first.
    # Row lock (FOR UPDATE; no-op on SQLite) — serialises against the webhook
    # and reconcile paths so concurrent completion never double-credits.
    payment: Optional[SponsorPayment] = (
        db.query(SponsorPayment)
        .filter(SponsorPayment.tx_ref == tx_ref)
        .with_for_update()
        .first()
    )

    try:
        fw_response = await flutterwave.get_transaction_by_ref(tx_ref)
        transactions = fw_response.get("data", [])

        if not transactions:
            result["status"] = "not_found"
            result["message"] = "Transaction not found on Flutterwave"
            return result

        # Take the most recent matching transaction
        tx_data = transactions[0]
        fw_status = tx_data.get("status", "")
        fw_amount = float(tx_data.get("amount", 0))
        fw_currency = tx_data.get("currency", "NGN")
        fw_tx_id = str(tx_data.get("id", ""))

        result["status"] = fw_status
        result["amount"] = fw_amount
        result["currency"] = fw_currency

        if payment:
            result["payment_id"] = str(payment.id)
            result["sponsor_id"] = str(payment.sponsor_id)

            if fw_status == "successful" and payment.status != PaymentStatusEnum.COMPLETED:
                expected_amount = float(payment.amount)
                if fw_amount + 0.01 < expected_amount or fw_currency != "NGN":
                    payment.flutterwave_response = tx_data
                    payment.notes = (
                        f"AMOUNT MISMATCH: expected NGN {expected_amount:,.2f}, "
                        f"Flutterwave confirmed {fw_currency} {fw_amount:,.2f}. "
                        f"Manual review required."
                    )
                    db.flush()
                    result["status"] = "pending"
                    result["message"] = (
                        "Payment amount could not be confirmed. Our team will review it."
                    )
                    return result

                payment.status = PaymentStatusEnum.COMPLETED
                payment.flutterwave_tx_id = fw_tx_id
                payment.payment_date = datetime.now(timezone.utc)
                payment.flutterwave_response = tx_data
                payment.amount = fw_amount

                # Next due date lives on the payment record
                sponsor: Optional[Sponsor] = (
                    db.query(Sponsor)
                    .filter(Sponsor.id == payment.sponsor_id)
                    .first()
                )
                if sponsor:
                    from datetime import date as date_type
                    payment.next_due_date = flutterwave.calculate_next_due_date(
                        sponsor.sponsorship_tier.value, date_type.today()
                    )

                db.flush()

                # Send thank-you INLINE (no Celery dependency) so it works even
                # when no worker is running (e.g. reconcile / redirect verify).
                if sponsor:
                    try:
                        await _send_thank_you_inline(db=db, payment=payment, sponsor=sponsor)
                    except Exception as exc:
                        logger.error("Inline thank-you after verify failed: %s", str(exc))

                result["message"] = "Payment verified and recorded successfully"

            elif fw_status == "successful" and payment.status == PaymentStatusEnum.COMPLETED:
                result["message"] = "Payment was already recorded as completed"

            elif fw_status == "failed":
                payment.status = PaymentStatusEnum.FAILED
                payment.flutterwave_response = tx_data
                db.flush()
                result["message"] = "Payment failed on Flutterwave"

            else:
                result["message"] = f"Payment status: {fw_status}"
        else:
            result["message"] = "Payment reference not found in local records"
            logger.warning("Payment verify: tx_ref=%s not in local DB", tx_ref)

    except Exception as exc:
        logger.error(
            "handle_payment_verification error: tx_ref=%s error=%s", tx_ref, str(exc)
        )
        result["status"] = "error"
        result["message"] = "Verification service temporarily unavailable"

    return result
