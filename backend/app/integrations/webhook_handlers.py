"""
Genesis Global CMS — Webhook Processing Handlers

Contains the business logic for processing incoming webhook payloads.
These functions are called by Celery tasks so that webhook endpoints
return 200 immediately and processing happens asynchronously.
"""
import logging
import uuid
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy.orm import Session

from app.integrations.flutterwave import flutterwave
from app.models.sponsor import Sponsor, SponsorPayment, PaymentStatusEnum

logger = logging.getLogger(__name__)


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
      1. Validate event type is "charge.completed"
      2. Validate status is "successful"
      3. Extract sponsor_id from tx_ref (format: "genesis-{sponsor_id}-{suffix}")
      4. Load sponsor from database
      5. Locate pending SponsorPayment with matching tx_ref
      6. Update payment: status=COMPLETED, flutterwave_tx_id, payment_date
      7. Calculate and update next_due_date on sponsor
      8. Queue thank-you notification to sponsor
      9. Queue notification to finance admin

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
    flutterwave_tx_id: Optional[str] = str(data.get("id", ""))
    amount: float = float(data.get("amount", 0))
    currency: str = data.get("currency", "NGN")

    if not tx_ref:
        logger.error("Flutterwave webhook: missing tx_ref in payload")
        return

    # Extract sponsor_id from tx_ref format: "genesis-{sponsor_id}-{suffix}"
    parts = tx_ref.split("-")
    # Format: genesis-{uuid4-part1}-{uuid4-part2}-...-{suffix}
    # The sponsor_id is a UUID which has 5 parts; tx_ref is genesis + 5 UUID parts + suffix
    # So parts[1:6] form the UUID, remainder is our suffix
    sponsor_id_str: Optional[str] = None
    try:
        if len(parts) >= 7 and parts[0] == "genesis":
            # Reconstruct UUID: parts[1]-parts[2]-parts[3]-parts[4]-parts[5]
            sponsor_id_str = "-".join(parts[1:6])
            uuid.UUID(sponsor_id_str)  # validate
        else:
            logger.error(
                "Flutterwave webhook: could not parse sponsor_id from tx_ref='%s'", tx_ref
            )
            return
    except (ValueError, IndexError):
        logger.error(
            "Flutterwave webhook: invalid UUID in tx_ref='%s'", tx_ref
        )
        return

    # Load sponsor from database
    try:
        sponsor_uuid = uuid.UUID(sponsor_id_str)
    except ValueError:
        logger.error("Flutterwave webhook: invalid sponsor UUID '%s'", sponsor_id_str)
        return

    sponsor: Optional[Sponsor] = (
        db.query(Sponsor)
        .filter(Sponsor.id == sponsor_uuid, Sponsor.deleted_at.is_(None))
        .first()
    )
    if not sponsor:
        logger.error(
            "Flutterwave webhook: sponsor not found for id=%s (tx_ref=%s)",
            sponsor_id_str,
            tx_ref,
        )
        return

    # Find the pending SponsorPayment
    payment: Optional[SponsorPayment] = (
        db.query(SponsorPayment)
        .filter(SponsorPayment.tx_ref == tx_ref)
        .first()
    )

    if payment is None:
        # Create a new payment record if somehow not pre-created
        logger.warning(
            "Flutterwave webhook: no pending payment found for tx_ref=%s; creating one", tx_ref
        )
        payment = SponsorPayment(
            sponsor_id=sponsor.id,
            tx_ref=tx_ref,
            amount=amount,
            currency=currency,
            status=PaymentStatusEnum.PENDING,
        )
        db.add(payment)

    # Update payment to COMPLETED
    payment.status = PaymentStatusEnum.COMPLETED
    payment.flutterwave_tx_id = flutterwave_tx_id
    payment.payment_date = datetime.now(timezone.utc)
    payment.flutterwave_response = data
    payment.amount = amount
    payment.currency = currency

    # Calculate and update next due date on sponsor
    from datetime import date as date_type
    next_due = flutterwave.calculate_next_due_date(
        sponsor.sponsorship_tier.value, date_type.today()
    )
    sponsor.next_due_date = next_due

    db.flush()

    logger.info(
        "Flutterwave webhook: payment completed — sponsor=%s tx_ref=%s amount=%s next_due=%s",
        sponsor_id_str,
        tx_ref,
        amount,
        next_due,
    )

    # Queue thank-you notification (deferred import to avoid circular)
    try:
        from app.workers.tasks.notification_tasks import send_payment_thank_you
        send_payment_thank_you.delay(str(payment.id))
    except Exception as exc:
        logger.error(
            "Flutterwave webhook: failed to queue thank-you task for payment=%s: %s",
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
                f"A sponsorship payment of {currency} {amount:,.2f} has been received.\n"
                f"Sponsor: {sponsor.full_name}\n"
                f"Transaction Reference: {tx_ref}\n"
                f"Flutterwave TX ID: {flutterwave_tx_id}\n"
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

    # Look up local payment first
    payment: Optional[SponsorPayment] = (
        db.query(SponsorPayment)
        .filter(SponsorPayment.tx_ref == tx_ref)
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
                payment.status = PaymentStatusEnum.COMPLETED
                payment.flutterwave_tx_id = fw_tx_id
                payment.payment_date = datetime.now(timezone.utc)
                payment.flutterwave_response = tx_data
                payment.amount = fw_amount
                payment.currency = fw_currency

                # Update sponsor next_due_date
                sponsor: Optional[Sponsor] = (
                    db.query(Sponsor)
                    .filter(Sponsor.id == payment.sponsor_id)
                    .first()
                )
                if sponsor:
                    from datetime import date as date_type
                    next_due = flutterwave.calculate_next_due_date(
                        sponsor.sponsorship_tier.value, date_type.today()
                    )
                    sponsor.next_due_date = next_due

                db.flush()

                # Queue thank-you notification
                try:
                    from app.workers.tasks.notification_tasks import send_payment_thank_you
                    send_payment_thank_you.delay(str(payment.id))
                except Exception as exc:
                    logger.error("Failed to queue thank-you after verify: %s", str(exc))

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
