"""
Genesis Global CMS — Member Registry Router

Endpoints:
  GET    /members                     List members (scoped)
  POST   /members                     Create member
  GET    /members/pending             List pending members (admin)
  GET    /members/duplicates          List duplicate flags
  POST   /members/search              Search by name/phone
  GET    /members/{id}                Get member detail
  PUT    /members/{id}                Update member
  DELETE /members/{id}                Soft delete (SUPER_ADMIN only)
  POST   /members/{id}/approve        Approve pending
  POST   /members/{id}/reject         Reject with reason
  POST   /members/{id}/request-info   Request more info
  POST   /members/{id}/merge/{target} Merge duplicate
"""
import uuid
from typing import Optional

from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy.orm import Session

from app.auth.dependencies import (
    get_current_user,
    require_role,
)
from app.auth.models import AppUser, UserRole
from app.core.exceptions import PermissionDenied
from app.core.responses import paginated_response, success_response
from app.database import get_db
from app.schemas.member import (
    ApproveRequest,
    MemberCreate,
    MemberSearchRequest,
    MemberUpdate,
    MergeRequest,
    RejectRequest,
    RequestInfoRequest,
)
from app.services.member_service import (
    approve_member,
    create_member,
    filter_member_fields,
    get_member,
    list_duplicates,
    list_members,
    list_pending_members,
    merge_member,
    reject_member,
    request_member_info,
    search_members,
    soft_delete_member,
    update_member,
)

router = APIRouter(prefix="/members", tags=["Members"])
_MEMBER_REGISTRY_BLOCKED_ROLES = {
    UserRole.FINANCE_ADMIN,
    UserRole.HR_ADMIN,
    UserRole.MEMBER,
    UserRole.MEDICAL,
}


# ── List Members ───────────────────────────────────────────────────────────────

