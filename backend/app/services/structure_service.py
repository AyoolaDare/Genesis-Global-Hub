"""
Genesis Global CMS — Structure Service

Business logic for departments, teams, groups, and member assignments.
"""
import uuid
from datetime import datetime, timezone
from secrets import token_urlsafe

import httpx
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.auth.models import AppUser, UserRole
from app.config import settings
from app.core.exceptions import DuplicateRecord, NotFound, PermissionDenied
from app.models.member import MemberModel
from app.models.structure import Department, Group, MemberAssignment, Team
from app.schemas.structure import (
    DepartmentCreate,
    DepartmentUpdate,
    GroupCreate,
    GroupUpdate,
    MemberAssignRequest,
    PortalAccessRequest,
    TeamCreate,
    TeamUpdate,
)


# ── Department Service ─────────────────────────────────────────────────────────

def list_departments(db: Session, page: int = 1, per_page: int = 20) -> tuple[list[Department], int]:
    query = db.query(Department).filter(Department.deleted_at.is_(None)).order_by(Department.name)
    total = query.count()
    items = query.offset((page - 1) * per_page).limit(per_page).all()
    return items, total


def get_department(dept_id: uuid.UUID, db: Session) -> Department:
    dept = db.query(Department).filter(
        Department.id == dept_id, Department.deleted_at.is_(None)
    ).first()
    if not dept:
        raise NotFound(message=f"Department {dept_id} not found.")
    return dept


def create_department(data: DepartmentCreate, current_user: AppUser, db: Session) -> Department:
    dept = Department(
        name=data.name,
        description=data.description,
        head_user_id=data.head_user_id,
    )
    try:
        db.add(dept)
        db.flush()
    except IntegrityError:
        db.rollback()
        raise DuplicateRecord(message=f"Department '{data.name}' already exists.")
    return dept


def update_department(
    dept: Department,
    data: DepartmentUpdate,
    current_user: AppUser,
    db: Session,
) -> Department:
    # Scoped dept heads can only update their own dept
    if current_user.role == UserRole.DEPARTMENT_HEAD and dept.head_user_id != current_user.id:
        raise PermissionDenied(message="You can only update your own department.")

    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(dept, field, value)

    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        raise DuplicateRecord(message="Department name already in use.")
    return dept


def assign_department_head(dept: Department, user_id: uuid.UUID, db: Session) -> Department:
    dept.head_user_id = user_id
    db.flush()
    return dept


def get_department_members(
    dept_id: uuid.UUID,
    db: Session,
    page: int = 1,
    per_page: int = 20,
) -> tuple[list[MemberModel], int]:
    query = (
        db.query(MemberModel)
        .join(
            MemberAssignment,
            (MemberAssignment.member_id == MemberModel.id)
            & (MemberAssignment.assignment_type == "DEPARTMENT")
            & (MemberAssignment.assignment_id == dept_id)
            & MemberAssignment.deleted_at.is_(None),
        )
        .filter(MemberModel.deleted_at.is_(None))
        .order_by(MemberModel.full_name)
    )
    total = query.count()
    members = query.offset((page - 1) * per_page).limit(per_page).all()
    return members, total


# ── Team Service ───────────────────────────────────────────────────────────────

def list_teams(
    db: Session,
    current_user: AppUser,
    request,
    page: int = 1,
    per_page: int = 20,
) -> tuple[list[Team], int]:
    query = db.query(Team).filter(Team.deleted_at.is_(None))

    # Scoped filtering for dept heads
    if current_user.role == UserRole.DEPARTMENT_HEAD:
        payload = getattr(request.state, "token_payload", {})
        scope = payload.get("scope", {}) or {}
        dept_ids = scope.get("departments", [])
        if dept_ids:
            query = query.filter(Team.department_id.in_(dept_ids))
        else:
            query = query.filter(False)

    query = query.order_by(Team.name)
    total = query.count()
    items = query.offset((page - 1) * per_page).limit(per_page).all()
    return items, total


def get_team(team_id: uuid.UUID, db: Session) -> Team:
    team = db.query(Team).filter(Team.id == team_id, Team.deleted_at.is_(None)).first()
    if not team:
        raise NotFound(message=f"Team {team_id} not found.")
    return team


