"""
Genesis Global CMS — Structure Service

Business logic for departments, teams, groups, and member assignments.
"""
import uuid
from datetime import datetime, timezone

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.auth.models import AppUser, UserRole
from app.core.exceptions import DuplicateRecord, NotFound, PermissionDenied
from app.models.member import MemberModel
from app.models.structure import Department, Group, MemberAssignment, Team
from app.schemas.structure import (
    DepartmentCreate,
    DepartmentUpdate,
    GroupCreate,
    GroupUpdate,
    MemberAssignRequest,
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
    # Verify dept exists
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
    dept = db.query(Department).filter(
        Department.id == data.department_id, Department.deleted_at.is_(None)
    ).first()
    if not dept:
        raise NotFound(message=f"Department {data.department_id} not found.")

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
