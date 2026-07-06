"""
Genesis Global CMS — Sponsor Service (ISOLATED DOMAIN)

CRITICAL:
  - NEVER return member_link_id in any response
  - Only FINANCE_ADMIN/SUPER_ADMIN can access this domain
"""
import logging
import uuid
from datetime import date, datetime, time, timezone
from typing import Optional

from sqlalchemy import func, or_, extract
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.auth.models import AppUser
from app.config import settings
from app.core.exceptions import NotFound, ServiceUnavailable
from app.integrations.flutterwave import FlutterwaveClient
from app.models.sponsor import (
    PaymentStatusEnum,
    PreferredChannelEnum,
    Sponsor,
    SponsorPayment,
)
from app.models.member import MemberModel
from app.schemas.sponsor import SponsorCreate, SponsorPaymentCreate, SponsorUpdate
from app.services.dedup_service import normalize_phone
from app.services.notification_service import queue_notification

logger = logging.getLogger(__name__)

flutterwave = FlutterwaveClient()


def _sponsor_phone_channel(sponsor: Sponsor) -> str:
    preferred = getattr(sponsor.preferred_channel, "value", sponsor.preferred_channel)
    return "WHATSAPP" if preferred == "WHATSAPP" else "SMS"


def _queue_sponsor_thank_you(
    db: Session,
    sponsor: Sponsor,
    amount: float,
    payment_date: Optional[datetime] = None,
    tx_ref: Optional[str] = None,
) -> int:
    """Queue thank-you messages for every available sponsor contact channel."""
    payload = {
        "sponsor_name": sponsor.full_name,
        "amount": float(amount),
        "payment_date": (payment_date or datetime.now(timezone.utc)).isoformat(),
    }
    if tx_ref:
        payload["tx_ref"] = tx_ref

    queued = 0
    if sponsor.phone:
        queue_notification(
            db=db,
            recipient_type="SPONSOR",
            recipient_id=sponsor.id,
            channel=_sponsor_phone_channel(sponsor),
            template_key="PAYMENT_THANK_YOU",
            payload={**payload, "phone": sponsor.phone},
        )
        queued += 1

    if sponsor.email:
        queue_notification(
            db=db,
            recipient_type="SPONSOR",
            recipient_id=sponsor.id,
            channel="EMAIL",
            template_key="PAYMENT_THANK_YOU",
            payload={**payload, "email": sponsor.email},
        )
        queued += 1

    return queued


def _rollback_after_dashboard_error(db: Session, section: str, exc: Exception) -> None:
    logger.exception("Finance dashboard section '%s' failed: %s", section, exc)
    try:
        db.rollback()
    except Exception:
        logger.exception("Finance dashboard rollback failed after '%s'", section)


def _safe_dashboard_scalar(
    db: Session,
    section: str,
    query_factory,
    default=0,
):
    try:
        return query_factory().scalar() or default
    except SQLAlchemyError as exc:
        _rollback_after_dashboard_error(db, section, exc)
        return default


