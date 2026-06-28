"""
Genesis Global CMS — Structure Router (Departments / Teams / Groups)
"""
import uuid

from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.auth.dependencies import get_current_user, require_role
from app.auth.models import AppUser
from app.core.responses import paginated_response, success_response
from app.database import get_db
from app.models.structure import Department as DeptModel, MemberAssignment, Team as TeamModel
from app.schemas.structure import (
    AssignHeadRequest,
    AssignLeaderRequest,
    DepartmentCreate,
    DepartmentUpdate,
    GroupCreate,
    MemberAssignRequest,
    TeamCreate,
)
from app.services.structure_service import (
    assign_department_head,
    assign_group_leader,
    assign_member,
    assign_team_leader,
    create_department,
    create_group,
    create_team,
    get_department,
    get_department_members,
    get_group,
    get_group_members,
    get_team,
    get_team_members,
    list_departments,
    list_groups,
    list_teams,
    remove_assignment,
    update_department,
)


router = APIRouter(tags=["Structure"])


# ── Departments ────────────────────────────────────────────────────────────────

@router.get("/departments", summary="List all departments")
async def list_departments_endpoint(
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    current_user: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    items, total = list_departments(db, page, per_page)
    data = []
    for d in items:
        head_email = None
        if d.head_user_id:
            head_user = db.get(AppUser, d.head_user_id)
            head_email = head_user.email if head_user else None
        data.append({
            "id": d.id,
            "name": d.name,
            "description": d.description,
            "head_id": d.head_user_id,
            "head_name": head_email,
            "member_count": db.query(func.count(MemberAssignment.id))
            .filter(
                MemberAssignment.assignment_type == "DEPARTMENT",
                MemberAssignment.assignment_id == d.id,
                MemberAssignment.left_at.is_(None),
                MemberAssignment.deleted_at.is_(None),
            )
            .scalar() or 0,
            "team_count": db.query(func.count(TeamModel.id))
            .filter(TeamModel.department_id == d.id, TeamModel.deleted_at.is_(None))
            .scalar() or 0,
            "created_at": d.created_at,
            "updated_at": d.updated_at,
        })
    return paginated_response(data=data, total=total, page=page, per_page=per_page)


@router.post("/departments", summary="Create department (SUPER_ADMIN only)", status_code=201)
async def create_department_endpoint(
    body: DepartmentCreate,
    current_user: AppUser = Depends(require_role("SUPER_ADMIN", "PASTOR")),
    db: Session = Depends(get_db),
):
    dept = create_department(body, current_user, db)
    return success_response(
        data={
            "id": dept.id,
            "name": dept.name,
            "description": dept.description,
            "head_user_id": dept.head_user_id,
            "created_at": dept.created_at,
        },
        message="Department created.",
    )


@router.get("/departments/{dept_id}", summary="Get department with teams and groups")
async def get_department_endpoint(
    dept_id: uuid.UUID,
    current_user: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    dept = get_department(dept_id, db)
    return success_response(data={
        "id": dept.id,
        "name": dept.name,
        "description": dept.description,
        "head_user_id": dept.head_user_id,
        "created_at": dept.created_at,
        "updated_at": dept.updated_at,
        "teams": [
            {"id": t.id, "name": t.name, "leader_user_id": t.leader_user_id}
            for t in dept.teams
        ],
        "groups": [
            {"id": g.id, "name": g.name, "team_id": g.team_id, "leader_user_id": g.leader_user_id}
            for g in dept.groups
        ],
    })


@router.put("/departments/{dept_id}", summary="Update department")
async def update_department_endpoint(
    dept_id: uuid.UUID,
    body: DepartmentUpdate,
    current_user: AppUser = Depends(require_role("SUPER_ADMIN", "PASTOR", "DEPARTMENT_HEAD")),
    db: Session = Depends(get_db),
):
    dept = get_department(dept_id, db)
    dept = update_department(dept, body, current_user, db)
    return success_response(
        data={"id": dept.id, "name": dept.name, "description": dept.description},
        message="Department updated.",
    )


@router.get("/departments/{dept_id}/members", summary="List members in a department")
async def dept_members_endpoint(
    dept_id: uuid.UUID,
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    current_user: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    members, total = get_department_members(dept_id, db, page, per_page)
    data = [{"id": m.id, "full_name": m.full_name, "phone": m.phone, "membership_status": m.membership_status} for m in members]
    return paginated_response(data=data, total=total, page=page, per_page=per_page)


@router.post("/departments/{dept_id}/assign-head", summary="Assign department head")
async def assign_dept_head_endpoint(
    dept_id: uuid.UUID,
    body: AssignHeadRequest,
    current_user: AppUser = Depends(require_role("SUPER_ADMIN", "PASTOR")),
    db: Session = Depends(get_db),
):
    dept = get_department(dept_id, db)
    dept = assign_department_head(dept, body.user_id, db)
    return success_response(data={"id": dept.id, "head_user_id": dept.head_user_id}, message="Department head assigned.")


# ── Teams ──────────────────────────────────────────────────────────────────────

@router.get("/teams", summary="List teams (scoped)")
async def list_teams_endpoint(
    request: Request,
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    current_user: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    items, total = list_teams(db, current_user, request, page, per_page)
    data = []
    for t in items:
        leader_email = None
        if t.leader_user_id:
            leader = db.get(AppUser, t.leader_user_id)
            leader_email = leader.email if leader else None
        dept_name = None
        if t.department_id:
            dept = db.get(DeptModel, t.department_id)
            dept_name = dept.name if dept else None
        data.append({
            "id": t.id,
            "name": t.name,
            "department_id": t.department_id,
            "department_name": dept_name,
            "leader_id": t.leader_user_id,
            "leader_name": leader_email,
            "member_count": db.query(func.count(MemberAssignment.id))
            .filter(
                MemberAssignment.assignment_type == "TEAM",
                MemberAssignment.assignment_id == t.id,
                MemberAssignment.left_at.is_(None),
                MemberAssignment.deleted_at.is_(None),
            )
            .scalar() or 0,
            "created_at": t.created_at,
        })
    return paginated_response(data=data, total=total, page=page, per_page=per_page)


@router.post("/teams", summary="Create team", status_code=201)
async def create_team_endpoint(
    body: TeamCreate,
    current_user: AppUser = Depends(
        require_role("SUPER_ADMIN", "PASTOR", "DEPARTMENT_HEAD")
    ),
    db: Session = Depends(get_db),
):
    team = create_team(body, current_user, db)
    return success_response(
        data={"id": team.id, "name": team.name, "department_id": team.department_id},
        message="Team created.",
    )


@router.get("/teams/{team_id}/members", summary="List members in a team")
async def team_members_endpoint(
    team_id: uuid.UUID,
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    current_user: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    members, total = get_team_members(team_id, db, page, per_page)
    data = [{"id": m.id, "full_name": m.full_name, "phone": m.phone} for m in members]
    return paginated_response(data=data, total=total, page=page, per_page=per_page)


@router.post("/teams/{team_id}/assign-leader", summary="Assign team leader")
async def assign_team_leader_endpoint(
    team_id: uuid.UUID,
    body: AssignLeaderRequest,
    current_user: AppUser = Depends(require_role("SUPER_ADMIN", "PASTOR", "DEPARTMENT_HEAD")),
    db: Session = Depends(get_db),
):
    team = get_team(team_id, db)
    team = assign_team_leader(team, body.user_id, db)
    return success_response(data={"id": team.id, "leader_user_id": team.leader_user_id}, message="Team leader assigned.")


# ── Groups ─────────────────────────────────────────────────────────────────────

@router.get("/groups", summary="List groups (scoped)")
async def list_groups_endpoint(
    request: Request,
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    current_user: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    items, total = list_groups(db, current_user, request, page, per_page)
    data = []
    for g in items:
        leader_email = None
        if g.leader_user_id:
            leader = db.get(AppUser, g.leader_user_id)
            leader_email = leader.email if leader else None
        dept_name = None
        if g.department_id:
            dept = db.get(DeptModel, g.department_id)
            dept_name = dept.name if dept else None
        team_name = None
        if g.team_id:
            team = db.get(TeamModel, g.team_id)
            team_name = team.name if team else None
        data.append({
            "id": g.id,
            "name": g.name,
            "department_id": g.department_id,
            "department_name": dept_name,
            "team_id": g.team_id,
            "team_name": team_name,
            "leader_id": g.leader_user_id,
            "leader_name": leader_email,
            "member_count": db.query(func.count(MemberAssignment.id))
            .filter(
                MemberAssignment.assignment_type == "GROUP",
                MemberAssignment.assignment_id == g.id,
                MemberAssignment.left_at.is_(None),
                MemberAssignment.deleted_at.is_(None),
            )
            .scalar() or 0,
            "created_at": g.created_at,
        })
    return paginated_response(data=data, total=total, page=page, per_page=per_page)


@router.post("/groups", summary="Create group", status_code=201)
async def create_group_endpoint(
    body: GroupCreate,
    current_user: AppUser = Depends(
        require_role("SUPER_ADMIN", "PASTOR", "DEPARTMENT_HEAD", "TEAM_LEADER")
    ),
    db: Session = Depends(get_db),
):
    group = create_group(body, current_user, db)
    return success_response(
        data={"id": group.id, "name": group.name, "department_id": group.department_id},
        message="Group created.",
    )


@router.get("/groups/{group_id}/members", summary="List members in a group")
async def group_members_endpoint(
    group_id: uuid.UUID,
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    current_user: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    members, total = get_group_members(group_id, db, page, per_page)
    data = [{"id": m.id, "full_name": m.full_name, "phone": m.phone} for m in members]
    return paginated_response(data=data, total=total, page=page, per_page=per_page)


@router.post("/groups/{group_id}/assign-leader", summary="Assign group leader")
async def assign_group_leader_endpoint(
    group_id: uuid.UUID,
    body: AssignLeaderRequest,
    current_user: AppUser = Depends(
        require_role("SUPER_ADMIN", "PASTOR", "DEPARTMENT_HEAD", "TEAM_LEADER")
    ),
    db: Session = Depends(get_db),
):
    group = get_group(group_id, db)
    group = assign_group_leader(group, body.user_id, db)
    return success_response(data={"id": group.id, "leader_user_id": group.leader_user_id}, message="Group leader assigned.")


# ── Member Assignments ─────────────────────────────────────────────────────────

@router.post("/members/{member_id}/assign", summary="Assign member to dept/team/group", status_code=201)
async def assign_member_endpoint(
    member_id: uuid.UUID,
    body: MemberAssignRequest,
    current_user: AppUser = Depends(
        require_role("SUPER_ADMIN", "PASTOR", "DEPARTMENT_HEAD", "TEAM_LEADER", "GROUP_LEADER")
    ),
    db: Session = Depends(get_db),
):
    assignment = assign_member(member_id, body, current_user, db)
    return success_response(
        data={
            "id": assignment.id,
            "member_id": assignment.member_id,
            "assignment_type": assignment.assignment_type,
            "assignment_id": assignment.assignment_id,
            "role_in_assignment": assignment.role_in_assignment,
            "joined_at": assignment.joined_at,
        },
        message="Member assigned successfully.",
    )


@router.delete(
    "/members/{member_id}/assign/{assignment_id}",
    summary="Remove member from assignment",
)
async def remove_assignment_endpoint(
    member_id: uuid.UUID,
    assignment_id: uuid.UUID,
    current_user: AppUser = Depends(
        require_role("SUPER_ADMIN", "PASTOR", "DEPARTMENT_HEAD", "TEAM_LEADER", "GROUP_LEADER")
    ),
    db: Session = Depends(get_db),
):
    remove_assignment(member_id, assignment_id, db)
    return success_response(message="Assignment removed.")


