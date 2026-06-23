"""
Genesis Global CMS — RBAC Permission Matrix

Permission strings follow the format:
    resource:action[:qualifier]

Qualifiers:
    *       — any action on resource (wildcard)
    scoped  — allowed only within user's assigned dept/team/group
    basic   — read-only, limited field set
    self    — own record only
    own     — own patients/records only (medical domain)
    pending — create but in PENDING status

Examples:
    "members:read"          → read any member (global)
    "members:read:scoped"   → read members in own scope
    "members:create:pending"→ create members, but they land as PENDING
    "medical:*:own"         → full CRUD on own patients only
    "profile:read:self"     → read own profile only
"""
from typing import Optional

# ── Permission Registry ────────────────────────────────────────────────────────

ROLE_PERMISSIONS: dict[str, list[str]] = {
    "SUPER_ADMIN": [
        "*",  # global wildcard — access to everything
    ],
    "PASTOR": [
        "members:read",
        "members:read:scoped",
        "departments:read",
        "teams:read",
        "groups:read",
        "kpi:read",
        "attendance:read",
        "audit_logs:read",     # pastors can view audit logs
        "reports:read",
        "notifications:read",
    ],
    "FINANCE_ADMIN": [
        "sponsors:read",
        "sponsors:create",
        "sponsors:update",
        "sponsors:delete",
        "payments:read",
        "payments:create",
        "payments:update",
        "payments:delete",
        "sponsors:*",
        "payments:*",
        "reports:read:finance",
    ],
    "HR_ADMIN": [
        "workers:read",
        "workers:create",
        "workers:update",
        "workers:delete",
        "workers:*",
        "performance:read",
        "performance:create",
        "performance:update",
        "performance:delete",
        "performance:*",
        "leave:read",
        "leave:create",
        "leave:update",
        "leave:delete",
        "leave:*",
        "recognitions:*",
        "reports:read:hr",
    ],
    "DEPARTMENT_HEAD": [
        "members:read:scoped",
        "teams:read:scoped",
        "groups:read:scoped",
        "kpi:read:scoped",
        "kpi:create:scoped",
        "kpi:update:scoped",
        "kpi:*:scoped",
        "attendance:read:scoped",
        "attendance:create:scoped",
        "attendance:update:scoped",
        "attendance:*:scoped",
        "meetings:create:scoped",
        "meetings:read:scoped",
        "meetings:update:scoped",
        "departments:read:scoped",
        "follow_up:read:scoped",
        "reports:read:scoped",
    ],
    "TEAM_LEADER": [
        "members:read:scoped",
        "groups:read:scoped",
        "tasks:read:scoped",
        "tasks:create:scoped",
        "tasks:update:scoped",
        "tasks:*:scoped",
        "kpi:read:scoped",
        "attendance:read:scoped",
        "attendance:create:scoped",
        "meetings:create:scoped",
        "meetings:read:scoped",
        "follow_up:read:scoped",
    ],
    "GROUP_LEADER": [
        "members:read:scoped",
        "attendance:read:scoped",
        "attendance:create:scoped",
        "attendance:update:scoped",
        "attendance:*:scoped",
        "kpi:read:scoped",
        "meetings:create:scoped",
        "meetings:read:scoped",
    ],
    "FOLLOW_UP": [
        "members:read:basic",
        "members:create:pending",  # creates land as PENDING
        "follow_up:read",
        "follow_up:create",
        "follow_up:update",
        "follow_up:*",
        "notifications:create",
    ],
    "MEDICAL": [
        "medical:read:own",
        "medical:create:own",
        "medical:update:own",
        "medical:delete:own",
        "medical:*:own",
        "profile:read:self",
    ],
    "MEMBER": [
        "profile:read:self",
        "profile:update:self",
        "giving:read:self",
        "groups:read:self",
        "attendance:read:self",
    ],
}


# ── Permission Check ───────────────────────────────────────────────────────────

