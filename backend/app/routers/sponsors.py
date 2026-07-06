"""
Genesis Global CMS — Sponsors & Payments Router (ISOLATED DOMAIN)

CRITICAL: member_link_id is NEVER returned in any response.

Endpoints:
  GET    /sponsors                       List sponsors (FINANCE_ADMIN only)
  POST   /sponsors                       Create sponsor
  GET    /sponsors/{id}                  Get sponsor + payment history
  PUT    /sponsors/{id}                  Update sponsor

  POST   /sponsors/{id}/payments         Record manual payment
  GET    /sponsors/{id}/payments         Payment history

  POST   /payments/initiate              Initiate Flutterwave payment
  GET    /payments/verify/{tx_ref}       Verify payment

  GET    /finance/dashboard              Finance dashboard
  GET    /finance/report/annual          Annual report
"""
import uuid
from datetime import date, datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.auth.dependencies import require_role
from app.auth.models import AppUser
from app.core.exceptions import NotFound
from app.core.responses import paginated_response, success_response
from app.database import get_db
from app.models.sponsor import SponsorPayment
from app.schemas.sponsor import (
    FunnelConfigUpdate,
    InitiatePaymentRequest,
    SponsorCreate,
    SponsorPaymentCreate,
    SponsorUpdate,
)
from app.services.sponsor_service import (
    create_sponsor,
    get_annual_report,
    get_finance_dashboard,
    get_finance_ops,
    get_sponsor,
    initiate_flutterwave_payment,
    list_all_payments,
    list_payments,
    list_sponsors,
    record_payment,
    update_sponsor,
    verify_flutterwave_payment,
)

router = APIRouter(tags=["Sponsors & Finance"])

_FINANCE_ROLES = ("SUPER_ADMIN", "FINANCE_ADMIN")


def _serialize_sponsor(sponsor) -> dict:
    """Serialize sponsor WITHOUT member_link_id."""
    return {
        "id": sponsor.id,
        "full_name": sponsor.full_name,
        "phone": sponsor.phone,
        "email": sponsor.email,
        "sponsorship_tier": sponsor.sponsorship_tier,
        "amount": float(sponsor.amount),
        "preferred_channel": sponsor.preferred_channel,
        "is_active": sponsor.is_active,
        "created_by": sponsor.created_by,
        "created_at": sponsor.created_at,
        "updated_at": sponsor.updated_at,
        # member_link_id intentionally excluded
    }


def _serialize_payment(payment) -> dict:
    return {
        "id": payment.id,
        "sponsor_id": payment.sponsor_id,
        "sponsor_name": payment.sponsor.full_name if payment.sponsor else None,
        "amount": float(payment.amount),
        "payment_date": payment.payment_date,
        "payment_method": payment.payment_method,
        "status": payment.status,
        "tx_ref": payment.tx_ref,
        "verified_by": payment.verified_by,
        "verified_at": payment.verified_at,
        "notes": payment.notes,
        "next_due_date": payment.next_due_date,
        "reminder_sent_at": payment.reminder_sent_at,
        "thank_you_sent_at": payment.thank_you_sent_at,
        "created_at": payment.created_at,
        "updated_at": payment.updated_at,
    }


# ── Sponsors ───────────────────────────────────────────────────────────────────

@router.get("/giving/supporters", summary="List all supporters (Finance Admin only)")
@router.get("/sponsors", summary="List all sponsors (Finance Admin only)")
async def list_sponsors_endpoint(
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    search: Optional[str] = Query(None),
    is_active: Optional[bool] = Query(None),
    current_user: AppUser = Depends(require_role(*_FINANCE_ROLES)),
    db: Session = Depends(get_db),
):
    items, total = list_sponsors(db, page, per_page, search, is_active)
    data = [_serialize_sponsor(s) for s in items]
    return paginated_response(data=data, total=total, page=page, per_page=per_page)


@router.post("/giving/supporters", summary="Create a new supporter", status_code=201)
@router.post("/sponsors", summary="Create a new sponsor", status_code=201)
async def create_sponsor_endpoint(
    body: SponsorCreate,
    current_user: AppUser = Depends(require_role(*_FINANCE_ROLES)),
    db: Session = Depends(get_db),
):
    sponsor = create_sponsor(body, current_user, db)
    return success_response(data=_serialize_sponsor(sponsor), message="Sponsor created.")


