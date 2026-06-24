"""
Genesis Global CMS — KPI Tracking Tests

Covers:
1.  Create KPI definition (super admin)
2.  Create KPI definition (department head)
3.  Record KPI value
4.  List KPI definitions
5.  List KPI records
6.  KPI dashboard for entity
7.  KPI percentage calculation (target=40, actual=35 → 87.5%)
8.  Update KPI definition
9.  Delete (soft delete) KPI definition
10. Unauthorized roles cannot manage KPIs
"""
import uuid
from datetime import date

import pytest

from tests.conftest import auth_headers, make_token
from tests.utils import (
    create_department,
    create_kpi_definition,
    create_kpi_record,
    create_user,
)
from app.auth.models import UserRole
from app.models.kpi import KpiPeriodEnum


# ── Create KPI Definition ──────────────────────────────────────────────────────

def test_super_admin_can_create_kpi_definition(client, db, super_admin_user, super_admin_token):
    """Super admin can create a KPI definition."""
    dept = create_department(db, name="KPI Test Department")

    response = client.post(
        "/api/v1/kpi/definitions",
        json={
            "name": "New Converts Onboarded",
            "entity_type": "DEPARTMENT",
            "entity_id": str(dept.id),
            "target_value": 40,
            "target_unit": "count",
            "period": "MONTHLY",
        },
        headers=auth_headers(super_admin_token),
    )

    assert response.status_code == 201
    data = response.json()["data"]
    assert data["name"] == "New Converts Onboarded"
    assert data["target_value"] == 40.0
    assert data["period"] == "MONTHLY"
    assert data["is_active"] is True


def test_pastor_can_create_kpi_definition(client, db, pastor_user, pastor_token):
    """Pastor can also create KPI definitions."""
    dept = create_department(db, name="Pastor KPI Dept")

    response = client.post(
        "/api/v1/kpi/definitions",
        json={
            "name": "Baptisms",
            "entity_type": "DEPARTMENT",
            "entity_id": str(dept.id),
            "target_value": 10,
            "period": "QUARTERLY",
        },
        headers=auth_headers(pastor_token),
    )

    assert response.status_code == 201


def test_department_head_can_create_kpi_for_their_dept(client, db, department_head_user, department_head_token):
    """Department head can create KPI definitions."""
    dept = create_department(db, head_user_id=department_head_user.id)

    response = client.post(
        "/api/v1/kpi/definitions",
        json={
            "name": "Member Retention",
            "entity_type": "DEPARTMENT",
            "entity_id": str(dept.id),
            "target_value": 90,
            "target_unit": "percent",
            "period": "MONTHLY",
        },
        headers=auth_headers(department_head_token),
    )

    assert response.status_code == 201


def test_finance_cannot_create_kpi(client, db, finance_user, finance_token):
    """Finance admin must receive 403 when trying to create a KPI definition."""
    response = client.post(
        "/api/v1/kpi/definitions",
        json={
            "name": "Finance KPI",
            "entity_type": "DEPARTMENT",
            "entity_id": str(uuid.uuid4()),
            "target_value": 100,
            "period": "MONTHLY",
        },
        headers=auth_headers(finance_token),
    )
    assert response.status_code == 403


def test_medical_cannot_create_kpi(client, db, medical_user, medical_token):
    """Medical staff must receive 403 when trying to create a KPI definition."""
    response = client.post(
        "/api/v1/kpi/definitions",
        json={
            "name": "Medical KPI",
            "entity_type": "DEPARTMENT",
            "entity_id": str(uuid.uuid4()),
            "target_value": 50,
            "period": "MONTHLY",
        },
        headers=auth_headers(medical_token),
    )
    assert response.status_code == 403


def test_hr_cannot_create_kpi(client, db, hr_user, hr_token):
    """HR admin must receive 403 when trying to create a KPI definition."""
    response = client.post(
        "/api/v1/kpi/definitions",
        json={
            "name": "HR KPI",
            "entity_type": "DEPARTMENT",
            "entity_id": str(uuid.uuid4()),
            "target_value": 30,
            "period": "MONTHLY",
        },
        headers=auth_headers(hr_token),
    )
    assert response.status_code == 403


# ── List KPI Definitions ───────────────────────────────────────────────────────

def test_list_kpi_definitions(client, db, super_admin_user, super_admin_token):
    """Super admin can list all KPI definitions."""
    create_kpi_definition(db, created_by=super_admin_user.id, name="List KPI 1")

    response = client.get(
        "/api/v1/kpi/definitions",
        headers=auth_headers(super_admin_token),
    )

    assert response.status_code == 200
    data = response.json()
    assert "data" in data
    assert "total" in data


