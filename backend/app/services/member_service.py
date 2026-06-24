"""
Genesis Global CMS — Member Service

Business logic for member creation, approval, rejection, merging,
deduplication, and role-based field visibility.
"""
import uuid
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import or_
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.auth.models import AppUser, UserRole
from app.core.exceptions import DuplicateRecord, NotFound, PermissionDenied
from app.models.member import MemberDuplicate, MemberModel, MemberStatusEnum, PendingMemberData
from app.schemas.member import (
    MemberCreate,
    MemberUpdate,
)
from app.services.dedup_service import normalize_phone, run_dedup_check
from app.services.notification_service import queue_notification


# ── Role → Status Mapping ──────────────────────────────────────────────────────

_ADMIN_ROLES = {
    UserRole.SUPER_ADMIN,
    UserRole.PASTOR,
}

_SCOPED_ADMIN_ROLES = {
    UserRole.DEPARTMENT_HEAD,
    UserRole.TEAM_LEADER,
    UserRole.GROUP_LEADER,
}

_LIMITED_ROLES = {
    UserRole.FOLLOW_UP,
    UserRole.MEDICAL,
}


def _initial_status_for_role(role: UserRole) -> MemberStatusEnum:
    """Determine the initial membership_status based on the creator's role."""
    if role in _ADMIN_ROLES or role in _SCOPED_ADMIN_ROLES:
        return MemberStatusEnum.ACTIVE
    return MemberStatusEnum.PENDING


# ── Field Visibility Filtering ─────────────────────────────────────────────────

def filter_member_fields(member: MemberModel, viewer_role: UserRole) -> dict:
    """
    Return a dict of member fields appropriate for the viewer's role.

    Role visibility matrix:
      MEDICAL       → full_name, phone, gender, date_of_birth only
      FINANCE_ADMIN → full_name, phone only
      HR_ADMIN      → full_name, phone only
      FOLLOW_UP     → full_name, phone, email, gender, dob, address, marital_status,
                      membership_status
      DEPT_HEAD/TEAM_LEADER/GROUP_LEADER → all except medical/sponsor/HR cross-domain fields
      PASTOR/SUPER_ADMIN → all fields
    """
    base = {
        "id": member.id,
        "full_name": member.full_name,
        "phone": member.phone,
    }

    if viewer_role == UserRole.MEDICAL:
        base["gender"] = member.gender
        base["date_of_birth"] = member.date_of_birth
        return base

    if viewer_role in (UserRole.FINANCE_ADMIN, UserRole.HR_ADMIN):
        return base

    if viewer_role == UserRole.FOLLOW_UP:
        base.update({
            "email": member.email,
            "gender": member.gender,
            "date_of_birth": member.date_of_birth,
            "address": member.address,
            "marital_status": member.marital_status,
            "membership_status": member.membership_status,
        })
        return base

    # Scoped leaders get most fields
    full = {
        "id": member.id,
        "full_name": member.full_name,
        "phone": member.phone,
        "email": member.email,
        "gender": member.gender,
        "date_of_birth": member.date_of_birth,
        "address": member.address,
        "marital_status": member.marital_status,
        "salvation_date": member.salvation_date,
        "water_baptism_status": member.water_baptism_status,
        "holy_spirit_baptism_status": member.holy_spirit_baptism_status,
        "membership_status": member.membership_status,
        "photo_url": member.photo_url,
        "submitted_by": member.submitted_by,
        "approved_by": member.approved_by,
        "approved_at": member.approved_at,
        "rejection_reason": member.rejection_reason,
        "duplicate_of": member.duplicate_of,
        "created_at": member.created_at,
        "updated_at": member.updated_at,
    }
    return full


# ── Create Member ──────────────────────────────────────────────────────────────