@router.get("/giving/supporters/{sponsor_id}", summary="Get supporter with contribution history")
@router.get("/sponsors/{sponsor_id}", summary="Get sponsor with payment history")
async def get_sponsor_endpoint(
    sponsor_id: uuid.UUID,
    current_user: AppUser = Depends(require_role(*_FINANCE_ROLES)),
    db: Session = Depends(get_db),
):
    sponsor = get_sponsor(sponsor_id, db)
    payments, _ = list_payments(sponsor_id, db)
    data = _serialize_sponsor(sponsor)
    data["payments"] = [_serialize_payment(p) for p in payments]
    return success_response(data=data)


@router.put("/giving/supporters/{sponsor_id}", summary="Update supporter")
@router.put("/sponsors/{sponsor_id}", summary="Update sponsor")
async def update_sponsor_endpoint(
    sponsor_id: uuid.UUID,
    body: SponsorUpdate,
    current_user: AppUser = Depends(require_role(*_FINANCE_ROLES)),
    db: Session = Depends(get_db),
):
    sponsor = get_sponsor(sponsor_id, db)
    sponsor = update_sponsor(sponsor, body, db)
    return success_response(data=_serialize_sponsor(sponsor), message="Sponsor updated.")


# ── Payments ───────────────────────────────────────────────────────────────────

@router.post(
    "/giving/supporters/{sponsor_id}/contributions",
    summary="Record a manual contribution",
    status_code=201,
)
@router.post("/sponsors/{sponsor_id}/payments", summary="Record a manual payment", status_code=201)
async def record_payment_endpoint(
    sponsor_id: uuid.UUID,
    body: SponsorPaymentCreate,
    current_user: AppUser = Depends(require_role(*_FINANCE_ROLES)),
    db: Session = Depends(get_db),
):
    sponsor = get_sponsor(sponsor_id, db)
    payment = record_payment(sponsor, body, current_user, db)
    return success_response(data=_serialize_payment(payment), message="Payment recorded.")


@router.post(
    "/giving/supporters/{sponsor_id}/send-reminder",
    summary="Send a payment reminder to a supporter now",
)
@router.post("/sponsors/{sponsor_id}/send-reminder", summary="Send a payment reminder now")
def send_reminder_endpoint(
    sponsor_id: uuid.UUID,
    current_user: AppUser = Depends(require_role(*_FINANCE_ROLES)),
    db: Session = Depends(get_db),
):
    """
    Send a payment reminder to the sponsor immediately by SMS/WhatsApp and email.

    Unlike the automated overdue-reminder cron job, this runs SYNCHRONOUSLY and
    returns the REAL per-channel delivery result, so the finance admin gets
    truthful feedback ("sent via SMS, EMAIL" or the actual error) instead of a
    blind success toast. Because it is a direct call — not a Celery .delay() —
    it also works when no Celery worker/Redis is running, which makes it the
    right tool for verifying the SMS/email pipeline end to end.

    NOTE: This endpoint is deliberately a plain `def` (not `async def`) so it
    runs in FastAPI's threadpool, where the reminder task's internal
    `asyncio.run_until_complete` calls are free to spin up their own event loop.
    """
    # 404 if the sponsor doesn't exist or is soft-deleted.
    get_sponsor(sponsor_id, db)

    # Deferred import avoids a circular import at module load time.
    from app.workers.tasks.notification_tasks import send_payment_reminder

    # Invoke the task body directly (NOT .delay) so we can surface the actual
    # delivery outcome to the caller instead of a fire-and-forget queue id.
    result = send_payment_reminder(str(sponsor_id))

    return success_response(
        data=result,
        message=result.get("message") or "Reminder processed.",
    )


