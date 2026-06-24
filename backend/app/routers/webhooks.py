"""
Genesis Global CMS — Webhook Endpoints

Handles inbound webhooks from Flutterwave and provides a payment
verification endpoint for the frontend to call after redirect.

Security:
  - HMAC-SHA256 signature verification on all Flutterwave webhooks
  - Invalid signatures return 400 immediately (no processing)
  - Valid webhooks are queued to Celery and return 200 without waiting
    (Flutterwave retries on any non-200 response, so we must always
    return 200 after signature validation)

Endpoints:
  POST /api/v1/webhooks/flutterwave         — Flutterwave payment events
  POST /api/v1/webhooks/flutterwave/verify/{tx_ref} — Frontend verification after redirect
"""
import logging

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session

from app.core.responses import success_response, error_response
from app.database import get_db
from app.integrations.flutterwave import flutterwave
from app.integrations import webhook_handlers

logger = logging.getLogger(__name__)

router = APIRouter(
    prefix="/api/v1/webhooks",
    tags=["webhooks"],
)


@router.post("/flutterwave", summary="Receive Flutterwave payment webhook events")
async def flutterwave_webhook(
    request: Request,
    db: Session = Depends(get_db),
):
    """
    Receive and process Flutterwave payment webhook events.

    Security:
      The raw request body is HMAC-SHA256 signed by Flutterwave using
      your FLUTTERWAVE_SECRET_KEY. We verify the signature before
      doing anything else. Invalid signatures are rejected with 400.

    Processing:
      Webhook processing is async (queued to Celery). This endpoint
      always returns 200 after signature validation — even if processing
      encounters an error internally — so that Flutterwave does not
      retry unnecessarily.

    Supported events:
      - charge.completed (payment received)
      - Other events are logged and ignored gracefully.

    Headers expected:
      verif-hash: HMAC-SHA256 hex digest of the request body

    Returns:
        200 {"success": true, "message": "Webhook received"}
        400 {"success": false, ...} on invalid signature
    """
    # Read raw body for signature verification (must be done before .json())
    body: bytes = await request.body()

    # Get Flutterwave signature from header
    signature: str = request.headers.get("verif-hash", "")

    # Verify HMAC signature — reject immediately if invalid
    if not flutterwave.verify_webhook_signature(body, signature):
        logger.warning(
            "Flutterwave webhook: invalid signature from IP=%s",
            request.client.host if request.client else "unknown",
        )
        raise HTTPException(
            status_code=400,
            detail=error_response(
                code="INVALID_SIGNATURE",
                message="Webhook signature verification failed.",
            ),
        )

    # Parse JSON payload
    try:
        payload: dict = await request.json()
    except Exception as parse_exc:
        logger.error("Flutterwave webhook: failed to parse JSON body: %s", str(parse_exc))
        # Return 200 anyway — malformed payload is not Flutterwave's fault
        return success_response(message="Webhook received (unparseable body logged)")

    event: str = payload.get("event", "unknown")
    tx_ref: str = payload.get("data", {}).get("tx_ref", "unknown")

    logger.info(
        "Flutterwave webhook received: event=%s tx_ref=%s",
        event,
        tx_ref,
    )

    # Queue processing asynchronously via Celery — do NOT block here
    # This keeps the HTTP response fast and ensures Flutterwave always
    # receives a 200 for valid signature webhooks.
    try:
        from app.workers.tasks.payment_tasks import process_webhook_payment
        process_webhook_payment.delay(payload)
    except Exception as queue_exc:
        # Log the error but still return 200 to Flutterwave
        # The webhook will NOT be retried, so log comprehensively
        logger.error(
            "Flutterwave webhook: failed to queue Celery task for event=%s tx_ref=%s: %s",
            event,
            tx_ref,
            str(queue_exc),
            exc_info=True,
        )

    return success_response(
        message="Webhook received",
        data={"event": event, "tx_ref": tx_ref},
    )


@router.post(
    "/flutterwave/verify/{tx_ref}",
    summary="Verify Flutterwave payment after redirect",
)
async def verify_payment(
    tx_ref: str,
    db: Session = Depends(get_db),
):
    """
    Verify a payment after the user returns from the Flutterwave payment page.

    The Flutter/web frontend calls this endpoint with the tx_ref that was
    included in the redirect_url. This endpoint:
      1. Queries the Flutterwave API for the transaction matching tx_ref
      2. Updates the local SponsorPayment record if status changed
      3. Returns the current payment status to the frontend

    Args:
        tx_ref: The transaction reference from the Flutterwave redirect URL.

    Returns:
        200 with payment status details on success.
        200 with status="error" if verification service is unavailable
            (frontend should show "please wait" and retry).
    """
    if not tx_ref or len(tx_ref) < 5:
        raise HTTPException(
            status_code=400,
            detail=error_response(
                code="INVALID_TX_REF",
                message="Transaction reference is required and must be valid.",
            ),
        )

    logger.info("Payment verification requested: tx_ref=%s", tx_ref)

    result = await webhook_handlers.handle_payment_verification(tx_ref=tx_ref, db=db)

    status = result.get("status", "unknown")

    if status == "successful":
        message = "Payment verified successfully."
    elif status == "failed":
        message = "Payment was not successful. Please try again or contact support."
    elif status == "pending":
        message = "Payment is pending. Please check back shortly."
    elif status == "not_found":
        message = "Transaction not found. Please ensure the reference is correct."
    elif status == "error":
        message = "Verification service temporarily unavailable. Please try again."
    else:
        message = result.get("message", "Payment status retrieved.")

    return success_response(
        data=result,
        message=message,
    )