@router.get("", summary="List members (scoped by role)")
async def list_members_endpoint(
    request: Request,
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    search: Optional[str] = Query(None),
    status: Optional[str] = Query(None),
    current_user: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if current_user.role in _MEMBER_REGISTRY_BLOCKED_ROLES:
        raise PermissionDenied(message="This role cannot access the member registry.")

    members, total = list_members(db, current_user, request, page, per_page, search, status)
    data = [filter_member_fields(m, current_user.role) for m in members]
    return paginated_response(data=data, total=total, page=page, per_page=per_page)


# ── Pending Members ────────────────────────────────────────────────────────────

@router.get("/pending", summary="List pending members (admin only)")
async def list_pending_endpoint(
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    current_user: AppUser = Depends(
        require_role("SUPER_ADMIN", "PASTOR", "DEPARTMENT_HEAD", "TEAM_LEADER", "GROUP_LEADER")
    ),
    db: Session = Depends(get_db),
):
    members, total = list_pending_members(db, page, per_page)
    data = [filter_member_fields(m, current_user.role) for m in members]
    return paginated_response(data=data, total=total, page=page, per_page=per_page)


# ── Duplicate Flags ────────────────────────────────────────────────────────────

@router.get("/duplicates", summary="List pending duplicate flags")
async def list_duplicates_endpoint(
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    current_user: AppUser = Depends(require_role("SUPER_ADMIN", "PASTOR")),
    db: Session = Depends(get_db),
):
    dups, total = list_duplicates(db, page, per_page)
    data = []
    for dup in dups:
        data.append({
            "id": dup.id,
            "new_member_id": dup.new_member_id,
            "existing_member_id": dup.existing_member_id,
            "overall_score": dup.overall_score,
            "phone_score": dup.phone_score,
            "name_score": dup.name_score,
            "email_score": dup.email_score,
            "status": dup.status,
            "resolved_by": dup.resolved_by,
            "resolved_at": dup.resolved_at,
            "created_at": dup.created_at,
            "new_member_name": dup.new_member.full_name if dup.new_member else None,
            "existing_member_name": dup.existing_member.full_name if dup.existing_member else None,
        })
    return paginated_response(data=data, total=total, page=page, per_page=per_page)


# ── Search Members ─────────────────────────────────────────────────────────────

@router.post("/search", summary="Search members by name or phone")
async def search_members_endpoint(
    body: MemberSearchRequest,
    current_user: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if current_user.role in _MEMBER_REGISTRY_BLOCKED_ROLES:
        raise PermissionDenied(message="This role cannot search member records.")

    members, total = search_members(body.query, db, body.page, body.per_page)
    data = [filter_member_fields(m, current_user.role) for m in members]
    return paginated_response(data=data, total=total, page=body.page, per_page=body.per_page)


# ── Create Member ──────────────────────────────────────────────────────────────

@router.post("", summary="Create a new member", status_code=201)
async def create_member_endpoint(
    body: MemberCreate,
    current_user: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if current_user.role == UserRole.MEDICAL:
        raise PermissionDenied(message="Medical staff cannot create member records.")
    if current_user.role == UserRole.FINANCE_ADMIN:
        raise PermissionDenied(message="Finance admins cannot create member records.")
    if current_user.role == UserRole.HR_ADMIN:
        raise PermissionDenied(message="HR admins cannot create member records.")

    member = await create_member(body, current_user, db)
    return success_response(
        data=filter_member_fields(member, current_user.role),
        message="Member created successfully.",
    )


# ── Get Member ─────────────────────────────────────────────────────────────────

@router.get("/{member_id}", summary="Get member detail")
async def get_member_endpoint(
    member_id: uuid.UUID,
    current_user: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if current_user.role in _MEMBER_REGISTRY_BLOCKED_ROLES:
        raise PermissionDenied(message="This role cannot access member records.")

    member = get_member(member_id, db)
    return success_response(data=filter_member_fields(member, current_user.role))


# ── Update Member ──────────────────────────────────────────────────────────────

@router.put("/{member_id}", summary="Update member")
async def update_member_endpoint(
    member_id: uuid.UUID,
    body: MemberUpdate,
    current_user: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if current_user.role in (UserRole.MEDICAL, UserRole.FINANCE_ADMIN, UserRole.HR_ADMIN):
        raise PermissionDenied(message="Your role cannot update member records.")

    member = get_member(member_id, db)
    member = update_member(member, body, current_user, db)
    return success_response(
        data=filter_member_fields(member, current_user.role),
        message="Member updated successfully.",
    )


# ── Soft Delete ────────────────────────────────────────────────────────────────

@router.delete("/{member_id}", summary="Soft delete member (SUPER_ADMIN only)")
async def delete_member_endpoint(
    member_id: uuid.UUID,
    current_user: AppUser = Depends(require_role("SUPER_ADMIN")),
    db: Session = Depends(get_db),
):
    member = get_member(member_id, db)
    soft_delete_member(member, db)
    return success_response(message="Member deleted successfully.")


# ── Approve Member ─────────────────────────────────────────────────────────────

@router.post("/{member_id}/approve", summary="Approve a pending member")
async def approve_member_endpoint(
    member_id: uuid.UUID,
    body: ApproveRequest,
    current_user: AppUser = Depends(
        require_role("SUPER_ADMIN", "PASTOR", "DEPARTMENT_HEAD", "TEAM_LEADER", "GROUP_LEADER")
    ),
    db: Session = Depends(get_db),
):
    member = get_member(member_id, db)
    member = approve_member(member, current_user, body.admin_notes, db)
    return success_response(
        data=filter_member_fields(member, current_user.role),
        message="Member approved successfully.",
    )


# ── Reject Member ──────────────────────────────────────────────────────────────

@router.post("/{member_id}/reject", summary="Reject a pending member")
async def reject_member_endpoint(
    member_id: uuid.UUID,
    body: RejectRequest,
    current_user: AppUser = Depends(require_role("SUPER_ADMIN", "PASTOR")),
    db: Session = Depends(get_db),
):
    member = get_member(member_id, db)
    member = reject_member(member, current_user, body.reason, body.admin_notes, db)
    return success_response(
        data={"id": member.id, "status": member.membership_status},
        message="Member rejected.",
    )


# ── Request More Info ──────────────────────────────────────────────────────────

@router.post("/{member_id}/request-info", summary="Request more information from submitter")
async def request_info_endpoint(
    member_id: uuid.UUID,
    body: RequestInfoRequest,
    current_user: AppUser = Depends(require_role("SUPER_ADMIN", "PASTOR")),
    db: Session = Depends(get_db),
):
    member = get_member(member_id, db)
    member = request_member_info(member, current_user, body.info_requested, body.admin_notes, db)
    return success_response(
        data={"id": member.id, "status": member.membership_status},
        message="Info request recorded.",
    )


# ── Merge Duplicate ────────────────────────────────────────────────────────────

@router.post("/{member_id}/merge/{target_id}", summary="Merge duplicate member into target")
async def merge_member_endpoint(
    member_id: uuid.UUID,
    target_id: uuid.UUID,
    body: MergeRequest,
    current_user: AppUser = Depends(require_role("SUPER_ADMIN", "PASTOR")),
    db: Session = Depends(get_db),
):
    source = get_member(member_id, db)
    target = get_member(target_id, db)
    target = merge_member(source, target, current_user, db)
    return success_response(
        data=filter_member_fields(target, current_user.role),
        message=f"Member {member_id} merged into {target_id}.",
    )
