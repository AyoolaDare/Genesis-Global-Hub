"""
Genesis Global CMS — Donor Payment Funnel Service

Powers the donor reminder & tracking funnel:

  1. Configurable reminder schedule (stored in app_settings under
     "finance.funnel") — weekly reminder → week-3 nudge → final notice.
  2. Donor funnel analytics: every active sponsor bucketed by payment status
     (PAID / PENDING / OVERDUE) and tenure (how long they have been giving),
     with a consistency label for stewardship (CONSISTENT / REGULAR / NEW /
     LAPSED).

The daily Celery task (check_overdue_payments) reads the same config, so
changing the schedule in the UI immediately changes when reminders fire.
"""
import logging
import uuid
from datetime import date, datetime, timezone
from typing import Optional

from sqlalchemy.orm import Session

from app.models.settings import AppSetting
from app.models.sponsor import (
    PaymentStatusEnum,
    Sponsor,
    SponsorPayment,
    SponsorshipTierEnum,
)

logger = logging.getLogger(__name__)

FUNNEL_CONFIG_KEY = "finance.funnel"

# Days are relative to the donor's next_due_date.
DEFAULT_FUNNEL_CONFIG: dict = {
    "enabled": True,
    # Stage 1 — weekly reminder: fires within N days BEFORE the due date.
    "stage1_days_before_due": 7,
    # Stage 2 — week-3 nudge: fires once the payment is N days OVERDUE.
    "stage2_days_overdue": 14,
    # Stage 3 — final notice: fires once the payment is N days OVERDUE.
    "stage3_days_overdue": 21,
}

TENURE_BUCKETS = ["NEW", "1_3_MONTHS", "3_6_MONTHS", "6_12_MONTHS", "1_YEAR_PLUS"]

_MONTHS_PER_CYCLE = {
    SponsorshipTierEnum.MONTHLY: 1,
    SponsorshipTierEnum.QUARTERLY: 3,
    SponsorshipTierEnum.ANNUAL: 12,
}


# ── Config ─────────────────────────────────────────────────────────────────────

def get_funnel_config(db: Session) -> dict:
    """Return the funnel config merged over defaults (missing keys filled in)."""
    config = dict(DEFAULT_FUNNEL_CONFIG)
    try:
        row = db.get(AppSetting, FUNNEL_CONFIG_KEY)
        if row and isinstance(row.value, dict):
            for key in DEFAULT_FUNNEL_CONFIG:
                if key in row.value:
                    config[key] = row.value[key]
    except Exception as exc:
        logger.warning("get_funnel_config: falling back to defaults: %s", exc)
    return config


def update_funnel_config(db: Session, data: dict, updated_by: Optional[uuid.UUID]) -> dict:
    """
    Validate and persist funnel config changes. Only known keys are stored;
    stage offsets must be positive and strictly ordered (week 3 before final).
    """
    current = get_funnel_config(db)
    merged = {**current, **{k: v for k, v in data.items() if k in DEFAULT_FUNNEL_CONFIG}}

    s1 = int(merged["stage1_days_before_due"])
    s2 = int(merged["stage2_days_overdue"])
    s3 = int(merged["stage3_days_overdue"])
    if s1 < 1 or s1 > 60:
        raise ValueError("stage1_days_before_due must be between 1 and 60.")
    if s2 < 1 or s3 <= s2:
        raise ValueError(
            "stage3_days_overdue must be greater than stage2_days_overdue (both ≥ 1)."
        )
    merged["stage1_days_before_due"] = s1
    merged["stage2_days_overdue"] = s2
    merged["stage3_days_overdue"] = s3
    merged["enabled"] = bool(merged["enabled"])

    row = db.get(AppSetting, FUNNEL_CONFIG_KEY)
    if row is None:
        row = AppSetting(key=FUNNEL_CONFIG_KEY, value=merged, updated_by=updated_by)
        db.add(row)
    else:
        row.value = merged
        row.updated_by = updated_by
    db.flush()
    return merged


# ── Funnel analytics ───────────────────────────────────────────────────────────

def _tenure_bucket(months: int) -> str:
    if months < 1:
        return "NEW"
    if months < 3:
        return "1_3_MONTHS"
    if months < 6:
        return "3_6_MONTHS"
    if months < 12:
        return "6_12_MONTHS"
    return "1_YEAR_PLUS"


def _months_between(start: date, end: date) -> int:
    return max(0, (end.year - start.year) * 12 + (end.month - start.month))


