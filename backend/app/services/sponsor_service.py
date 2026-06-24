"""
Genesis Global CMS — Sponsor Service (ISOLATED DOMAIN)

CRITICAL:
  - NEVER return member_link_id in any response
  - Only FINANCE_ADMIN/SUPER_ADMIN can access this domain
"""
import uuid
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import func, or_, extract
from sqlalchemy.orm import Session

from app.auth.models import AppUser
from app.core.exceptions import NotFound
from app.integrations.flutterwave import FlutterwaveClient
from app.models.sponsor import PaymentStatusEnum, Sponsor, SponsorPayment
from app.models.member import MemberModel
from app.schemas.sponsor import SponsorCreate, SponsorPaymentCreate, SponsorUpdate
from app.services.dedup_service import normalize_phone
from app.services.notification_service import queue_notification

flutterwave = FlutterwaveClient()


# ── Sponsor Service ────────────────────────────────────────────────────────────

def list_sponsors(
    db: Session,
    page: int = 1,
    per_page: int = 20,
    search: Optional[str] = None,
    is_active: Optional[bool] = None,
) -> tuple[list[Sponsor], int]:
    query = db.query(Sponsor).filter(Sponsor.deleted_at.is_(None))

    if search:
        s = f"%{search}%"
        query = query.filter(
            or_(
                Sponsor.full_name.ilike(s),
                Sponsor.phone.ilike(s),
                Sponsor.email.ilike(s),
            )
        )

    if is_active is not None:
        query = query.filter(Sponsor.is_active == is_active)

    query = query.order_by(Sponsor.full_name)
    total = query.count()
    items = query.offset((page - 1) * per_page).limit(per_page).all()
    return items, total


def get_sponsor(sponsor_id: uuid.UUID, db: Session) -> Sponsor:
    sponsor = db.query(Sponsor).filter(
        Sponsor.id == sponsor_id, Sponsor.deleted_at.is_(None)
    ).first()
    if not sponsor:
        raise NotFound(message=f"Sponsor {sponsor_id} not found.")
    return sponsor


def _find_member_link(full_name: str, phone: Optional[str], db: Session) -> Optional[uuid.UUID]:
    """Silently link sponsor to a member by phone number match."""
    if not phone:
        return None
    norm_phone = normalize_phone(phone)
    if not norm_phone:
        return None
    member = db.query(MemberModel).filter(
        MemberModel.deleted_at.is_(None),
        MemberModel.phone == norm_phone,
    ).first()
    return member.id if member else None


def create_sponsor(
    data: SponsorCreate,
    current_user: AppUser,
    db: Session,
) -> Sponsor:
    member_link_id = _find_member_link(data.full_name, data.phone, db)

    sponsor = Sponsor(
        full_name=data.full_name,
        phone=data.phone,
        email=str(data.email).lower() if data.email else None,
        sponsorship_tier=data.sponsorship_tier,
        amount=data.amount,
        preferred_channel=data.preferred_channel,
        member_link_id=member_link_id,  # backend-only, never returned
        is_active=data.is_active,
        created_by=current_user.id,
    )
    db.add(sponsor)
    db.flush()
    return sponsor


def update_sponsor(
    sponsor: Sponsor,
    data: SponsorUpdate,
    db: Session,
) -> Sponsor:
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(sponsor, field, value)
    db.flush()
    return sponsor


# ── Payment Service ────────────────────────────────────────────────────────────

def record_payment(
    sponsor: Sponsor,
    data: SponsorPaymentCreate,
    current_user: AppUser,
    db: Session,
) -> SponsorPayment:
    """Record a manual payment (not via Flutterwave)."""
    payment = SponsorPayment(
        sponsor_id=sponsor.id,
        amount=data.amount,
        payment_date=data.payment_date or datetime.now(timezone.utc),
        payment_method=data.payment_method,
        status=PaymentStatusEnum.COMPLETED,
        verified_by=current_user.id,
        verified_at=datetime.now(timezone.utc),
        notes=data.notes,
        next_due_date=data.next_due_date,
    )
    db.add(payment)
    db.flush()

    # Queue thank-you notification
    if sponsor.phone or sponsor.email:
        channel = sponsor.preferred_channel or "SMS"
        queue_notification(
            db=db,
            recipient_type="SPONSOR",
            recipient_id=sponsor.id,
            channel=channel,
            template_key="PAYMENT_THANK_YOU",
            payload={
                "sponsor_name": sponsor.full_name,
                "amount": float(data.amount),
                "payment_date": (data.payment_date or datetime.now(timezone.utc)).isoformat(),
            },
        )

    return payment