def _safe_dashboard_rows(db: Session, section: str, query_factory) -> list:
    try:
        return query_factory().all()
    except SQLAlchemyError as exc:
        _rollback_after_dashboard_error(db, section, exc)
        return []


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
        preferred_channel=data.preferred_channel or PreferredChannelEnum.SMS,
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
    _queue_sponsor_thank_you(
        db=db,
        sponsor=sponsor,
        amount=float(data.amount),
        payment_date=data.payment_date or payment.payment_date,
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


def list_all_payments(
    db: Session,
    page: int = 1,
    per_page: int = 20,
    status: Optional[str] = None,
    method: Optional[str] = None,
    from_date: Optional[date] = None,
    to_date: Optional[date] = None,
) -> tuple[list[SponsorPayment], int]:
    query = (
        db.query(SponsorPayment)
        .join(Sponsor, Sponsor.id == SponsorPayment.sponsor_id)
        .filter(
            SponsorPayment.deleted_at.is_(None),
            Sponsor.deleted_at.is_(None),
        )
        .order_by(SponsorPayment.payment_date.desc().nulls_last())
    )

    if status:
        query = query.filter(SponsorPayment.status == status)

    if method:
        query = query.filter(SponsorPayment.payment_method == method)

    if from_date:
        query = query.filter(
            SponsorPayment.payment_date >= datetime.combine(from_date, time.min)
        )

    if to_date:
        query = query.filter(
            SponsorPayment.payment_date <= datetime.combine(to_date, time.max)
        )

    total = query.count()
    items = query.offset((page - 1) * per_page).limit(per_page).all()
    return items, total


# ── Flutterwave Integration ────────────────────────────────────────────────────

async def initiate_flutterwave_payment(
    sponsor_id: uuid.UUID,
    amount: float,
    redirect_url: Optional[str],
    db: Session,
    notify_sponsor: bool = True,
) -> dict:
    """
    Create a pending payment record and return a real Flutterwave payment link.

    Calls POST /payments on the Flutterwave API server-side; the secret key
    never leaves the backend. The pending SponsorPayment row is only kept if
    Flutterwave accepts the request.

    When notify_sponsor is True (the admin-initiated path), the link is also
    sent to the sponsor automatically by SMS/WhatsApp and email. Reminder
    jobs pass False because they embed the link in their own message.
    """
    sponsor = get_sponsor(sponsor_id, db)

    # Unique transaction reference: genesis-{sponsor_id}-{12-hex-suffix}.
    # Must match the format expected by the webhook handler.
    tx_ref = flutterwave.build_tx_ref(str(sponsor_id))

    if not redirect_url:
        base = (settings.FRONTEND_URL or "").rstrip("/")
        redirect_url = f"{base}/payment/complete" if base else "https://flutterwave.com"

    try:
        fw_response = await flutterwave.initiate_payment(
            tx_ref=tx_ref,
            amount=amount,
            redirect_url=redirect_url,
            customer_email=sponsor.email or "no-reply@genesisglob.al",
            customer_name=sponsor.full_name,
            customer_phone=sponsor.phone or "",
            currency="NGN",
            meta={"sponsor_id": str(sponsor_id)},
        )
    except Exception as exc:
        logger.error(
            "initiate_flutterwave_payment: Flutterwave call failed for sponsor=%s: %s",
            sponsor_id,
            exc,
        )
        raise ServiceUnavailable(
            message="Payment provider is temporarily unavailable. Please try again."
        )

    payment_link = (fw_response.get("data") or {}).get("link")
    if fw_response.get("status") != "success" or not payment_link:
        logger.error(
            "initiate_flutterwave_payment: unexpected Flutterwave response for sponsor=%s: %s",
            sponsor_id,
            fw_response.get("message"),
        )
        raise ServiceUnavailable(
            message="Payment provider rejected the request. Please try again."
        )

    # Only record the pending payment once Flutterwave has accepted it
    payment = SponsorPayment(
        sponsor_id=sponsor_id,
        amount=amount,
        payment_method="FLUTTERWAVE",
        status=PaymentStatusEnum.PENDING,
        tx_ref=tx_ref,
    )
    db.add(payment)
    db.flush()

    sponsor_notified = False
    if notify_sponsor and (sponsor.phone or sponsor.email):
        # Deferred import to avoid circular dependency; short countdown so
        # the worker sees the committed payment row before loading it.
        try:
            from app.workers.tasks.notification_tasks import send_payment_link
            send_payment_link.apply_async(
                args=[str(payment.id), payment_link], countdown=5
            )
            sponsor_notified = True
        except Exception as exc:
            logger.error(
                "initiate_flutterwave_payment: failed to queue payment-link "
                "notification for payment=%s: %s",
                payment.id,
                exc,
            )

    return {
        "tx_ref": tx_ref,
        "payment_link": payment_link,
        "amount": amount,
        "sponsor_name": sponsor.full_name,
        "sponsor_notified": sponsor_notified,
    }


async def verify_flutterwave_payment(
    tx_ref: str,
    current_user: AppUser,
    db: Session,
) -> SponsorPayment:
    """
    Verify a Flutterwave payment by tx_ref against the Flutterwave API.

    The payment is only marked COMPLETED when Flutterwave confirms the
    transaction is successful AND the paid amount/currency match what we
    expected. Idempotent: an already-completed payment is returned as-is.
    """
    # Row lock (FOR UPDATE; no-op on SQLite) — serialises against the webhook
    # and reconcile paths so concurrent completion never double-credits.
    payment = db.query(SponsorPayment).filter(
        SponsorPayment.tx_ref == tx_ref,
        SponsorPayment.deleted_at.is_(None),
    ).with_for_update().first()
    if not payment:
        raise NotFound(message=f"Payment with ref '{tx_ref}' not found.")

    if payment.status == PaymentStatusEnum.COMPLETED:
        return payment

    try:
        fw_response = await flutterwave.get_transaction_by_ref(tx_ref)
    except Exception as exc:
        logger.error("verify_flutterwave_payment: Flutterwave call failed for tx_ref=%s: %s", tx_ref, exc)
        raise ServiceUnavailable(
            message="Payment provider is temporarily unavailable. Please try again."
        )

    transactions = fw_response.get("data") or []
    if not transactions:
        # Nothing on Flutterwave's side yet — leave the record PENDING
        return payment

    tx_data = transactions[0]
    fw_status = tx_data.get("status", "")
    fw_amount = float(tx_data.get("amount", 0))
    fw_currency = tx_data.get("currency", "")
    fw_tx_id = str(tx_data.get("id", ""))
    now = datetime.now(timezone.utc)

    if fw_status == "successful":
        expected_amount = float(payment.amount)
        if fw_amount + 0.01 < expected_amount or fw_currency != "NGN":
            # Underpayment / wrong currency: keep PENDING for manual review
            payment.flutterwave_response = tx_data
            payment.notes = (
                f"AMOUNT MISMATCH: expected NGN {expected_amount:,.2f}, "
                f"Flutterwave confirmed {fw_currency} {fw_amount:,.2f}. Manual review required."
            )
            db.flush()
            logger.warning(
                "verify_flutterwave_payment: amount/currency mismatch tx_ref=%s expected=%s got=%s %s",
                tx_ref, expected_amount, fw_currency, fw_amount,
            )
            return payment

        payment.status = PaymentStatusEnum.COMPLETED
        payment.flutterwave_tx_id = fw_tx_id
        payment.flutterwave_response = tx_data
        payment.amount = fw_amount
        payment.payment_date = now
        payment.verified_by = current_user.id
        payment.verified_at = now

        # Next due date lives on the payment record (sponsor has no such column)
        sponsor = get_sponsor(payment.sponsor_id, db)
        payment.next_due_date = flutterwave.calculate_next_due_date(
            sponsor.sponsorship_tier.value, date.today()
        )
        db.flush()

        _queue_sponsor_thank_you(
            db=db,
            sponsor=sponsor,
            amount=float(payment.amount),
            payment_date=payment.payment_date,
            tx_ref=tx_ref,
        )

    elif fw_status == "failed":
        payment.status = PaymentStatusEnum.FAILED
        payment.flutterwave_response = tx_data
        db.flush()

    return payment


# ── Finance Dashboard ──────────────────────────────────────────────────────────

def get_finance_dashboard(db: Session) -> dict:
    """Compute finance dashboard metrics."""
    now = datetime.now(timezone.utc)
    month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    year_start = now.replace(month=1, day=1, hour=0, minute=0, second=0, microsecond=0)

    total_sponsors = _safe_dashboard_scalar(
        db,
        "total_sponsors",
        lambda: db.query(func.count(Sponsor.id)).filter(Sponsor.deleted_at.is_(None)),
        0,
    )

    active_sponsors = _safe_dashboard_scalar(
        db,
        "active_sponsors",
        lambda: db.query(func.count(Sponsor.id)).filter(
            Sponsor.deleted_at.is_(None),
            Sponsor.is_active.is_(True),
        ),
        0,
    )

    monthly_revenue = _safe_dashboard_scalar(
        db,
        "monthly_revenue",
        lambda: db.query(func.coalesce(func.sum(SponsorPayment.amount), 0)).filter(
            SponsorPayment.deleted_at.is_(None),
            SponsorPayment.status == PaymentStatusEnum.COMPLETED,
            SponsorPayment.payment_date >= month_start,
        ),
        0.0,
    )

    annual_revenue = _safe_dashboard_scalar(
        db,
        "annual_revenue",
        lambda: db.query(func.coalesce(func.sum(SponsorPayment.amount), 0)).filter(
            SponsorPayment.deleted_at.is_(None),
            SponsorPayment.status == PaymentStatusEnum.COMPLETED,
            SponsorPayment.payment_date >= year_start,
        ),
        0.0,
    )

    payments_this_month = _safe_dashboard_scalar(
        db,
        "payments_this_month",
        lambda: db.query(func.count(SponsorPayment.id)).filter(
            SponsorPayment.deleted_at.is_(None),
            SponsorPayment.status == PaymentStatusEnum.COMPLETED,
            SponsorPayment.payment_date >= month_start,
        ),
        0,
    )

    # Overdue sponsors (next_due_date is past and not yet paid)
    overdue = _safe_dashboard_rows(
        db,
        "overdue_sponsors",
        lambda: (
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
        ),
    )

    overdue_list = []
    try:
        for sponsor, payment in overdue:
            days_overdue = 0
            if payment and payment.next_due_date:
                days_overdue = (now.date() - payment.next_due_date).days
            overdue_list.append({
                "id": sponsor.id,
                "name": sponsor.full_name,
                "full_name": sponsor.full_name,
                "phone": sponsor.phone,
                "tier": getattr(sponsor.sponsorship_tier, "value", sponsor.sponsorship_tier),
                "sponsorship_tier": getattr(
                    sponsor.sponsorship_tier, "value", sponsor.sponsorship_tier
                ),
                "amount": float(sponsor.amount),
                "days_overdue": days_overdue,
                "last_payment_date": payment.payment_date if payment else None,
                "next_due_date": payment.next_due_date if payment else None,
            })
    except Exception as exc:
        _rollback_after_dashboard_error(db, "overdue_sponsors_serialize", exc)
        overdue_list = []

    recent_payments = _safe_dashboard_rows(
        db,
        "recent_payments",
        lambda: (
            db.query(SponsorPayment, Sponsor)
            .join(Sponsor, Sponsor.id == SponsorPayment.sponsor_id)
            .filter(
                SponsorPayment.deleted_at.is_(None),
                Sponsor.deleted_at.is_(None),
                SponsorPayment.status == PaymentStatusEnum.COMPLETED,
            )
            .order_by(SponsorPayment.payment_date.desc().nulls_last())
            .limit(8)
        ),
    )

    try:
        recent_payment_list = [
            {
                "id": payment.id,
                "sponsor_id": sponsor.id,
                "sponsor_name": sponsor.full_name,
                "amount": float(payment.amount),
                "date": payment.payment_date.strftime("%d/%m/%Y")
                if payment.payment_date
                else "",
            }
            for payment, sponsor in recent_payments
        ]
    except Exception as exc:
        _rollback_after_dashboard_error(db, "recent_payments_serialize", exc)
        recent_payment_list = []

    return {
        "total_sponsors": total_sponsors,
        "active_sponsors": active_sponsors,
        "monthly_revenue": float(monthly_revenue),
        "annual_revenue": float(annual_revenue),
        "payments_this_month": payments_this_month,
        "overdue_sponsors": overdue_list,
        "recent_payments": recent_payment_list,
    }


def get_finance_ops(db: Session) -> dict:
    """
    Operational health snapshot for the finance/sponsorship pipeline.

    Designed for the ops monitoring panel: surfaces everything that can
    silently go wrong at donor scale — stuck pending payments, thank-you
    delivery gaps, notification queue backlog/failures, and missing provider
    credentials — plus human-readable alerts so a finance admin can act
    without reading logs.
    """
    from datetime import timedelta

    from app.models.notification import NotificationQueue

    now = datetime.now(timezone.utc)
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    stuck_cutoff = now - timedelta(minutes=30)
    week_ago = now - timedelta(days=7)
    month_ago = now - timedelta(days=30)

    def _count(section: str, query_factory) -> int:
        return int(_safe_dashboard_scalar(db, section, query_factory, 0))

    base_payment = lambda: db.query(func.count(SponsorPayment.id)).filter(  # noqa: E731
        SponsorPayment.deleted_at.is_(None)
    )

    pending_count = _count(
        "ops_pending",
        lambda: base_payment().filter(SponsorPayment.status == PaymentStatusEnum.PENDING),
    )
    stuck_pending = _count(
        "ops_stuck_pending",
        lambda: base_payment().filter(
            SponsorPayment.status == PaymentStatusEnum.PENDING,
            SponsorPayment.payment_method == "FLUTTERWAVE",
            SponsorPayment.created_at <= stuck_cutoff,
        ),
    )
    completed_today = _count(
        "ops_completed_today",
        lambda: base_payment().filter(
            SponsorPayment.status == PaymentStatusEnum.COMPLETED,
            SponsorPayment.payment_date >= today_start,
        ),
    )
    failed_30d = _count(
        "ops_failed_30d",
        lambda: base_payment().filter(
            SponsorPayment.status == PaymentStatusEnum.FAILED,
            SponsorPayment.updated_at >= month_ago,
        ),
    )
    # Completed in the last 7 days but never thanked — a delivery gap
    missing_thank_you = _count(
        "ops_missing_thank_you",
        lambda: base_payment().filter(
            SponsorPayment.status == PaymentStatusEnum.COMPLETED,
            SponsorPayment.thank_you_sent_at.is_(None),
            SponsorPayment.payment_date >= week_ago,
        ),
    )

    oldest_pending = _safe_dashboard_scalar(
        db,
        "ops_oldest_pending",
        lambda: db.query(func.min(SponsorPayment.created_at)).filter(
            SponsorPayment.deleted_at.is_(None),
            SponsorPayment.status == PaymentStatusEnum.PENDING,
            SponsorPayment.payment_method == "FLUTTERWAVE",
        ),
        None,
    )
    oldest_pending_minutes = None
    if oldest_pending is not None:
        if oldest_pending.tzinfo is None:
            oldest_pending = oldest_pending.replace(tzinfo=timezone.utc)
        oldest_pending_minutes = max(0, int((now - oldest_pending).total_seconds() // 60))

    nq_pending = _count(
        "ops_nq_pending",
        lambda: db.query(func.count(NotificationQueue.id)).filter(
            NotificationQueue.status == "PENDING"
        ),
    )
    nq_failed = _count(
        "ops_nq_failed",
        lambda: db.query(func.count(NotificationQueue.id)).filter(
            NotificationQueue.status == "FAILED"
        ),
    )
    nq_retrying = _count(
        "ops_nq_retrying",
        lambda: db.query(func.count(NotificationQueue.id)).filter(
            NotificationQueue.status == "PENDING",
            NotificationQueue.retry_count > 0,
        ),
    )

    providers = {
        "flutterwave_api": bool(settings.FLUTTERWAVE_SECRET_KEY),
        "flutterwave_webhook": bool(settings.FLUTTERWAVE_SECRET_HASH),
        "termii_sms": bool(settings.TERMII_API_KEY),
        "brevo_email": bool(settings.BREVO_API_KEY),
    }

    alerts: list[str] = []
    if not providers["flutterwave_api"]:
        alerts.append(
            "FLUTTERWAVE_SECRET_KEY is not set — payment links and verification will fail."
        )
    if not providers["flutterwave_webhook"]:
        alerts.append(
            "FLUTTERWAVE_SECRET_HASH is not set — all Flutterwave webhooks are rejected, "
            "so payments will not complete automatically."
        )
    if not providers["termii_sms"]:
        alerts.append("TERMII_API_KEY is not set — SMS/WhatsApp notifications will fail.")
    if not providers["brevo_email"]:
        alerts.append("BREVO_API_KEY is not set — email notifications will fail.")
    if stuck_pending > 0:
        alerts.append(
            f"{stuck_pending} Flutterwave payment(s) have been pending for over 30 minutes — "
            "run 'Recheck Payments' or check the webhook configuration."
        )
    if missing_thank_you > 0:
        alerts.append(
            f"{missing_thank_you} completed payment(s) in the last 7 days have no thank-you "
            "delivered — resend from the sponsor's payment history."
        )
    if nq_failed > 0:
        alerts.append(
            f"{nq_failed} queued notification(s) permanently failed — check provider "
            "credentials and recipient contact details."
        )

    return {
        "generated_at": now.isoformat(),
        "healthy": len(alerts) == 0,
        "payments": {
            "pending": pending_count,
            "stuck_pending": stuck_pending,
            "oldest_pending_minutes": oldest_pending_minutes,
            "completed_today": completed_today,
            "failed_last_30_days": failed_30d,
            "missing_thank_you_7_days": missing_thank_you,
        },
        "notifications": {
            "queued": nq_pending,
            "retrying": nq_retrying,
            "failed": nq_failed,
        },
        "providers": providers,
        "alerts": alerts,
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