def create_team(data: TeamCreate, current_user: AppUser, db: Session) -> Team:
    if data.department_id is not None:
        dept = db.query(Department).filter(
            Department.id == data.department_id, Department.deleted_at.is_(None)
        ).first()
        if not dept:
            raise NotFound(message=f"Department {data.department_id} not found.")

    team = Team(
        name=data.name,
        department_id=data.department_id,
        leader_user_id=data.leader_user_id,
    )
    try:
        db.add(team)
        db.flush()
    except IntegrityError:
        db.rollback()
        raise DuplicateRecord(message=f"Team '{data.name}' already exists in this department.")
    return team


def update_team(team: Team, data: TeamUpdate, db: Session) -> Team:
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(team, field, value)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        raise DuplicateRecord(message="Team name already in use in this department.")
    return team


def assign_team_leader(team: Team, user_id: uuid.UUID, db: Session) -> Team:
    team.leader_user_id = user_id
    db.flush()
    return team


def get_team_members(
    team_id: uuid.UUID,
    db: Session,
    page: int = 1,
    per_page: int = 20,
) -> tuple[list[MemberModel], int]:
    query = (
        db.query(MemberModel)
        .join(
            MemberAssignment,
            (MemberAssignment.member_id == MemberModel.id)
            & (MemberAssignment.assignment_type == "TEAM")
            & (MemberAssignment.assignment_id == team_id)
            & MemberAssignment.deleted_at.is_(None),
        )
        .filter(MemberModel.deleted_at.is_(None))
        .order_by(MemberModel.full_name)
    )
    total = query.count()
    members = query.offset((page - 1) * per_page).limit(per_page).all()
    return members, total


# ── Group Service ──────────────────────────────────────────────────────────────

def list_groups(
    db: Session,
    current_user: AppUser,
    request,
    page: int = 1,
    per_page: int = 20,
) -> tuple[list[Group], int]:
    query = db.query(Group).filter(Group.deleted_at.is_(None))

    if current_user.role in (UserRole.DEPARTMENT_HEAD, UserRole.TEAM_LEADER):
        payload = getattr(request.state, "token_payload", {})
        scope = payload.get("scope", {}) or {}
        dept_ids = scope.get("departments", [])
        team_ids = scope.get("teams", [])
        if dept_ids or team_ids:
            from sqlalchemy import or_
            conditions = []
            if dept_ids:
                conditions.append(Group.department_id.in_(dept_ids))
            if team_ids:
                conditions.append(Group.team_id.in_(team_ids))
            query = query.filter(or_(*conditions))
        else:
            query = query.filter(False)

    query = query.order_by(Group.name)
    total = query.count()
    items = query.offset((page - 1) * per_page).limit(per_page).all()
    return items, total


def get_group(group_id: uuid.UUID, db: Session) -> Group:
    group = db.query(Group).filter(Group.id == group_id, Group.deleted_at.is_(None)).first()
    if not group:
        raise NotFound(message=f"Group {group_id} not found.")
    return group


def create_group(data: GroupCreate, current_user: AppUser, db: Session) -> Group:
    if data.department_id is not None:
        dept = db.query(Department).filter(
            Department.id == data.department_id, Department.deleted_at.is_(None)
        ).first()
        if not dept:
            raise NotFound(message=f"Department {data.department_id} not found.")

    if data.team_id is not None:
        team = db.query(Team).filter(
            Team.id == data.team_id, Team.deleted_at.is_(None)
        ).first()
        if not team:
            raise NotFound(message=f"Team {data.team_id} not found.")

    group = Group(
        name=data.name,
        department_id=data.department_id,
        team_id=data.team_id,
        leader_user_id=data.leader_user_id,
    )
    db.add(group)
    db.flush()
    return group


def update_group(group: Group, data: GroupUpdate, db: Session) -> Group:
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(group, field, value)
    db.flush()
    return group


def assign_group_leader(group: Group, user_id: uuid.UUID, db: Session) -> Group:
    group.leader_user_id = user_id
    db.flush()
    return group


def get_group_members(
    group_id: uuid.UUID,
    db: Session,
    page: int = 1,
    per_page: int = 20,
) -> tuple[list[MemberModel], int]:
    query = (
        db.query(MemberModel)
        .join(
            MemberAssignment,
            (MemberAssignment.member_id == MemberModel.id)
            & (MemberAssignment.assignment_type == "GROUP")
            & (MemberAssignment.assignment_id == group_id)
            & MemberAssignment.deleted_at.is_(None),
        )
        .filter(MemberModel.deleted_at.is_(None))
        .order_by(MemberModel.full_name)
    )
    total = query.count()
    members = query.offset((page - 1) * per_page).limit(per_page).all()
    return members, total


