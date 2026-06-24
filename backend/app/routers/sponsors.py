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
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.auth.dependencies import require_role
from app.auth.models import AppUser
from app.core.responses import paginated_response, success_response
from app.database import get_db
from app.schemas.sponsor import InitiatePaymentRequest, SponsorCreate, SponsorPaymentCreate, SponsorUpdate
from app.services.sponsor_service import (
    create_sponsor,
    get_annual_report,
    get_finance_dashboard,
    get_sponsor,
    initiate_flutterwave_payment,
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
        "amount": float(payment.amount),
        "payment_date": payment.payment_date,
        "payment_method": payment.payment_method,
        "status": payment.status,
        "flutterwave_tx_ref": payment.flutterwave_tx_ref,
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


@router.post("/sponsors", summary="Create a new sponsor", status_code=201)
async def create_sponsor_endpoint(
    body: SponsorCreate,
    current_user: AppUser = Depends(require_role(*_FINANCE_ROLES)),
    db: Session = Depends(get_db),
):
    sponsor = create_sponsor(body, current_user, db)
    return success_response(data=_serialize_sponsor(sponsor), message="Sponsor created.")


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


@router.post("/payments/initiate", summary="Initiate Flutterwave payment", status_code=201)
async def initiate_payment_endpoint(
    body: InitiatePaymentRequest,
    current_user: AppUser = Depends(require_role(*_FINANCE_ROLES)),
    db: Session = Depends(get_db),
):
    result = initiate_flutterwave_payment(body.sponsor_id, body.amount, body.redirect_url, db)
    return success_response(data=result, message="Payment initiated.")


@router.get("/payments/verify/{tx_ref}", summary="Verify Flutterwave payment")
async def verify_payment_endpoint(
    tx_ref: str,
    current_user: AppUser = Depends(require_role(*_FINANCE_ROLES)),
    db: Session = Depends(get_db),
):
    payment = verify_flutterwave_payment(tx_ref, current_user, db)
    return success_response(
        data=_serialize_payment(payment),
        message=f"Payment status: {payment.status}",
    )


# ── Finance Dashboard & Reports ────────────────────────────────────────────────

@router.get("/finance/dashboard", summary="Finance dashboard")
async def finance_dashboard_endpoint(
    current_user: AppUser = Depends(require_role(*_FINANCE_ROLES)),
    db: Session = Depends(get_db),
):
    dashboard = get_finance_dashboard(db)
    return success_response(data=dashboard)


@router.get("/finance/report/annual", summary="Annual sponsorship report")
async def annual_report_endpoint(
    year: int = Query(datetime.now(timezone.utc).year, ge=2020, le=2100),
    current_user: AppUser = Depends(require_role(*_FINANCE_ROLES)),
    db: Session = Depends(get_db),
):
    report = get_annual_report(year, db)
    return success_response(data=report)