async def create_member(
    data: MemberCreate,
    current_user: AppUser,
    db: Session,
) -> MemberModel:
    """
    Create a new member record.

    - Normalize phone
    - Run dedup check
    - Set status based on creator role and dedup result
    - Save pending_member_data if applicable
    - Queue admin notifications for duplicates
    """
    # Normalize phone
    normalized_phone = normalize_phone(data.phone) if data.phone else data.phone

    # Determine initial status
    initial_status = _initial_status_for_role(current_user.role)

    # Run deduplication
    dup_results = await run_dedup_check(
        full_name=data.full_name,
        phone=normalized_phone,
        email=data.email,
        db=db,
    )

    # Override status if duplicates found (even for admins)
    if dup_results:
        initial_status = MemberStatusEnum.PENDING_DUPLICATE_CHECK

    # Build ORM object
    member = MemberModel(
        full_name=data.full_name,
        phone=normalized_phone,
        email=str(data.email).lower() if data.email else None,
        gender=data.gender,
        date_of_birth=data.date_of_birth,
        address=data.address,
        marital_status=data.marital_status,
        salvation_date=data.salvation_date,
        water_baptism_status=data.water_baptism_status,
        holy_spirit_baptism_status=data.holy_spirit_baptism_status,
        membership_status=initial_status,
        photo_url=data.photo_url,
        submitted_by=current_user.id,
    )

    try:
        db.add(member)
        db.flush()  # get the new member ID without committing
    except IntegrityError as exc:
        db.rollback()
        raise DuplicateRecord(message="A member with this phone or email already exists.") from exc

    # Create pending data record if not active immediately
    if initial_status != MemberStatusEnum.ACTIVE or data.submitter_notes:
        pending = PendingMemberData(
            member_id=member.id,
            submitter_notes=data.submitter_notes,
        )
        db.add(pending)

    # Save duplicate records
    for dup in dup_results:
        dup_record = MemberDuplicate(
            new_member_id=member.id,
            existing_member_id=dup.existing_member_id,
            overall_score=dup.overall_score,
            phone_score=dup.phone_score,
            name_score=dup.name_score,
            email_score=dup.email_score,
            status="PENDING",
        )
        db.add(dup_record)

        # Notify admins of potential duplicate (in-app notification)
        # We queue for all admin users — the notification worker handles delivery
        queue_notification(
            db=db,
            recipient_type="USER",
            recipient_id=current_user.id,  # notify the submitter too
            channel="IN_APP",
            template_key="DUPLICATE_DETECTED",
            payload={
                "new_member_name": member.full_name,
                "existing_member_name": dup.existing_member_name,
                "score": dup.overall_score,
            },
        )

    db.flush()
    return member


# ── Get Member ─────────────────────────────────────────────────────────────────

def get_member(member_id: uuid.UUID, db: Session) -> MemberModel:
    """Fetch a non-deleted member by ID or raise NotFound."""
    member = db.query(MemberModel).filter(
        MemberModel.id == member_id,
        MemberModel.deleted_at.is_(None),
    ).first()
    if not member:
        raise NotFound(message=f"Member {member_id} not found.")
    return member


# ── Update Member ──────────────────────────────────────────────────────────────

def update_member(
    member: MemberModel,
    data: MemberUpdate,
    current_user: AppUser,
    db: Session,
) -> MemberModel:
    """Apply partial updates to a member. Scoped roles can only update their own members."""
    update_data = data.model_dump(exclude_unset=True)

    if "phone" in update_data and update_data["phone"]:
        update_data["phone"] = normalize_phone(update_data["phone"])

    if "email" in update_data and update_data["email"]:
        update_data["email"] = str(update_data["email"]).lower()

    for field, value in update_data.items():
        setattr(member, field, value)

    try:
        db.flush()
    except IntegrityError as exc:
        db.rollback()
        raise DuplicateRecord(message="A member with this phone or email already exists.") from exc

    return member


# ── Soft Delete ────────────────────────────────────────────────────────────────

def soft_delete_member(member: MemberModel, db: Session) -> None:
    """Set deleted_at to now (SUPER_ADMIN only — enforced at router level)."""
    member.deleted_at = datetime.now(timezone.utc)
    db.flush()


# ── Approve Member ─────────────────────────────────────────────────────────────

def approve_member(
    member: MemberModel,
    current_user: AppUser,
    admin_notes: Optional[str],
    db: Session,
) -> MemberModel:
    """Approve a pending member. Sets status to ACTIVE."""
    if member.membership_status not in (
        MemberStatusEnum.PENDING,
        MemberStatusEnum.PENDING_DUPLICATE_CHECK,
        MemberStatusEnum.PENDING_INFO_REQUESTED,
    ):
        raise PermissionDenied(
            message=f"Cannot approve a member with status '{member.membership_status}'."
        )

    member.membership_status = MemberStatusEnum.ACTIVE
    member.approved_by = current_user.id
    member.approved_at = datetime.now(timezone.utc)

    # Update pending data
    if member.pending_data:
        if admin_notes:
            member.pending_data.admin_notes = admin_notes

    # Resolve any pending duplicate flags
    db.query(MemberDuplicate).filter(
        MemberDuplicate.new_member_id == member.id,
        MemberDuplicate.status == "PENDING",
    ).update(
        {"status": "RESOLVED", "resolved_by": current_user.id, "resolved_at": datetime.now(timezone.utc)},
        synchronize_session=False,
    )

    db.flush()

    # Queue welcome SMS to member (if phone exists)
    if member.phone:
        queue_notification(
            db=db,
            recipient_type="MEMBER",
            recipient_id=member.id,
            channel="SMS",
            template_key="MEMBER_WELCOME",
            payload={"name": member.full_name},
        )

    return member


# ── Reject Member ──────────────────────────────────────────────────────────────

def reject_member(
    member: MemberModel,
    current_user: AppUser,
    reason: str,
    admin_notes: Optional[str],
    db: Session,
) -> MemberModel:
    """Reject a pending member."""
    if member.membership_status not in (
        MemberStatusEnum.PENDING,
        MemberStatusEnum.PENDING_DUPLICATE_CHECK,
        MemberStatusEnum.PENDING_INFO_REQUESTED,
    ):
        raise PermissionDenied(
            message=f"Cannot reject a member with status '{member.membership_status}'."
        )

    member.membership_status = MemberStatusEnum.REJECTED
    member.rejection_reason = reason

    if member.pending_data and admin_notes:
        member.pending_data.admin_notes = admin_notes

    db.flush()
    return member