# ── Member Assignment Service ──────────────────────────────────────────────────

def assign_member(
    member_id: uuid.UUID,
    data: MemberAssignRequest,
    current_user: AppUser,
    db: Session,
) -> MemberAssignment:
    """Assign a member to a department, team, or group."""
    # Verify member exists
    member = db.query(MemberModel).filter(
        MemberModel.id == member_id, MemberModel.deleted_at.is_(None)
    ).first()
    if not member:
        raise NotFound(message=f"Member {member_id} not found.")

    # Verify the target entity exists
    if data.assignment_type == "DEPARTMENT":
        entity = db.query(Department).filter(
            Department.id == data.assignment_id, Department.deleted_at.is_(None)
        ).first()
        if not entity:
            raise NotFound(message=f"Department {data.assignment_id} not found.")
    elif data.assignment_type == "TEAM":
        entity = db.query(Team).filter(
            Team.id == data.assignment_id, Team.deleted_at.is_(None)
        ).first()
        if not entity:
            raise NotFound(message=f"Team {data.assignment_id} not found.")
    else:  # GROUP
        entity = db.query(Group).filter(
            Group.id == data.assignment_id, Group.deleted_at.is_(None)
        ).first()
        if not entity:
            raise NotFound(message=f"Group {data.assignment_id} not found.")

    # Check for existing active assignment
    existing = db.query(MemberAssignment).filter(
        MemberAssignment.member_id == member_id,
        MemberAssignment.assignment_type == data.assignment_type,
        MemberAssignment.assignment_id == data.assignment_id,
        MemberAssignment.deleted_at.is_(None),
        MemberAssignment.left_at.is_(None),
    ).first()
    if existing:
        raise DuplicateRecord(
            message=f"Member is already assigned to this {data.assignment_type.lower()}."
        )

    assignment = MemberAssignment(
        member_id=member_id,
        assignment_type=data.assignment_type,
        assignment_id=data.assignment_id,
        role_in_assignment=data.role_in_assignment,
        joined_at=datetime.now(timezone.utc),
    )
    db.add(assignment)
    db.flush()
    return assignment


def get_member_assignments(member_id: uuid.UUID, db: Session) -> list[dict]:
    """
    Return a member's active unit assignments with resolved unit names,
    for display on the member detail screen.
    """
    member = db.query(MemberModel).filter(
        MemberModel.id == member_id, MemberModel.deleted_at.is_(None)
    ).first()
    if not member:
        raise NotFound(message=f"Member {member_id} not found.")

    assignments = db.query(MemberAssignment).filter(
        MemberAssignment.member_id == member_id,
        MemberAssignment.deleted_at.is_(None),
        MemberAssignment.left_at.is_(None),
    ).order_by(MemberAssignment.joined_at.desc()).all()

    names: dict[uuid.UUID, str] = {}
    by_type = {
        "DEPARTMENT": (Department, [a.assignment_id for a in assignments if a.assignment_type == "DEPARTMENT"]),
        "TEAM": (Team, [a.assignment_id for a in assignments if a.assignment_type == "TEAM"]),
        "GROUP": (Group, [a.assignment_id for a in assignments if a.assignment_type == "GROUP"]),
    }
    for model, ids in by_type.values():
        if ids:
            for row in db.query(model.id, model.name).filter(model.id.in_(ids)).all():
                names[row.id] = row.name

    return [
        {
            "id": a.id,
            "assignment_type": a.assignment_type,
            "assignment_id": a.assignment_id,
            "entity_name": names.get(a.assignment_id, "Unknown"),
            "role_in_assignment": a.role_in_assignment,
            "joined_at": a.joined_at,
        }
        for a in assignments
    ]


def remove_assignment(
    member_id: uuid.UUID,
    assignment_id: uuid.UUID,
    db: Session,
) -> None:
    """Soft-remove a member assignment."""
    assignment = db.query(MemberAssignment).filter(
        MemberAssignment.id == assignment_id,
        MemberAssignment.member_id == member_id,
        MemberAssignment.deleted_at.is_(None),
    ).first()
    if not assignment:
        raise NotFound(message=f"Assignment {assignment_id} not found.")

    assignment.left_at = datetime.now(timezone.utc)
    assignment.deleted_at = datetime.now(timezone.utc)
    db.flush()