def list_payments(
    sponsor_id: uuid.UUID,
    db: Session,
    page: int = 1,
    per_page: int = 20,
) -> tuple[list[SponsorPayment], int]:
    query = db.query(SponsorPayment).filter(
        SponsorPayment.sponsor_id == sponsor_id,
        SponsorPayment.deleted_at.is_(None),
    ).order_by(SponsorPayment.payment_date.desc())

    total = query.count()
    items = query.offset((page - 1) * per_page).limit(per_page).all()
    return items, total


# ── Flutterwave Integration ────────────────────────────────────────────────────

def initiate_flutterwave_payment(
    sponsor_id: uuid.UUID,
    amount: float,
    redirect_url: Optional[str],
    db: Session,
) -> dict:
    """
    Create a pending payment record and return a Flutterwave payment link.

    In production, this would call the Flutterwave API.
    Returns a mock response for now.
    """
    sponsor = get_sponsor(sponsor_id, db)

    # Generate a unique transaction reference
    tx_ref = f"GEN-GLOBAL-{sponsor_id}-{int(datetime.now(timezone.utc).timestamp())}"

    # Create pending payment record
    payment = SponsorPayment(
        sponsor_id=sponsor_id,
        amount=amount,
        payment_method="FLUTTERWAVE",
        status=PaymentStatusEnum.PENDING,
        flutterwave_tx_ref=tx_ref,
    )
    db.add(payment)
    db.flush()

    # In production: call Flutterwave API here
    payment_link = f"https://checkout.flutterwave.com/v3/hosted/pay/{tx_ref}"

    return {
        "tx_ref": tx_ref,
        "payment_link": payment_link,
        "amount": amount,
        "sponsor_name": sponsor.full_name,
    }


def verify_flutterwave_payment(
    tx_ref: str,
    current_user: AppUser,
    db: Session,
) -> SponsorPayment:
    """
    Verify a Flutterwave payment by tx_ref.
    In production, this would call the Flutterwave verification API.
    """
    payment = db.query(SponsorPayment).filter(
        SponsorPayment.flutterwave_tx_ref == tx_ref,
        SponsorPayment.deleted_at.is_(None),
    ).first()
    if not payment:
        raise NotFound(message=f"Payment with ref '{tx_ref}' not found.")

    # In production: verify with Flutterwave API
    # For now, mark as completed
    if payment.status == PaymentStatusEnum.PENDING:
        payment.status = PaymentStatusEnum.COMPLETED
        payment.payment_date = datetime.now(timezone.utc)
        payment.verified_by = current_user.id
        payment.verified_at = datetime.now(timezone.utc)
        db.flush()

        # Queue thank-you
        sponsor = get_sponsor(payment.sponsor_id, db)
        if sponsor.phone or sponsor.email:
            channel = sponsor.preferred_channel or "SMS"
            queue_notification(
                db=db,
                recipient_type="SPONSOR",
                recipient_id=sponsor.id,
                channel=channel,
                template_key="PAYMENT_THANK_YOU",
                payload={
                    "sponsor_name": sponsor.full_name,
                    "amount": float(payment.amount),
                    "tx_ref": tx_ref,
                },
            )

    return payment


# ── Finance Dashboard ──────────────────────────────────────────────────────────