@router.post(
    "/giving/supporters/{sponsor_id}/contributions/{payment_id}/send-thank-you",
    summary="Send (or resend) the thank-you for a contribution now",
)
@router.post(
    "/sponsors/{sponsor_id}/payments/{payment_id}/send-thank-you",
    summary="Send (or resend) the payment thank-you now",
)
def send_thank_you_endpoint(
    sponsor_id: uuid.UUID,
    payment_id: uuid.UUID,
    current_user: AppUser = Depends(require_role(*_FINANCE_ROLES)),
    db: Session = Depends(get_db),
):
    """
    Send (or re-send) the thank-you message for a specific payment immediately
    by SMS/WhatsApp and email, and return the REAL per-channel delivery result.

    This is the manual counterpart to the automatic thank-you that fires when a
    Flutterwave payment is confirmed. Use it to verify the thank-you pipeline
    end to end, or to resend after the automatic one failed. Runs synchronously
    (plain `def`, threadpool) so the caller gets truthful, immediate feedback.
    """
    # Ensure the sponsor exists and the payment belongs to it (404 otherwise).
    get_sponsor(sponsor_id, db)
    payment = (
        db.query(SponsorPayment)
        .filter(
            SponsorPayment.id == payment_id,
            SponsorPayment.sponsor_id == sponsor_id,
            SponsorPayment.deleted_at.is_(None),
        )
        .first()
    )
    if not payment:
        raise NotFound(message=f"Payment {payment_id} not found for this sponsor.")

    # Deferred import avoids a circular import at module load time.
    from app.workers.tasks.notification_tasks import send_payment_thank_you_now

    result = send_payment_thank_you_now(str(payment_id))
    return success_response(
        data=result,
        message=result.get("message") or "Thank-you processed.",
    )


@router.get(
    "/giving/supporters/{sponsor_id}/contributions",
    summary="Contribution history for a supporter",
)
@router.get("/sponsors/{sponsor_id}/payments", summary="Payment history for a sponsor")
async def list_payments_endpoint(
    sponsor_id: uuid.UUID,
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    current_user: AppUser = Depends(require_role(*_FINANCE_ROLES)),
    db: Session = Depends(get_db),
):
    items, total = list_payments(sponsor_id, db, page, per_page)
    data = [_serialize_payment(p) for p in items]
    return paginated_response(data=data, total=total, page=page, per_page=per_page)


@router.get("/giving/contributions", summary="List supporter contributions")
@router.get("/payments", summary="List sponsor payments")
async def list_all_payments_endpoint(
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    status: Optional[str] = Query(None),
    method: Optional[str] = Query(None),
    from_date: Optional[date] = Query(None, alias="from"),
    to_date: Optional[date] = Query(None, alias="to"),
    current_user: AppUser = Depends(require_role(*_FINANCE_ROLES)),
    db: Session = Depends(get_db),
):
    items, total = list_all_payments(
        db=db,
        page=page,
        per_page=per_page,
        status=status,
        method=method,
        from_date=from_date,
        to_date=to_date,
    )
    data = [_serialize_payment(p) for p in items]
    return paginated_response(data=data, total=total, page=page, per_page=per_page)


@router.post(
    "/giving/contributions/initiate",
    summary="Initiate Flutterwave contribution",
    status_code=201,
)
@router.post("/payments/initiate", summary="Initiate Flutterwave payment", status_code=201)
async def initiate_payment_endpoint(
    body: InitiatePaymentRequest,
    current_user: AppUser = Depends(require_role(*_FINANCE_ROLES)),
    db: Session = Depends(get_db),
):
    result = await initiate_flutterwave_payment(body.sponsor_id, body.amount, body.redirect_url, db)
    return success_response(data=result, message="Payment initiated.")


@router.get("/giving/contributions/verify/{tx_ref}", summary="Verify Flutterwave contribution")
@router.get("/payments/verify/{tx_ref}", summary="Verify Flutterwave payment")
async def verify_payment_endpoint(
    tx_ref: str,
    current_user: AppUser = Depends(require_role(*_FINANCE_ROLES)),
    db: Session = Depends(get_db),
):
    payment = await verify_flutterwave_payment(tx_ref, current_user, db)
    return success_response(
        data=_serialize_payment(payment),
        message=f"Payment status: {payment.status}",
    )


# ── Finance Dashboard & Reports ────────────────────────────────────────────────

@router.get("/giving/dashboard", summary="Giving dashboard")
@router.get("/finance/dashboard", summary="Finance dashboard")
async def finance_dashboard_endpoint(
    current_user: AppUser = Depends(require_role(*_FINANCE_ROLES)),
    db: Session = Depends(get_db),
):
    dashboard = get_finance_dashboard(db)
    return success_response(data=dashboard)


