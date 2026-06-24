"""
Genesis Global CMS — Test Utility Helpers

Factory functions for creating test data directly in the database.
All functions accept an active SQLAlchemy session and optional overrides.
"""
import uuid
from datetime import date, datetime, timedelta, timezone
from typing import Optional

from sqlalchemy.orm import Session

from app.auth.models import AppUser, UserRole
from app.core.security import create_access_token
from app.models.attendance import Meeting, MeetingTypeEnum, AttendanceRecord, AttendanceStatusEnum
from app.models.follow_up import FollowUpContact, FollowUpTask, FollowUpStageEnum
from app.models.hr import Worker, EmploymentTypeEnum
from app.models.kpi import KpiDefinition, KpiRecord, KpiPeriodEnum
from app.models.medical import MedicalPatient, MedicalVisit
from app.models.member import MemberModel, MemberStatusEnum
from app.models.sponsor import Sponsor, SponsorPayment, SponsorshipTierEnum, PaymentStatusEnum, PaymentMethodEnum, PreferredChannelEnum
from app.models.structure import Department, Team, Group


# ── Token Helpers ──────────────────────────────────────────────────────────────

def auth_headers(token: str) -> dict:
    """Return Authorization header dict for a given JWT token."""
    return {"Authorization": f"Bearer {token}"}


def create_token_for_role(role: str, scope: dict = None, user_id: str = None) -> str:
    """Create a signed JWT for an arbitrary role without a real DB user."""
    uid = user_id or str(uuid.uuid4())
    return create_access_token({
        "sub": uid,
        "email": f"{role.lower()}@token.test",
        "role": role,
        "scope": scope or {"departments": [], "teams": [], "groups": []},
    })


def create_token_for(user: AppUser, scope: dict = None) -> str:
    """Create a JWT for a real AppUser instance."""
    return create_access_token({
        "sub": str(user.id),
        "email": user.email,
        "role": user.role.value,
        "scope": scope or {"departments": [], "teams": [], "groups": []},
    })


# ── AppUser Factories ──────────────────────────────────────────────────────────

def create_user(db: Session, email: str, role: UserRole = UserRole.MEMBER, **kwargs) -> AppUser:
    user = AppUser(
        id=kwargs.pop("id", uuid.uuid4()),
        email=email,
        role=role,
        is_active=kwargs.pop("is_active", True),
        **kwargs,
    )
    db.add(user)
    db.flush()
    return user


def create_medical_user(db: Session, email: str = None) -> AppUser:
    email = email or f"medical-{uuid.uuid4().hex[:6]}@test.com"
    return create_user(db, email, UserRole.MEDICAL)


def create_follow_up_user(db: Session, email: str = None) -> AppUser:
    email = email or f"followup-{uuid.uuid4().hex[:6]}@test.com"
    return create_user(db, email, UserRole.FOLLOW_UP)


# ── Member Factories ───────────────────────────────────────────────────────────

def create_member(
    db: Session,
    full_name: str = "Test Member",
    phone: str = None,
    email: str = None,
    status: MemberStatusEnum = MemberStatusEnum.ACTIVE,
    submitted_by: uuid.UUID = None,
    **kwargs,
) -> MemberModel:
    member = MemberModel(
        id=kwargs.pop("id", uuid.uuid4()),
        full_name=full_name,
        phone=phone or f"080{uuid.uuid4().int % 100000000:08d}",
        email=email,
        membership_status=status,
        submitted_by=submitted_by,
        **kwargs,
    )
    db.add(member)
    db.flush()
    return member


def create_pending_member(db: Session, full_name: str = "Pending Member", submitted_by: uuid.UUID = None) -> MemberModel:
    return create_member(db, full_name=full_name, status=MemberStatusEnum.PENDING, submitted_by=submitted_by)


def create_active_member(db: Session, full_name: str = "Active Member", phone: str = None) -> MemberModel:
    return create_member(db, full_name=full_name, phone=phone, status=MemberStatusEnum.ACTIVE)


# ── Medical Patient Factories ──────────────────────────────────────────────────