# ── Portal Access Service ──────────────────────────────────────────────────────

_PORTAL_ROLES = {
    UserRole.FOLLOW_UP,
    UserRole.MEDICAL,
    UserRole.FINANCE_ADMIN,
    UserRole.HR_ADMIN,
    UserRole.DEPARTMENT_HEAD,
    UserRole.TEAM_LEADER,
    UserRole.GROUP_LEADER,
}


def _serialize_portal_user(user: AppUser | None) -> dict | None:
    if user is None:
        return None
    return {
        "id": user.id,
        "email": user.email,
        "role": user.role.value,
        "member_id": user.member_id,
        "is_active": user.is_active,
        "last_login_at": user.last_login_at,
    }


def get_member_portal_access(member_id: uuid.UUID, db: Session) -> dict | None:
    user = db.query(AppUser).filter(AppUser.member_id == member_id).first()
    return _serialize_portal_user(user)


def _get_existing_supabase_user_id(email: str) -> uuid.UUID:
    url = f"{settings.SUPABASE_URL}/auth/v1/admin/users"
    headers = {
        "apikey": settings.SUPABASE_SERVICE_KEY,
        "Authorization": f"Bearer {settings.SUPABASE_SERVICE_KEY}",
    }
    response = httpx.get(
        url,
        headers=headers,
        params={"page": 1, "per_page": 1000},
        timeout=15.0,
    )
    if response.status_code != 200:
        raise PermissionDenied(message="Could not verify existing auth user.")

    for user in response.json().get("users", []):
        if user.get("email", "").lower() == email.lower():
            return uuid.UUID(user["id"])

    raise NotFound(message=f"Auth user for {email} not found.")


def _supabase_create_or_get_user(email: str, password: str) -> uuid.UUID:
    if not settings.SUPABASE_SERVICE_KEY:
        raise PermissionDenied(message="Supabase service key is not configured.")

    url = f"{settings.SUPABASE_URL}/auth/v1/admin/users"
    headers = {
        "apikey": settings.SUPABASE_SERVICE_KEY,
        "Authorization": f"Bearer {settings.SUPABASE_SERVICE_KEY}",
        "Content-Type": "application/json",
    }
    payload = {
        "email": email,
        "password": password,
        "email_confirm": True,
    }
    response = httpx.post(url, json=payload, headers=headers, timeout=15.0)

    if response.status_code in (200, 201):
        return uuid.UUID(response.json()["id"])

    if response.status_code == 422:
        message = response.text.lower()
        if "registered" in message or "exists" in message:
            return _get_existing_supabase_user_id(email)

    raise PermissionDenied(message="Could not create portal login in Supabase Auth.")


def grant_member_portal_access(
    member_id: uuid.UUID,
    data: PortalAccessRequest,
    db: Session,
) -> tuple[dict, str | None]:
    member = db.query(MemberModel).filter(
        MemberModel.id == member_id,
        MemberModel.deleted_at.is_(None),
    ).first()
    if not member:
        raise NotFound(message=f"Member {member_id} not found.")

    portal_role = UserRole(data.role)
    if portal_role not in _PORTAL_ROLES:
        raise PermissionDenied(message="This role cannot be assigned as a member portal.")

    email = data.email.strip().lower()
    generated_password = None
    password = data.temporary_password
    existing_for_member = db.query(AppUser).filter(AppUser.member_id == member_id).first()

    if existing_for_member is None:
        if password is None:
            generated_password = token_urlsafe(12)
            password = generated_password
        user_id = _supabase_create_or_get_user(email, password)
        user = db.get(AppUser, user_id)
        if user is None:
            user = AppUser(
                id=user_id,
                email=email,
                role=portal_role,
                member_id=member_id,
                is_active=True,
            )
            db.add(user)
        else:
            user.email = email
            user.role = portal_role
            user.member_id = member_id
            user.is_active = True
    else:
        user = existing_for_member
        user.email = email
        user.role = portal_role
        user.is_active = True

    db.flush()
    return _serialize_portal_user(user), generated_password


def revoke_member_portal_access(member_id: uuid.UUID, db: Session) -> None:
    user = db.query(AppUser).filter(AppUser.member_id == member_id).first()
    if not user:
        raise NotFound(message=f"Portal access for member {member_id} not found.")
    user.is_active = False
    db.flush()
