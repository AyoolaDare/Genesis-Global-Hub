"""
Genesis Global CMS — FastAPI Auth Dependencies

Provides reusable dependency functions for:
  - JWT authentication (get_current_user)
  - Role-based access control (require_role)
  - Scope-based access control (require_scope)
  - Query scope filtering (ScopeFilter)
"""
import logging
import uuid
from typing import Callable, Optional

from fastapi import Depends, Request
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session, Query

from app.auth.models import AppUser, UserRole
from app.auth.permissions import has_permission
from app.core.exceptions import (
    AccountInactive,
    AuthenticationFailed,
    PermissionDenied,
    ScopeViolation,
)
from app.core.security import verify_token
from app.database import get_db

logger = logging.getLogger(__name__)

# OAuth2 scheme — reads "Authorization: Bearer <token>" header
oauth2_scheme = OAuth2PasswordBearer(
    tokenUrl="/api/v1/auth/login",
    auto_error=False,  # we raise our own exceptions
)


# ── Primary Auth Dependency ────────────────────────────────────────────────────

async def get_current_user(
    request: Request,
    token: Optional[str] = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
) -> AppUser:
    """
    FastAPI dependency: decode the JWT and load the corresponding AppUser.

    Raises:
        AuthenticationFailed: No token present.
        TokenExpired:         Token has expired.
        TokenInvalid:         Token signature/type is invalid.
        TokenBlacklisted:     Token has been revoked (post-logout).
        AccountInactive:      User account is deactivated.
    """
    if not token:
        raise AuthenticationFailed(message="Authentication credentials were not provided.")

    # verify_token raises typed exceptions on failure
    payload = verify_token(token, expected_type="access")

    user_id_str: Optional[str] = payload.get("sub")
    if not user_id_str:
        raise AuthenticationFailed(message="Token payload is missing the subject claim.")

    try:
        user_id = uuid.UUID(user_id_str)
    except ValueError:
        raise AuthenticationFailed(message="Token subject is not a valid UUID.")

    user: Optional[AppUser] = db.get(AppUser, user_id)
    if user is None:
        raise AuthenticationFailed(message="User associated with this token no longer exists.")

    if not user.is_active:
        raise AccountInactive()

    # Attach the decoded scope to the request state for downstream use
    request.state.current_user = user
    request.state.token_payload = payload

    return user


async def get_optional_user(
    request: Request,
    token: Optional[str] = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
) -> Optional[AppUser]:
    """
    Like get_current_user but returns None instead of raising if no token present.
    Used for endpoints that have optional authentication.
    """
    if not token:
        return None
    try:
        return await get_current_user(request, token, db)
    except Exception:
        return None


# ── Role-Based Access Control ──────────────────────────────────────────────────

def require_role(*roles: str) -> Callable:
    """
    Dependency factory: restrict endpoint to users with one of the specified roles.

    Usage:
        @router.get("/admin-only")
        async def admin_endpoint(user: AppUser = Depends(require_role("SUPER_ADMIN", "PASTOR"))):
            ...

    Raises:
        PermissionDenied: User's role is not in the allowed set.
    """
    role_set = set(roles)

    async def _check_role(
        current_user: AppUser = Depends(get_current_user),
    ) -> AppUser:
        if current_user.role.value not in role_set:
            raise PermissionDenied(
                message=f"This action requires one of the following roles: {', '.join(sorted(role_set))}."
            )
        return current_user

    return _check_role


def require_permission(permission: str) -> Callable:
    """
    Dependency factory: restrict endpoint to users that have a specific permission.

    Uses the RBAC matrix in permissions.py to evaluate access.

    Usage:
        @router.post("/members")
        async def create_member(user: AppUser = Depends(require_permission("members:create"))):
            ...

    Raises:
        PermissionDenied: User's role does not have the requested permission.
    """
    async def _check_permission(
        current_user: AppUser = Depends(get_current_user),
    ) -> AppUser:
        if not has_permission(current_user.role.value, permission):
            raise PermissionDenied(
                message=f"You do not have the '{permission}' permission."
            )
        return current_user

    return _check_permission


# ── Scope-Based Access Control ─────────────────────────────────────────────────

def require_scope(scope_type: str, entity_id_param: str = "entity_id") -> Callable:
    """
    Dependency factory: validate that the current user has scope over a specific
    department, team, or group.

    SUPER_ADMIN and PASTOR bypass scope checks (global access).

    Args:
        scope_type:       "departments", "teams", or "groups".
        entity_id_param:  The path parameter name containing the entity UUID.

    Usage:
        @router.get("/departments/{department_id}/members")
        async def dept_members(
            department_id: uuid.UUID,
            user: AppUser = Depends(require_scope("departments", "department_id")),
        ):
            ...

    Raises:
        ScopeViolation: User does not have access to the requested entity.
    """
    async def _check_scope(
        request: Request,
        current_user: AppUser = Depends(get_current_user),
    ) -> AppUser:
        # SUPER_ADMIN and PASTOR have global scope
        if current_user.role in (UserRole.SUPER_ADMIN, UserRole.PASTOR):
            return current_user

        # Extract entity ID from path parameters
        entity_id_str = request.path_params.get(entity_id_param)
        if not entity_id_str:
            raise ScopeViolation(message=f"Path parameter '{entity_id_param}' not found.")

        try:
            entity_id = str(uuid.UUID(str(entity_id_str)))
        except ValueError:
            raise ScopeViolation(message="Invalid entity ID format.")

        # Get scope from the token payload stored in request state
        payload = getattr(request.state, "token_payload", {})
        scope: dict = payload.get("scope", {}) or {}
        allowed_ids: list = scope.get(scope_type, [])

        if entity_id not in allowed_ids:
            raise ScopeViolation(
                message=f"You are not authorised to access this {scope_type.rstrip('s')}."
            )

        return current_user

    return _check_scope


