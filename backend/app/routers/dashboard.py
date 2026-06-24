"""
Genesis Global CMS — Dashboard Router

Endpoints:
  GET /dashboard/admin       Admin/Pastor overview stats
"""
from datetime import date, timedelta

from fastapi import APIRouter, Depends
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.auth.dependencies import require_role
from app.auth.models import AppUser
from app.core.responses import success_response
from app.database import get_db
from app.models.follow_up import FollowUpTask
from app.models.member import MemberModel, MemberStatusEnum
from app.models.structure import Department, Group, Team

router = APIRouter(prefix="/dashboard", tags=["Dashboard"])


@router.get("/admin")
def admin_dashboard(
    db: Session = Depends(get_db),
    current_user: AppUser = Depends(require_role("SUPER_ADMIN", "PASTOR")),
):
    today = date.today()

    total_members = (
        db.query(func.count(MemberModel.id))
        .filter(MemberModel.deleted_at.is_(None))
        .scalar() or 0
    )
    active_members = (
        db.query(func.count(MemberModel.id))
        .filter(
            MemberModel.deleted_at.is_(None),
            MemberModel.membership_status == MemberStatusEnum.ACTIVE,
        )
        .scalar() or 0
    )
    pending_approvals = (
        db.query(func.count(MemberModel.id))
        .filter(
            MemberModel.deleted_at.is_(None),
            MemberModel.membership_status == MemberStatusEnum.PENDING,
        )
        .scalar() or 0
    )
    total_departments = (
        db.query(func.count(Department.id))
        .filter(Department.deleted_at.is_(None))
        .scalar() or 0
    )
    total_teams = (
        db.query(func.count(Team.id))
        .filter(Team.deleted_at.is_(None))
        .scalar() or 0
    )
    total_groups = (
        db.query(func.count(Group.id))
        .filter(Group.deleted_at.is_(None))
        .scalar() or 0
    )
    follow_up_tasks = (
        db.query(func.count(FollowUpTask.id))
        .filter(
            FollowUpTask.deleted_at.is_(None),
            FollowUpTask.completed_at.is_(None),
        )
        .scalar() or 0
    )
    today_follow_ups = (
        db.query(func.count(FollowUpTask.id))
        .filter(
            FollowUpTask.deleted_at.is_(None),
            FollowUpTask.completed_at.is_(None),
            func.date(FollowUpTask.due_date) == today,
        )
        .scalar() or 0
    )

    # Member growth: new members per month for the last 6 months
    member_growth = []
    for i in range(5, -1, -1):
        month_start = (today.replace(day=1) - timedelta(days=i * 28)).replace(day=1)
        if month_start.month == 12:
            month_end = month_start.replace(year=month_start.year + 1, month=1, day=1)
        else:
            month_end = month_start.replace(month=month_start.month + 1, day=1)
        count = (
            db.query(func.count(MemberModel.id))
            .filter(
                MemberModel.deleted_at.is_(None),
                func.date(MemberModel.created_at) >= month_start,
                func.date(MemberModel.created_at) < month_end,
            )
            .scalar() or 0
        )
        member_growth.append({
            "label": month_start.strftime("%b"),
            "value": count,
        })

    return success_response(
        data={
            "total_members": total_members,
            "active_members": active_members,
            "pending_approvals": pending_approvals,
            "total_departments": total_departments,
            "total_teams": total_teams,
            "total_groups": total_groups,
            "follow_up_tasks": follow_up_tasks,
            "today_follow_ups": today_follow_ups,
            "member_growth": member_growth,
            "attendance_trend": [],
        },
        message="Dashboard data loaded.",
    )