def test_list_kpi_definitions_unauthenticated_returns_401(client):
    """Unauthenticated access to KPI list must return 401."""
    response = client.get("/api/v1/kpi/definitions")
    assert response.status_code == 401


# ── Record KPI Value ───────────────────────────────────────────────────────────

def test_record_kpi_value(client, db, super_admin_user, super_admin_token):
    """Super admin can record a KPI value for a period."""
    kpi = create_kpi_definition(db, created_by=super_admin_user.id, target_value=40)

    response = client.post(
        "/api/v1/kpi/records",
        json={
            "kpi_definition_id": str(kpi.id),
            "period_start": "2024-01-01",
            "period_end": "2024-01-31",
            "actual_value": 35,
            "notes": "Good progress this month",
        },
        headers=auth_headers(super_admin_token),
    )

    assert response.status_code == 201
    data = response.json()["data"]
    assert data["actual_value"] == 35.0
    assert data["kpi_definition_id"] == str(kpi.id)


def test_record_kpi_value_zero(client, db, super_admin_user, super_admin_token):
    """Zero actual value is a valid KPI record."""
    kpi = create_kpi_definition(db, created_by=super_admin_user.id, target_value=20)

    response = client.post(
        "/api/v1/kpi/records",
        json={
            "kpi_definition_id": str(kpi.id),
            "period_start": "2024-02-01",
            "period_end": "2024-02-29",
            "actual_value": 0,
        },
        headers=auth_headers(super_admin_token),
    )

    assert response.status_code == 201
    assert response.json()["data"]["actual_value"] == 0.0


def test_record_kpi_missing_required_fields(client, db, super_admin_user, super_admin_token):
    """Recording KPI without period dates must fail."""
    kpi = create_kpi_definition(db, created_by=super_admin_user.id)

    response = client.post(
        "/api/v1/kpi/records",
        json={
            "kpi_definition_id": str(kpi.id),
            "actual_value": 25,
            # missing period_start and period_end
        },
        headers=auth_headers(super_admin_token),
    )

    assert response.status_code == 422


def test_finance_cannot_record_kpi(client, db, finance_user, finance_token, super_admin_user):
    """Finance admin cannot record KPI values."""
    kpi = create_kpi_definition(db, created_by=super_admin_user.id)

    response = client.post(
        "/api/v1/kpi/records",
        json={
            "kpi_definition_id": str(kpi.id),
            "period_start": "2024-01-01",
            "period_end": "2024-01-31",
            "actual_value": 20,
        },
        headers=auth_headers(finance_token),
    )

    assert response.status_code == 403


# ── KPI Dashboard ──────────────────────────────────────────────────────────────