# ── Scope Filter Helper ────────────────────────────────────────────────────────

class ScopeFilter:
    """
    Helper class to apply scope-based WHERE filters to SQLAlchemy queries.

    Usage:
        query = db.query(Member)
        filtered = ScopeFilter.filter_by_department(query, current_user, request)
    """

    @staticmethod
    def _get_scope(request: Request) -> dict:
        payload = getattr(request.state, "token_payload", {})
        return payload.get("scope", {}) or {}

    @staticmethod
    def is_global_role(user: AppUser) -> bool:
        """Return True for roles that have unrestricted access."""
        return user.role in (
            UserRole.SUPER_ADMIN,
            UserRole.PASTOR,
            UserRole.FINANCE_ADMIN,
            UserRole.HR_ADMIN,
        )

    @classmethod
    def filter_members_by_scope(
        cls,
        query: Query,
        user: AppUser,
        request: Request,
    ) -> Query:
        """
        Filter a members query to the entities within the user's scope.

        For global roles: no filter applied.
        For scoped roles: filters by member_assignments to authorised
                          departments, teams, or groups.
        """
        if cls.is_global_role(user):
            return query

        scope = cls._get_scope(request)
        dept_ids = scope.get("departments", [])
        team_ids = scope.get("teams", [])
        group_ids = scope.get("groups", [])

        if not any([dept_ids, team_ids, group_ids]):
            # No scope at all — return empty result set
            return query.filter(False)

        from sqlalchemy import and_, exists, or_
        from app.models.structure import MemberAssignment

        conditions = []
        if dept_ids:
            conditions.append(
                and_(
                    MemberAssignment.assignment_type == "DEPARTMENT",
                    MemberAssignment.assignment_id.in_(
                        [uuid.UUID(str(entity_id)) for entity_id in dept_ids]
                    ),
                )
            )
        if team_ids:
            conditions.append(
                and_(
                    MemberAssignment.assignment_type == "TEAM",
                    MemberAssignment.assignment_id.in_(
                        [uuid.UUID(str(entity_id)) for entity_id in team_ids]
                    ),
                )
            )
        if group_ids:
            conditions.append(
                and_(
                    MemberAssignment.assignment_type == "GROUP",
                    MemberAssignment.assignment_id.in_(
                        [uuid.UUID(str(entity_id)) for entity_id in group_ids]
                    ),
                )
            )

        return query.filter(
            exists()
            .where(MemberAssignment.member_id == query.column_descriptions[0]["entity"].id)
            .where(or_(*conditions))
        )

    @classmethod
    def filter_by_department(
        cls,
        query: Query,
        user: AppUser,
        request: Request,
    ) -> Query:
        """Filter any query that has a ``department_id`` column to authorised departments."""
        if cls.is_global_role(user):
            return query

        scope = cls._get_scope(request)
        dept_ids = scope.get("departments", [])

        if not dept_ids:
            return query.filter(False)

        return query.filter(
            query.column_descriptions[0]["entity"].department_id.in_(dept_ids)
        )

    @classmethod
    def filter_by_team(
        cls,
        query: Query,
        user: AppUser,
        request: Request,
    ) -> Query:
        """Filter any query with a ``team_id`` column to authorised teams."""
        if cls.is_global_role(user):
            return query

        scope = cls._get_scope(request)
        team_ids = scope.get("teams", [])

        if not team_ids:
            return query.filter(False)

        return query.filter(
            query.column_descriptions[0]["entity"].team_id.in_(team_ids)
        )

    @classmethod
    def filter_by_group(
        cls,
        query: Query,
        user: AppUser,
        request: Request,
    ) -> Query:
        """Filter any query with a ``group_id`` column to authorised groups."""
        if cls.is_global_role(user):
            return query

        scope = cls._get_scope(request)
        group_ids = scope.get("groups", [])

        if not group_ids:
            return query.filter(False)

        return query.filter(
            query.column_descriptions[0]["entity"].group_id.in_(group_ids)
        )


# ── Convenience: Admin-Only Dependency ────────────────────────────────────────

require_super_admin = require_role("SUPER_ADMIN")
require_admin_or_pastor = require_role("SUPER_ADMIN", "PASTOR")
require_finance = require_role("SUPER_ADMIN", "FINANCE_ADMIN")
require_hr = require_role("SUPER_ADMIN", "HR_ADMIN")
require_medical = require_role("SUPER_ADMIN", "MEDICAL")