def create_patient(
    db: Session,
    created_by: uuid.UUID,
    full_name: str = "Test Patient",
    phone: str = None,
    is_church_member: bool = False,
    **kwargs,
) -> MedicalPatient:
    patient = MedicalPatient(
        id=kwargs.pop("id", uuid.uuid4()),
        full_name=full_name,
        phone=phone or f"081{uuid.uuid4().int % 100000000:08d}",
        is_church_member=is_church_member,
        consent_given=True,
        created_by=created_by,
        **kwargs,
    )
    db.add(patient)
    db.flush()
    return patient


def create_medical_visit(
    db: Session,
    patient_id: uuid.UUID,
    attended_by: uuid.UUID,
    visit_date: date = None,
) -> MedicalVisit:
    visit = MedicalVisit(
        id=uuid.uuid4(),
        patient_id=patient_id,
        visit_date=visit_date or date.today(),
        complaints="Test complaint",
        diagnosis="Test diagnosis",
        treatment="Test treatment",
        attended_by=attended_by,
    )
    db.add(visit)
    db.flush()
    return visit


# ── Sponsor Factories ──────────────────────────────────────────────────────────

def create_sponsor(
    db: Session,
    full_name: str = "Test Sponsor",
    amount: float = 50000.0,
    created_by: uuid.UUID = None,
    **kwargs,
) -> Sponsor:
    sponsor = Sponsor(
        id=kwargs.pop("id", uuid.uuid4()),
        full_name=full_name,
        email=f"sponsor-{uuid.uuid4().hex[:6]}@test.com",
        phone="08099887766",
        sponsorship_tier=kwargs.pop("sponsorship_tier", SponsorshipTierEnum.MONTHLY),
        amount=amount,
        preferred_channel=kwargs.pop("preferred_channel", PreferredChannelEnum.EMAIL),
        is_active=True,
        created_by=created_by,
        **kwargs,
    )
    db.add(sponsor)
    db.flush()
    return sponsor


def create_sponsor_payment(
    db: Session,
    sponsor_id: uuid.UUID,
    amount: float = 50000.0,
    status: PaymentStatusEnum = PaymentStatusEnum.COMPLETED,
    **kwargs,
) -> SponsorPayment:
    payment = SponsorPayment(
        id=uuid.uuid4(),
        sponsor_id=sponsor_id,
        amount=amount,
        status=status,
        payment_method=PaymentMethodEnum.CASH,
        **kwargs,
    )
    db.add(payment)
    db.flush()
    return payment


# ── Structure Factories ────────────────────────────────────────────────────────

def create_department(db: Session, name: str = None, head_user_id: uuid.UUID = None) -> Department:
    dept = Department(
        id=uuid.uuid4(),
        name=name or f"Department-{uuid.uuid4().hex[:6]}",
        head_user_id=head_user_id,
    )
    db.add(dept)
    db.flush()
    return dept


def create_team(db: Session, department_id: uuid.UUID, name: str = None, leader_user_id: uuid.UUID = None) -> Team:
    team = Team(
        id=uuid.uuid4(),
        name=name or f"Team-{uuid.uuid4().hex[:6]}",
        department_id=department_id,
        leader_user_id=leader_user_id,
    )
    db.add(team)
    db.flush()
    return team


def create_group(db: Session, department_id: uuid.UUID, team_id: uuid.UUID = None, name: str = None) -> Group:
    group = Group(
        id=uuid.uuid4(),
        name=name or f"Group-{uuid.uuid4().hex[:6]}",
        department_id=department_id,
        team_id=team_id,
    )
    db.add(group)
    db.flush()
    return group


# ── Follow-Up Factories ────────────────────────────────────────────────────────

def create_follow_up_contact(
    db: Session,
    registered_by: uuid.UUID,
    full_name: str = "Jane Convert",
    phone: str = None,
) -> FollowUpContact:
    contact = FollowUpContact(
        id=uuid.uuid4(),
        full_name=full_name,
        phone=phone or "08012345678",
        address="123 Faith Street",
        registered_by=registered_by,
    )
    db.add(contact)
    db.flush()
    return contact