def get_finance_dashboard(db: Session) -> dict:
    """Compute finance dashboard metrics."""
    now = datetime.now(timezone.utc)
    month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    year_start = now.replace(month=1, day=1, hour=0, minute=0, second=0, microsecond=0)

    total_sponsors = db.query(func.count(Sponsor.id)).filter(
        Sponsor.deleted_at.is_(None)
    ).scalar() or 0

    active_sponsors = db.query(func.count(Sponsor.id)).filter(
        Sponsor.deleted_at.is_(None),
        Sponsor.is_active.is_(True),
    ).scalar() or 0

    monthly_revenue = db.query(func.coalesce(func.sum(SponsorPayment.amount), 0)).filter(
        SponsorPayment.deleted_at.is_(None),
        SponsorPayment.status == PaymentStatusEnum.COMPLETED,
        SponsorPayment.payment_date >= month_start,
    ).scalar() or 0.0

    annual_revenue = db.query(func.coalesce(func.sum(SponsorPayment.amount), 0)).filter(
        SponsorPayment.deleted_at.is_(None),
        SponsorPayment.status == PaymentStatusEnum.COMPLETED,
        SponsorPayment.payment_date >= year_start,
    ).scalar() or 0.0

    payments_this_month = db.query(func.count(SponsorPayment.id)).filter(
        SponsorPayment.deleted_at.is_(None),
        SponsorPayment.status == PaymentStatusEnum.COMPLETED,
        SponsorPayment.payment_date >= month_start,
    ).scalar() or 0

    # Overdue sponsors (next_due_date is past and not yet paid)
    overdue = (
        db.query(Sponsor, SponsorPayment)
        .outerjoin(
            SponsorPayment,
            (SponsorPayment.sponsor_id == Sponsor.id)
            & (SponsorPayment.status == PaymentStatusEnum.COMPLETED)
            & (SponsorPayment.deleted_at.is_(None)),
        )
        .filter(
            Sponsor.deleted_at.is_(None),
            Sponsor.is_active.is_(True),
            SponsorPayment.next_due_date.isnot(None),
            SponsorPayment.next_due_date < now.date(),
        )
        .order_by(SponsorPayment.next_due_date.asc())
        .limit(20)
        .all()
    )

    overdue_list = []
    for sponsor, payment in overdue:
        overdue_list.append({
            "id": sponsor.id,
            "full_name": sponsor.full_name,
            "phone": sponsor.phone,
            "sponsorship_tier": sponsor.sponsorship_tier,
            "amount": float(sponsor.amount),
            "last_payment_date": payment.payment_date if payment else None,
            "next_due_date": payment.next_due_date if payment else None,
        })

    return {
        "total_sponsors": total_sponsors,
        "active_sponsors": active_sponsors,
        "monthly_revenue": float(monthly_revenue),
        "annual_revenue": float(annual_revenue),
        "payments_this_month": payments_this_month,
        "overdue_sponsors": overdue_list,
    }


def get_annual_report(year: int, db: Session) -> dict:
    """Build annual sponsorship report broken down by month and tier."""
    year_start = datetime(year, 1, 1)
    year_end = datetime(year + 1, 1, 1)

    # Monthly breakdown
    monthly_data = (
        db.query(
            extract("month", SponsorPayment.payment_date).label("month"),
            func.count(SponsorPayment.id).label("total_payments"),
            func.coalesce(func.sum(SponsorPayment.amount), 0).label("total_amount"),
        )
        .filter(
            SponsorPayment.deleted_at.is_(None),
            SponsorPayment.status == PaymentStatusEnum.COMPLETED,
            SponsorPayment.payment_date >= year_start,
            SponsorPayment.payment_date < year_end,
        )
        .group_by(extract("month", SponsorPayment.payment_date))
        .order_by(extract("month", SponsorPayment.payment_date))
        .all()
    )

    month_names = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]

    by_month = [
        {
            "month": month_names[int(row.month) - 1],
            "total_payments": row.total_payments,
            "total_amount": float(row.total_amount),
        }
        for row in monthly_data
    ]

    # By tier
    tier_data = (
        db.query(
            Sponsor.sponsorship_tier,
            func.count(SponsorPayment.id).label("total_payments"),
            func.coalesce(func.sum(SponsorPayment.amount), 0).label("total_amount"),
        )
        .join(SponsorPayment, SponsorPayment.sponsor_id == Sponsor.id)
        .filter(
            Sponsor.deleted_at.is_(None),
            SponsorPayment.deleted_at.is_(None),
            SponsorPayment.status == PaymentStatusEnum.COMPLETED,
            SponsorPayment.payment_date >= year_start,
            SponsorPayment.payment_date < year_end,
        )
        .group_by(Sponsor.sponsorship_tier)
        .all()
    )

    by_tier = {
        str(row.sponsorship_tier): {
            "total_payments": row.total_payments,
            "total_amount": float(row.total_amount),
        }
        for row in tier_data
    }

    total_annual_revenue = sum(m["total_amount"] for m in by_month)
    total_payments = sum(m["total_payments"] for m in by_month)

    return {
        "year": year,
        "total_annual_revenue": total_annual_revenue,
        "total_payments": total_payments,
        "by_month": by_month,
        "by_tier": by_tier,
    }