def has_permission(user_role: str, permission: str) -> bool:
    """
    Return True if the given role is authorised for the specified permission.

    Matching rules (in order):
    1. SUPER_ADMIN has "*" — always True.
    2. Exact match: "members:read:scoped" in role's list.
    3. Wildcard action: "members:*" covers "members:read".
    4. Wildcard resource+action: "*" covers everything.
    5. Qualified-to-base: if role has "members:read:scoped",
       a request for "members:read" is still allowed because having
       scoped access implies the action is permitted (just constrained).

    Args:
        user_role:  One of the UserRole enum string values.
        permission: Permission string to check.

    Returns:
        True if authorised, False otherwise.
    """
    role_perms = ROLE_PERMISSIONS.get(user_role, [])

    # Rule 1: Global wildcard
    if "*" in role_perms:
        return True

    # Rule 2: Exact match
    if permission in role_perms:
        return True

    # Parse the requested permission
    parts = permission.split(":")
    resource = parts[0]                        # e.g. "members"
    action = parts[1] if len(parts) > 1 else None  # e.g. "read"
    # qualifier = parts[2] if len(parts) > 2 else None  # e.g. "scoped"

    for perm in role_perms:
        perm_parts = perm.split(":")
        perm_resource = perm_parts[0]
        perm_action = perm_parts[1] if len(perm_parts) > 1 else None

        # Rule 3: resource-level wildcard  "members:*" or "members:*:scoped"
        if perm_resource == resource and perm_action == "*":
            return True

        # Rule 4: Base action covered by qualified permission
        # e.g. role has "members:read:scoped", request is "members:read"
        if perm_resource == resource and perm_action == action:
            return True  # qualifier is just a constraint, not a denial

    return False


def get_permission_qualifier(user_role: str, permission: str) -> Optional[str]:
    """
    Return the qualifier suffix for a permission if one exists.

    E.g. if role has "members:read:scoped", returns "scoped".
    If role has "members:read" (no qualifier), returns None.
    If role has wildcard "*", returns None (unrestricted).

    Useful for deciding whether to apply scope filters in queries.
    """
    role_perms = ROLE_PERMISSIONS.get(user_role, [])

    if "*" in role_perms:
        return None  # super admin — no qualifier

    parts = permission.split(":")
    resource = parts[0]
    action = parts[1] if len(parts) > 1 else None

    # Exact match on base permission (no qualifier)
    if permission in role_perms:
        return None

    # Search for matching permission with qualifier
    for perm in role_perms:
        perm_parts = perm.split(":")
        perm_resource = perm_parts[0]
        perm_action = perm_parts[1] if len(perm_parts) > 1 else None
        perm_qualifier = perm_parts[2] if len(perm_parts) > 2 else None

        if perm_resource == resource and (perm_action == action or perm_action == "*"):
            return perm_qualifier

    return None


# ── Field Serialization Rules ──────────────────────────────────────────────────

# Fields to STRIP from member data by role.
# Keys are UserRole values; values are sets of field names to remove.
MEMBER_FIELD_RESTRICTIONS: dict[str, set[str]] = {
    "MEDICAL": {
        "address",
        "marital_status",
        "departments",
        "teams",
        "groups",
        "salvation_date",
        "water_baptism_status",
        "holy_spirit_baptism_status",
        "sponsor_info",
        "hr_info",
        "emergency_contact",
    },
    "FINANCE_ADMIN": {
        "address",
        "marital_status",
        "gender",
        "date_of_birth",
        "departments",
        "teams",
        "groups",
        "salvation_date",
        "water_baptism_status",
        "holy_spirit_baptism_status",
        "medical_info",
        "emergency_contact",
        "email",           # finance sees only full_name + phone for linking
    },
    "HR_ADMIN": {
        "address",
        "marital_status",
        "gender",
        "date_of_birth",
        "departments",
        "teams",
        "groups",
        "salvation_date",
        "water_baptism_status",
        "holy_spirit_baptism_status",
        "medical_info",
        "sponsor_info",
        "emergency_contact",
    },
    "FOLLOW_UP": {
        "medical_info",
        "sponsor_info",
        "hr_info",
        "salvation_date",
        "water_baptism_status",
        "holy_spirit_baptism_status",
        "giving_history",
    },
    "MEMBER": {
        # Members can only view their own profile (enforced by scope)
        # If somehow a member queries another member's data, strip sensitive fields.
        "medical_info",
        "sponsor_info",
        "hr_info",
        "address",
        "date_of_birth",
        "marital_status",
        "emergency_contact",
    },
}


def strip_member_fields(member_dict: dict, user_role: str) -> dict:
    """
    Remove role-restricted fields from a member data dictionary.

    Args:
        member_dict: Raw member data as a dictionary.
        user_role:   The requesting user's role string.

    Returns:
        Filtered dictionary with restricted fields removed.
    """
    restricted = MEMBER_FIELD_RESTRICTIONS.get(user_role, set())
    if not restricted:
        return member_dict  # SUPER_ADMIN, PASTOR, DEPARTMENT_HEAD, etc. — no restrictions

    return {k: v for k, v in member_dict.items() if k not in restricted}