def get_donor_funnel(db: Session) -> dict:
    """
    Build the donor funnel snapshot: per-donor status, tenure and consistency,
    plus a status × tenure summary matrix for the dashboard.

    Status semantics:
      PAID    — current cycle covered (next due date in the future), or a
                ONE_TIME sponsor who has completed a payment.
      PENDING — has not completed any payment yet (new / link outstanding).
      OVERDUE — latest cycle's due date has passed without a new payment.
    """
    today = date.today()

    sponsors: list[Sponsor] = (
        db.query(Sponsor)
        .filter(Sponsor.deleted_at.is_(None), Sponsor.is_active.is_(True))
        .all()
    )
    if not sponsors:
        return _empty_funnel()

    # One query for all completed payments; aggregate in Python. At tens of
    # thousands of rows this remains cheap (indexed, id+dates only).
    completed_rows = (
        db.query(
            SponsorPayment.sponsor_id,
            SponsorPayment.payment_date,
            SponsorPayment.next_due_date,
            SponsorPayment.amount,
            SponsorPayment.reminder_stage,
        )
        .filter(
            SponsorPayment.deleted_at.is_(None),
            SponsorPayment.status == PaymentStatusEnum.COMPLETED,
        )
        .order_by(SponsorPayment.sponsor_id, SponsorPayment.payment_date.asc().nulls_last())
        .all()
    )

    by_sponsor: dict = {}
    for sponsor_id, payment_date, next_due, amount, stage in completed_rows:
        agg = by_sponsor.setdefault(
            sponsor_id,
            {
                "count": 0,
                "total": 0.0,
                "first": None,
                "last": None,
                "next_due": None,
                "stage": 0,
            },
        )
        agg["count"] += 1
        agg["total"] += float(amount or 0)
        pdate = payment_date.date() if isinstance(payment_date, datetime) else payment_date
        if pdate:
            if agg["first"] is None or pdate < agg["first"]:
                agg["first"] = pdate
            if agg["last"] is None or pdate > agg["last"]:
                agg["last"] = pdate
        # Rows are ordered by payment_date asc → the last row wins, which is
        # the latest cycle's due date and funnel stage.
        if next_due is not None:
            agg["next_due"] = next_due
            agg["stage"] = int(stage or 0)

    donors: list[dict] = []
    summary = {"paid": 0, "pending": 0, "overdue": 0}
    matrix = {
        bucket: {"paid": 0, "pending": 0, "overdue": 0, "total": 0}
        for bucket in TENURE_BUCKETS
    }

    for sponsor in sponsors:
        agg = by_sponsor.get(sponsor.id)
        count = agg["count"] if agg else 0
        first = agg["first"] if agg else None
        last = agg["last"] if agg else None
        next_due = agg["next_due"] if agg else None
        stage = agg["stage"] if agg else 0
        total = agg["total"] if agg else 0.0

        tenure_months = _months_between(first, today) if first else 0
        bucket = _tenure_bucket(tenure_months)

        # Status
        if count == 0:
            status = "PENDING"
            days_overdue = None
        elif sponsor.sponsorship_tier == SponsorshipTierEnum.ONE_TIME or next_due is None:
            status = "PAID"
            days_overdue = None
        elif next_due >= today:
            status = "PAID"
            days_overdue = None
        else:
            status = "OVERDUE"
            days_overdue = (today - next_due).days

        # Consistency (stewardship label)
        cycle_months = _MONTHS_PER_CYCLE.get(sponsor.sponsorship_tier)
        if count == 0 or tenure_months < 1:
            consistency = "NEW"
        elif status == "OVERDUE" and days_overdue is not None and days_overdue > 45:
            consistency = "LAPSED"
        elif cycle_months:
            expected = max(1, tenure_months // cycle_months)
            consistency = (
                "CONSISTENT" if count >= 3 and count >= 0.8 * expected else "REGULAR"
            )
        else:
            consistency = "REGULAR"

        key = status.lower()
        summary[key] += 1
        matrix[bucket][key] += 1
        matrix[bucket]["total"] += 1

        donors.append({
            "id": sponsor.id,
            "full_name": sponsor.full_name,
            "phone": sponsor.phone,
            "email": sponsor.email,
            "tier": sponsor.sponsorship_tier.value,
            "amount": float(sponsor.amount),
            "status": status,
            "days_overdue": days_overdue,
            "reminder_stage": stage,
            "tenure_months": tenure_months,
            "tenure_bucket": bucket,
            "payments_count": count,
            "total_paid": round(total, 2),
            "first_payment_date": first.isoformat() if first else None,
            "last_payment_date": last.isoformat() if last else None,
            "next_due_date": next_due.isoformat() if next_due else None,
            "consistency": consistency,
        })

    # Longest-tenured donors first; overdue sorted to the top within a bucket
    donors.sort(key=lambda d: (-d["tenure_months"], d["status"] != "OVERDUE", d["full_name"]))

    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "summary": summary,
        "tenure_matrix": matrix,
        "donors": donors,
    }


def _empty_funnel() -> dict:
    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "summary": {"paid": 0, "pending": 0, "overdue": 0},
        "tenure_matrix": {
            bucket: {"paid": 0, "pending": 0, "overdue": 0, "total": 0}
            for bucket in TENURE_BUCKETS
        },
        "donors": [],
    }