# ── Request More Info ──────────────────────────────────────────────────────────

def request_member_info(
    member: MemberModel,
    current_user: AppUser,
    info_requested: str,
    admin_notes: Optional[str],
    db: Session,
) -> MemberModel:
    """Set status to PENDING_INFO_REQUESTED and record what info is needed."""
    member.membership_status = MemberStatusEnum.PENDING_INFO_REQUESTED

    if not member.pending_data:
        member.pending_data = PendingMemberData(member_id=member.id)
        db.add(member.pending_data)

    member.pending_data.additional_info_requested = info_requested
    if admin_notes:
        member.pending_data.admin_notes = admin_notes

    db.flush()
    return member


# ── Merge Duplicate ────────────────────────────────────────────────────────────

def merge_member(
    source_member: MemberModel,
    target_member: MemberModel,
    current_user: AppUser,
    db: Session,
) -> MemberModel:
    """
    Merge source_member into target_member.
    - source gets status MERGED and duplicate_of = target.id
    - duplicate flags are resolved
    """
    source_member.membership_status = MemberStatusEnum.MERGED
    source_member.duplicate_of = target_member.id

    # Resolve all duplicate flags between these two
    db.query(MemberDuplicate).filter(
        or_(
            MemberDuplicate.new_member_id == source_member.id,
            MemberDuplicate.existing_member_id == source_member.id,
        ),
        MemberDuplicate.status == "PENDING",
    ).update(
        {"status": "RESOLVED", "resolved_by": current_user.id, "resolved_at": datetime.now(timezone.utc)},
        synchronize_session=False,
    )

    db.flush()
    return target_member


# ── List Members (with scope) ──────────────────────────────────────────────────

def list_members(
    db: Session,
    current_user: AppUser,
    request,
    page: int = 1,
    per_page: int = 20,
    search: Optional[str] = None,
    status: Optional[str] = None,
) -> tuple[list[MemberModel], int]:
    """
    List members with role-based scope filtering and pagination.
    Returns (members, total_count).
    """
    from app.auth.dependencies import ScopeFilter

    query = db.query(MemberModel).filter(MemberModel.deleted_at.is_(None))

    # Apply scope filtering
    query = ScopeFilter.filter_members_by_scope(query, current_user, request)

    # Text search
    if search:
        search_term = f"%{search}%"
        query = query.filter(
            or_(
                MemberModel.full_name.ilike(search_term),
                MemberModel.phone.ilike(search_term),
                MemberModel.email.ilike(search_term),
            )
        )

    # Status filter
    if status:
        query = query.filter(MemberModel.membership_status == status)

    # Exclude MEDICAL role from accessing members
    if current_user.role == UserRole.MEDICAL:
        raise PermissionDenied(message="Medical staff cannot access member records.")

    total = query.count()
    members = (
        query.order_by(MemberModel.created_at.desc())
        .offset((page - 1) * per_page)
        .limit(per_page)
        .all()
    )

    return members, total


# ── List Pending Members ───────────────────────────────────────────────────────

def list_pending_members(
    db: Session,
    page: int = 1,
    per_page: int = 20,
) -> tuple[list[MemberModel], int]:
    """List all members in any pending state."""
    query = db.query(MemberModel).filter(
        MemberModel.deleted_at.is_(None),
        MemberModel.membership_status.in_([
            MemberStatusEnum.PENDING,
            MemberStatusEnum.PENDING_DUPLICATE_CHECK,
            MemberStatusEnum.PENDING_INFO_REQUESTED,
        ]),
    ).order_by(MemberModel.created_at.asc())

    total = query.count()
    members = query.offset((page - 1) * per_page).limit(per_page).all()
    return members, total


# ── List Duplicates ────────────────────────────────────────────────────────────

def list_duplicates(
    db: Session,
    page: int = 1,
    per_page: int = 20,
) -> tuple[list[MemberDuplicate], int]:
    """List pending duplicate flags with member names."""
    query = db.query(MemberDuplicate).filter(
        MemberDuplicate.status == "PENDING",
    ).order_by(MemberDuplicate.created_at.desc())

    total = query.count()
    dups = query.offset((page - 1) * per_page).limit(per_page).all()
    return dups, total


# ── Search Members ─────────────────────────────────────────────────────────────

def search_members(
    query_str: str,
    db: Session,
    page: int = 1,
    per_page: int = 20,
) -> tuple[list[MemberModel], int]:
    """Full-text search on name and phone."""
    search_term = f"%{query_str}%"
    query = db.query(MemberModel).filter(
        MemberModel.deleted_at.is_(None),
        or_(
            MemberModel.full_name.ilike(search_term),
            MemberModel.phone.ilike(search_term),
            MemberModel.email.ilike(search_term),
        ),
    ).order_by(MemberModel.full_name.asc())

    total = query.count()
    members = query.offset((page - 1) * per_page).limit(per_page).all()
    return members, total
