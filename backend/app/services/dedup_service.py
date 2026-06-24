"""
Genesis Global CMS — Deduplication Service

Implements fuzzy matching logic to detect potential duplicate members.
Called automatically on every new member creation.
"""
import re
import uuid
from dataclasses import dataclass
from difflib import SequenceMatcher
from typing import Optional

from sqlalchemy.orm import Session

from app.models.member import MemberModel, MemberStatusEnum


# ── Score threshold ────────────────────────────────────────────────────────────

DUPLICATE_THRESHOLD = 85.0  # flag if overall score >= 85%


# ── Data classes ───────────────────────────────────────────────────────────────

@dataclass
class DupResult:
    existing_member_id: uuid.UUID
    existing_member_name: str
    overall_score: float
    phone_score: float
    name_score: float
    email_score: float


# ── Phone Normalization ────────────────────────────────────────────────────────

def normalize_phone(phone: Optional[str]) -> Optional[str]:
    """
    Normalize a phone number to the last 11 digits.
    Handles +234, 234, 0 prefixes common in Nigeria.

    Returns None if phone is blank or too short.
    """
    if not phone:
        return None

    # Strip all non-digit characters
    digits = re.sub(r"\D", "", phone)

    if not digits:
        return None

    # If starts with 234 (country code), strip it and restore the leading 0
    if digits.startswith("234") and len(digits) > 11:
        digits = "0" + digits[3:]

    # Take the last 11 digits (handles any leading zeros or country code)
    if len(digits) >= 10:
        return digits[-11:] if len(digits) >= 11 else digits

    return None


# ── Name Similarity ────────────────────────────────────────────────────────────

def _tokenize_name(name: str) -> set[str]:
    """Tokenize a name into lowercase alphabetic tokens."""
    return set(t.lower() for t in re.split(r"\s+", name.strip()) if t)


def calculate_name_similarity(name1: str, name2: str) -> float:
    """
    Calculate similarity between two names.

    Algorithm:
      1. Exact match → 100%
      2. Token match (sort tokens alphabetically, join, compare) → 100% if all tokens match
      3. Weighted average: Jaccard(60%) + SequenceMatcher(40%)

    Returns a float 0.0–100.0.
    """
    if not name1 or not name2:
        return 0.0

    n1 = name1.strip().lower()
    n2 = name2.strip().lower()

    # Exact match
    if n1 == n2:
        return 100.0

    # Token sort match
    tokens1 = _tokenize_name(name1)
    tokens2 = _tokenize_name(name2)

    sorted1 = " ".join(sorted(tokens1))
    sorted2 = " ".join(sorted(tokens2))

    if sorted1 == sorted2:
        return 100.0

    # Jaccard similarity on token sets
    intersection = tokens1 & tokens2
    union = tokens1 | tokens2
    jaccard = (len(intersection) / len(union) * 100.0) if union else 0.0

    # SequenceMatcher on the sorted token strings
    seq_ratio = SequenceMatcher(None, sorted1, sorted2).ratio() * 100.0

    # Weighted average: sequence matcher handles typos much better than Jaccard
    return jaccard * 0.20 + seq_ratio * 0.80


# ── Email Similarity ───────────────────────────────────────────────────────────

def _normalize_email(email: Optional[str]) -> Optional[str]:
    """Return lowercase stripped email, or None."""
    if not email:
        return None
    return email.strip().lower()


def calculate_email_score(email1: Optional[str], email2: Optional[str]) -> float:
    """Return 100.0 if emails match exactly (normalized), else 0.0."""
    e1 = _normalize_email(email1)
    e2 = _normalize_email(email2)
    if e1 and e2 and e1 == e2:
        return 100.0
    return 0.0


# ── Overall Score ──────────────────────────────────────────────────────────────

def calculate_duplicate_score(
    new_name: str,
    new_phone: Optional[str],
    new_email: Optional[str],
    existing_name: str,
    existing_phone: Optional[str],
    existing_email: Optional[str],
) -> dict:
    """
    Compute the composite duplicate score between a new member and an existing one.

    Returns:
        {
          overall_score: float,
          phone_score: float,
          name_score: float,
          email_score: float,
        }

    Scoring:
      - Phone exact match → overall = 0.60 * 100 + 0.40 * name_score
      - No phone match   → overall = 0.70 * name_score + 0.30 * email_score
    """
    name_score = calculate_name_similarity(new_name, existing_name)
    email_score = calculate_email_score(new_email, existing_email)

    norm_new = normalize_phone(new_phone)
    norm_existing = normalize_phone(existing_phone)

    phone_match = (
        norm_new is not None
        and norm_existing is not None
        and norm_new == norm_existing
    )

    phone_score = 100.0 if phone_match else 0.0

    if phone_match:
        # Phone match alone must clear the duplicate threshold; name is a minor modifier
        overall_score = 0.80 * 100.0 + 0.20 * name_score
    else:
        overall_score = 0.70 * name_score + 0.30 * email_score

    return {
        "overall_score": round(overall_score, 2),
        "phone_score": round(phone_score, 2),
        "name_score": round(name_score, 2),
        "email_score": round(email_score, 2),
    }


# ── Run Dedup Check ────────────────────────────────────────────────────────────

async def run_dedup_check(
    full_name: str,
    phone: Optional[str],
    email: Optional[str],
    db: Session,
    exclude_id: Optional[uuid.UUID] = None,
) -> list[DupResult]:
    """
    Check a new member against all active non-deleted members.
    Returns all matches with overall_score >= DUPLICATE_THRESHOLD.

    Args:
        full_name:  Proposed full name.
        phone:      Proposed phone (raw, will be normalized).
        email:      Proposed email.
        db:         DB session.
        exclude_id: Optional UUID to exclude (when updating an existing member).
    """
    # Query only active/pending members — skip already merged/rejected
    query = db.query(MemberModel).filter(
        MemberModel.deleted_at.is_(None),
        MemberModel.membership_status.in_([
            MemberStatusEnum.ACTIVE,
            MemberStatusEnum.PENDING,
            MemberStatusEnum.PENDING_DUPLICATE_CHECK,
            MemberStatusEnum.PENDING_INFO_REQUESTED,
            MemberStatusEnum.INACTIVE,
        ]),
    )

    if exclude_id:
        query = query.filter(MemberModel.id != exclude_id)

    existing_members = query.all()

    results: list[DupResult] = []

    for member in existing_members:
        scores = calculate_duplicate_score(
            new_name=full_name,
            new_phone=phone,
            new_email=email,
            existing_name=member.full_name,
            existing_phone=member.phone,
            existing_email=member.email,
        )

        if scores["overall_score"] >= DUPLICATE_THRESHOLD:
            results.append(
                DupResult(
                    existing_member_id=member.id,
                    existing_member_name=member.full_name,
                    overall_score=scores["overall_score"],
                    phone_score=scores["phone_score"],
                    name_score=scores["name_score"],
                    email_score=scores["email_score"],
                )
            )

    # Sort descending by overall score
    results.sort(key=lambda r: r.overall_score, reverse=True)
    return results