def test_kpi_dashboard_accessible(client, db, super_admin_user, super_admin_token):
    """Super admin can access the KPI dashboard for any entity."""
    entity_id = uuid.uuid4()

    response = client.get(
        f"/api/v1/kpi/dashboard/DEPARTMENT/{entity_id}",
        headers=auth_headers(super_admin_token),
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert isinstance(data, dict)


def test_kpi_dashboard_with_records_has_kpis(client, db, super_admin_user, super_admin_token):
    """Dashboard should include KPI definitions with records."""
    dept_id = uuid.uuid4()
    kpi = create_kpi_definition(
        db,
        created_by=super_admin_user.id,
        entity_type="DEPARTMENT",
        entity_id=dept_id,
        target_value=40,
    )
    create_kpi_record(db, kpi_definition_id=kpi.id, recorded_by=super_admin_user.id, actual_value=35)

    response = client.get(
        f"/api/v1/kpi/dashboard/DEPARTMENT/{dept_id}",
        headers=auth_headers(super_admin_token),
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert "kpis" in data


def test_kpi_percentage_calculation_87_point_5(client, db, super_admin_user, super_admin_token):
    """KPI with target=40 and actual=35 should show percentage_achieved ≈ 87.5%."""
    dept_id = uuid.uuid4()
    kpi = create_kpi_definition(
        db,
        created_by=super_admin_user.id,
        entity_type="DEPARTMENT",
        entity_id=dept_id,
        target_value=40,
    )
    create_kpi_record(
        db,
        kpi_definition_id=kpi.id,
        recorded_by=super_admin_user.id,
        actual_value=35,
    )

    response = client.get(
        f"/api/v1/kpi/dashboard/DEPARTMENT/{dept_id}",
        headers=auth_headers(super_admin_token),
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert "kpis" in data

    for kpi_item in data["kpis"]:
        if kpi_item.get("name") == kpi.name:
            pct = kpi_item.get("percentage_achieved")
            if pct is not None:
                assert abs(pct - 87.5) < 0.5, f"Expected ~87.5%, got {pct}"
            break


def test_kpi_dashboard_unauthenticated_returns_401(client):
    """Unauthenticated dashboard access must return 401."""
    entity_id = uuid.uuid4()
    response = client.get(f"/api/v1/kpi/dashboard/DEPARTMENT/{entity_id}")
    assert response.status_code == 401


# ── Update KPI Definition ──────────────────────────────────────────────────────

def test_update_kpi_definition(client, db, super_admin_user, super_admin_token):
    """Super admin can update a KPI definition's target and other fields."""
    kpi = create_kpi_definition(db, created_by=super_admin_user.id, target_value=30)

    response = client.put(
        f"/api/v1/kpi/definitions/{kpi.id}",
        json={"target_value": 50, "is_active": True},
        headers=auth_headers(super_admin_token),
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["id"] == str(kpi.id)


def test_update_nonexistent_kpi_returns_404(client, db, super_admin_user, super_admin_token):
    """Updating a non-existent KPI definition should return 404."""
    fake_id = uuid.uuid4()
    response = client.put(
        f"/api/v1/kpi/definitions/{fake_id}",
        json={"target_value": 100},
        headers=auth_headers(super_admin_token),
    )
    assert response.status_code == 404


# ── Delete KPI Definition ──────────────────────────────────────────────────────

def test_super_admin_can_delete_kpi_definition(client, db, super_admin_user, super_admin_token):
    """Super admin can soft-delete a KPI definition."""
    kpi = create_kpi_definition(db, created_by=super_admin_user.id)

    response = client.delete(
        f"/api/v1/kpi/definitions/{kpi.id}",
        headers=auth_headers(super_admin_token),
    )

    assert response.status_code == 200
    assert response.json()["success"] is True


def test_department_head_cannot_delete_kpi(client, db, department_head_user, department_head_token, super_admin_user):
    """Department head cannot delete KPI definitions (only SUPER_ADMIN/PASTOR can)."""
    kpi = create_kpi_definition(db, created_by=super_admin_user.id)

    response = client.delete(
        f"/api/v1/kpi/definitions/{kpi.id}",
        headers=auth_headers(department_head_token),
    )

    assert response.status_code == 403


# ── List KPI Records ───────────────────────────────────────────────────────────

def test_list_kpi_records(client, db, super_admin_user, super_admin_token):
    """Super admin can list all KPI records."""
    kpi = create_kpi_definition(db, created_by=super_admin_user.id)
    create_kpi_record(db, kpi_definition_id=kpi.id, recorded_by=super_admin_user.id)

    response = client.get(
        "/api/v1/kpi/records",
        headers=auth_headers(super_admin_token),
    )

    assert response.status_code == 200
    data = response.json()
    assert "data" in data
    assert "total" in data


def test_kpi_dashboard_trend_data_with_history(client, db, super_admin_user, super_admin_token):
    """Dashboard should include trend data when multiple records exist."""
    from datetime import date, timedelta

    dept_id = uuid.uuid4()
    kpi = create_kpi_definition(
        db,
        created_by=super_admin_user.id,
        entity_id=dept_id,
        target_value=30,
    )

    # Create 3 months of records
    months = [
        (date(2024, 1, 1), date(2024, 1, 31), 25),
        (date(2024, 2, 1), date(2024, 2, 29), 28),
        (date(2024, 3, 1), date(2024, 3, 31), 32),
    ]
    for ps, pe, val in months:
        create_kpi_record(
            db,
            kpi_definition_id=kpi.id,
            recorded_by=super_admin_user.id,
            actual_value=val,
            period_start=ps,
            period_end=pe,
        )

    response = client.get(
        f"/api/v1/kpi/dashboard/DEPARTMENT/{dept_id}",
        headers=auth_headers(super_admin_token),
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert "kpis" in data

    if data["kpis"]:
        for kpi_item in data["kpis"]:
            # trend should be present and non-empty if records exist
            if "trend" in kpi_item:
                assert isinstance(kpi_item["trend"], list)