@router.get("/giving/funnel", summary="Donor payment funnel (status × tenure)")
@router.get("/finance/funnel", summary="Donor payment funnel (status × tenure)")
async def donor_funnel_endpoint(
    current_user: AppUser = Depends(require_role(*_FINANCE_ROLES)),
    db: Session = Depends(get_db),
):
    """
    Donor tracking funnel: every active sponsor with their payment status
    (PAID / PENDING / OVERDUE), giving tenure, funnel reminder stage, payment
    consistency label, and a status × tenure summary matrix.
    """
    from app.services.funnel_service import get_donor_funnel

    return success_response(data=get_donor_funnel(db))


@router.get("/giving/funnel/config", summary="Get reminder funnel schedule")
@router.get("/finance/funnel/config", summary="Get reminder funnel schedule")
async def get_funnel_config_endpoint(
    current_user: AppUser = Depends(require_role(*_FINANCE_ROLES)),
    db: Session = Depends(get_db),
):
    """Current reminder funnel schedule (defaults merged in)."""
    from app.services.funnel_service import get_funnel_config

    return success_response(data=get_funnel_config(db))


@router.put("/giving/funnel/config", summary="Update reminder funnel schedule")
@router.put("/finance/funnel/config", summary="Update reminder funnel schedule")
async def update_funnel_config_endpoint(
    body: FunnelConfigUpdate,
    current_user: AppUser = Depends(require_role(*_FINANCE_ROLES)),
    db: Session = Depends(get_db),
):
    """
    Update the reminder funnel schedule. The daily funnel task re-reads this
    on every run, so changes take effect from the next run without a deploy.
    """
    from app.core.exceptions import ValidationError
    from app.services.funnel_service import update_funnel_config

    try:
        config = update_funnel_config(
            db, body.model_dump(exclude_none=True), current_user.id
        )
    except ValueError as exc:
        raise ValidationError(message=str(exc))
    return success_response(data=config, message="Funnel schedule updated.")


@router.get("/giving/ops", summary="Giving pipeline health snapshot")
@router.get("/finance/ops", summary="Finance pipeline health snapshot")
async def finance_ops_endpoint(
    current_user: AppUser = Depends(require_role(*_FINANCE_ROLES)),
    db: Session = Depends(get_db),
):
    """
    Operational monitoring for the finance pipeline: stuck pending payments,
    thank-you delivery gaps, notification queue backlog, provider credential
    health, and actionable alerts. Powers the System Health panel on the
    finance dashboard.
    """
    return success_response(data=get_finance_ops(db))


@router.post("/giving/reconcile-pending", summary="Reconcile pending contributions now")
@router.post("/finance/reconcile-pending", summary="Reconcile pending payments now")
def reconcile_pending_endpoint(
    current_user: AppUser = Depends(require_role(*_FINANCE_ROLES)),
    db: Session = Depends(get_db),
):
    """
    Re-check every PENDING Flutterwave payment against Flutterwave and credit
    the ones that actually succeeded — the same logic as the hourly reconcile
    cron, but on demand and SYNCHRONOUSLY (plain `def`, threadpool), so it needs
    no Celery worker. Use it to clear payments stuck as PENDING because a webhook
    was missed. Payments confirmed successful are completed and the thank-you is
    sent inline.

    Note: only payments at least ~15 minutes old are re-checked (younger ones
    may still be completing on Flutterwave's side).
    """
    from app.workers.tasks.payment_tasks import reconcile_pending_payments

    stats = reconcile_pending_payments()
    message = (
        f"Checked {stats.get('checked', 0)} pending payment(s): "
        f"{stats.get('completed', 0)} completed, "
        f"{stats.get('failed', 0)} failed, "
        f"{stats.get('still_pending', 0)} still pending, "
        f"{stats.get('expired', 0)} expired."
    )
    return success_response(data=stats, message=message)


@router.get("/giving/report/annual", summary="Annual giving report")
@router.get("/finance/report/annual", summary="Annual sponsorship report")
async def annual_report_endpoint(
    year: int = Query(datetime.now(timezone.utc).year, ge=2020, le=2100),
    current_user: AppUser = Depends(require_role(*_FINANCE_ROLES)),
    db: Session = Depends(get_db),
):
    report = get_annual_report(year, db)
    return success_response(data=report)