def create_follow_up_task(
    db: Session,
    contact_id: uuid.UUID,
    assigned_to: uuid.UUID,
    stage: FollowUpStageEnum = FollowUpStageEnum.FIRST_CONTACT,
    due_date: datetime = None,
) -> FollowUpTask:
    task = FollowUpTask(
        id=uuid.uuid4(),
        contact_id=contact_id,
        assigned_to=assigned_to,
        stage=stage,
        due_date=due_date or (datetime.now(timezone.utc) + timedelta(days=1)),
    )
    db.add(task)
    db.flush()
    return task


def create_task_due_today(db: Session, assigned_to: uuid.UUID, contact_id: uuid.UUID) -> FollowUpTask:
    now = datetime.now(timezone.utc)
    due = now.replace(hour=23, minute=59, second=59)
    return create_follow_up_task(db, contact_id=contact_id, assigned_to=assigned_to, due_date=due)


def create_overdue_task(db: Session, assigned_to: uuid.UUID, contact_id: uuid.UUID, hours_overdue: int = 48) -> FollowUpTask:
    due = datetime.now(timezone.utc) - timedelta(hours=hours_overdue)
    return create_follow_up_task(db, contact_id=contact_id, assigned_to=assigned_to, due_date=due)


# ── Attendance Factories ───────────────────────────────────────────────────────

def create_meeting(
    db: Session,
    created_by: uuid.UUID,
    title: str = "Test Meeting",
    meeting_date: date = None,
    meeting_type: str = "GROUP",
    entity_id: uuid.UUID = None,
) -> Meeting:
    meeting = Meeting(
        id=uuid.uuid4(),
        title=title,
        meeting_date=meeting_date or date.today(),
        meeting_type=meeting_type,
        entity_id=entity_id or uuid.uuid4(),
        created_by=created_by,
    )
    db.add(meeting)
    db.flush()
    return meeting


def create_attendance_record(
    db: Session,
    meeting_id: uuid.UUID,
    member_id: uuid.UUID,
    marked_by: uuid.UUID,
    status: AttendanceStatusEnum = AttendanceStatusEnum.PRESENT,
) -> AttendanceRecord:
    record = AttendanceRecord(
        id=uuid.uuid4(),
        meeting_id=meeting_id,
        member_id=member_id,
        status=status,
        marked_by=marked_by,
        marked_at=datetime.now(timezone.utc),
    )
    db.add(record)
    db.flush()
    return record


# ── KPI Factories ──────────────────────────────────────────────────────────────

def create_kpi_definition(
    db: Session,
    created_by: uuid.UUID,
    entity_type: str = "DEPARTMENT",
    entity_id: uuid.UUID = None,
    target_value: float = 40.0,
    name: str = "Test KPI",
    period: KpiPeriodEnum = KpiPeriodEnum.MONTHLY,
) -> KpiDefinition:
    kpi = KpiDefinition(
        id=uuid.uuid4(),
        name=name,
        entity_type=entity_type,
        entity_id=entity_id or uuid.uuid4(),
        target_value=target_value,
        target_unit="count",
        period=period,
        is_active=True,
        created_by=created_by,
    )
    db.add(kpi)
    db.flush()
    return kpi


def create_kpi_record(
    db: Session,
    kpi_definition_id: uuid.UUID,
    recorded_by: uuid.UUID,
    actual_value: float = 35.0,
    period_start: date = None,
    period_end: date = None,
) -> KpiRecord:
    ps = period_start or date(2024, 1, 1)
    pe = period_end or date(2024, 1, 31)
    record = KpiRecord(
        id=uuid.uuid4(),
        kpi_definition_id=kpi_definition_id,
        period_start=ps,
        period_end=pe,
        actual_value=actual_value,
        recorded_by=recorded_by,
    )
    db.add(record)
    db.flush()
    return record


# ── HR Worker Factories ────────────────────────────────────────────────────────

def create_worker(
    db: Session,
    created_by: uuid.UUID,
    full_name: str = "Test Worker",
    employment_type: EmploymentTypeEnum = EmploymentTypeEnum.VOLUNTEER,
    **kwargs,
) -> Worker:
    worker = Worker(
        id=uuid.uuid4(),
        full_name=full_name,
        phone="08011112222",
        employment_type=employment_type,
        created_by=created_by,
        status="ACTIVE",
        **kwargs,
    )
    db.add(worker)
    db.flush()
    return worker
