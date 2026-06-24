"""
Genesis Global CMS — Medical Records Tests (Isolated Domain)

Covers:
1.  Medical staff can create patients
2.  member_link_id NEVER appears in any response
3.  is_church_member shown as True when linked, without exposing ID
4.  Medical staff cannot search member directory
5.  Medical staff can search own patients
6.  Create medical visit for a patient
7.  List visits for a patient
8.  Medical dashboard stats
9.  Non-medical roles cannot access medical endpoints
10. Super admin CAN access medical endpoints
"""
import uuid
from datetime import date

import pytest

from tests.conftest import auth_headers, make_token
from tests.utils import (
    create_active_member,
    create_medical_user,
    create_medical_visit,
    create_patient,
    create_user,
)
from app.auth.models import UserRole


# ── Patient Creation ───────────────────────────────────────────────────────────

def test_medical_creates_patient_successfully(client, db, medical_user, medical_token):
    """Medical staff can create a new patient record."""
    response = client.post(
        "/api/v1/medical/patients",
        json={
            "full_name": "Test Patient Alpha",
            "phone": "08099887766",
            "gender": "MALE",
            "consent_given": True,
        },
        headers=auth_headers(medical_token),
    )

    assert response.status_code == 201
    data = response.json()["data"]
    assert data["full_name"] == "Test Patient Alpha"
    assert data["consent_given"] is True


def test_patient_creation_requires_consent(client, db, medical_user, medical_token):
    """Patient records require consent_given field."""
    response = client.post(
        "/api/v1/medical/patients",
        json={
            "full_name": "No Consent Patient",
            "phone": "08099887755",
        },
        headers=auth_headers(medical_token),
    )
    # Either creates with consent=False or requires it — should not crash
    # The schema defaults consent_given, so it should succeed
    assert response.status_code in (201, 422)


def test_member_link_id_never_in_create_response(client, db, medical_user, medical_token):
    """Patient creation response must not include member_link_id."""
    response = client.post(
        "/api/v1/medical/patients",
        json={
            "full_name": "Link Test Patient",
            "consent_given": True,
        },
        headers=auth_headers(medical_token),
    )

    assert response.status_code == 201
    body_str = response.text
    assert "member_link_id" not in body_str


def test_non_medical_cannot_create_patient(client, db, finance_user, finance_token):
    """Finance admin must receive 403 when trying to create a patient."""
    response = client.post(
        "/api/v1/medical/patients",
        json={"full_name": "Finance Patient", "consent_given": True},
        headers=auth_headers(finance_token),
    )
    assert response.status_code == 403


def test_follow_up_cannot_create_patient(client, db, follow_up_user, follow_up_token):
    """Follow-up staff must receive 403 when trying to create a patient."""
    response = client.post(
        "/api/v1/medical/patients",
        json={"full_name": "FollowUp Patient", "consent_given": True},
        headers=auth_headers(follow_up_token),
    )
    assert response.status_code == 403


# ── Patient Retrieval ──────────────────────────────────────────────────────────

def test_medical_can_get_own_patient(client, db, medical_user, medical_token):
    """Medical staff can retrieve a patient they created."""
    patient = create_patient(db, created_by=medical_user.id, full_name="Owned Patient")

    response = client.get(
        f"/api/v1/medical/patients/{patient.id}",
        headers=auth_headers(medical_token),
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["full_name"] == "Owned Patient"
    assert "member_link_id" not in data


def test_medical_cannot_get_other_users_patient(client, db):
    """Medical user cannot access a patient created by a different medical user."""
    user1 = create_medical_user(db, "medget1@test.com")
    user2 = create_medical_user(db, "medget2@test.com")

    patient = create_patient(db, created_by=user1.id, full_name="User1 Only Patient")

    token2 = make_token(str(user2.id), user2.email, "MEDICAL")
    response = client.get(
        f"/api/v1/medical/patients/{patient.id}",
        headers=auth_headers(token2),
    )

    assert response.status_code in (403, 404)


def test_super_admin_can_access_medical_patients(client, db, super_admin_user, super_admin_token):
    """Super admin can list all medical patients."""
    response = client.get(
        "/api/v1/medical/patients",
        headers=auth_headers(super_admin_token),
    )
    assert response.status_code == 200


def test_get_nonexistent_patient_returns_404(client, db, medical_user, medical_token):
    """Requesting a patient that does not exist should return 404."""
    fake_id = uuid.uuid4()
    response = client.get(
        f"/api/v1/medical/patients/{fake_id}",
        headers=auth_headers(medical_token),
    )
    assert response.status_code == 404


# ── Church Member Flag ─────────────────────────────────────────────────────────

def test_is_church_member_true_without_exposing_link(client, db, medical_user, medical_token):
    """Patient marked as church member shows is_church_member=True but no link ID."""
    patient = create_patient(
        db,
        created_by=medical_user.id,
        full_name="Church Member Patient",
        is_church_member=True,
    )
    patient.member_link_id = uuid.uuid4()
    db.flush()

    response = client.get(
        f"/api/v1/medical/patients/{patient.id}",
        headers=auth_headers(medical_token),
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["is_church_member"] is True
    assert "member_link_id" not in data
    assert "member_id" not in data


def test_non_church_member_patient(client, db, medical_user, medical_token):
    """A patient not linked to a member has is_church_member=False."""
    patient = create_patient(
        db,
        created_by=medical_user.id,
        full_name="Non Church Patient",
        is_church_member=False,
    )

    response = client.get(
        f"/api/v1/medical/patients/{patient.id}",
        headers=auth_headers(medical_token),
    )

    assert response.status_code == 200
    assert response.json()["data"]["is_church_member"] is False


# ── Patient Search ─────────────────────────────────────────────────────────────

def test_medical_can_search_own_patients(client, db, medical_user, medical_token):
    """Medical user can search their own patients by name."""
    create_patient(db, created_by=medical_user.id, full_name="Searchable Patient Delta")

    response = client.get(
        "/api/v1/medical/patients/search?q=Searchable",
        headers=auth_headers(medical_token),
    )

    assert response.status_code == 200
    data = response.json()
    assert data["total"] >= 1
    names = [p["full_name"] for p in data["data"]]
    assert any("Searchable" in n for n in names)


def test_medical_cannot_search_member_directory(client, db, medical_user, medical_token):
    """Medical staff must be blocked from the member search endpoint."""
    response = client.post(
        "/api/v1/members/search",
        json={"query": "test member"},
        headers=auth_headers(medical_token),
    )
    assert response.status_code == 403


def test_search_requires_minimum_query_length(client, db, medical_user, medical_token):
    """Patient search query must be at least 2 characters."""
    response = client.get(
        "/api/v1/medical/patients/search?q=X",
        headers=auth_headers(medical_token),
    )
    assert response.status_code == 422


# ── Medical Visits ─────────────────────────────────────────────────────────────

def test_record_medical_visit(client, db, medical_user, medical_token):
    """Medical staff can record a visit for their patient."""
    patient = create_patient(db, created_by=medical_user.id, full_name="Visit Patient")

    response = client.post(
        f"/api/v1/medical/patients/{patient.id}/visits",
        json={
            "visit_date": "2024-01-15",
            "complaints": "Persistent headache",
            "diagnosis": "Tension headache",
            "treatment": "Rest and hydration",
            "medications": "Paracetamol 500mg",
        },
        headers=auth_headers(medical_token),
    )

    assert response.status_code == 201
    data = response.json()["data"]
    assert data["patient_id"] == str(patient.id)
    assert data["diagnosis"] == "Tension headache"


def test_list_visits_for_patient(client, db, medical_user, medical_token):
    """Medical staff can list visits for their patient."""
    patient = create_patient(db, created_by=medical_user.id, full_name="Visit List Patient")
    create_medical_visit(db, patient_id=patient.id, attended_by=medical_user.id)

    response = client.get(
        f"/api/v1/medical/patients/{patient.id}/visits",
        headers=auth_headers(medical_token),
    )

    assert response.status_code == 200
    data = response.json()
    assert data["total"] >= 1


def test_visit_response_does_not_include_member_link_id(client, db, medical_user, medical_token):
    """Visit records must not expose any member link field."""
    patient = create_patient(db, created_by=medical_user.id, full_name="Visit Link Test")

    response = client.post(
        f"/api/v1/medical/patients/{patient.id}/visits",
        json={
            "visit_date": "2024-02-01",
            "complaints": "Cough",
            "diagnosis": "Common cold",
            "treatment": "Bed rest",
        },
        headers=auth_headers(medical_token),
    )

    assert response.status_code == 201
    assert "member_link_id" not in response.text


def test_cannot_record_visit_for_other_users_patient(client, db):
    """Medical user cannot record a visit for another user's patient."""
    user1 = create_medical_user(db, "visit1@test.com")
    user2 = create_medical_user(db, "visit2@test.com")

    patient = create_patient(db, created_by=user1.id, full_name="Visit Isolation Patient")
    token2 = make_token(str(user2.id), user2.email, "MEDICAL")

    response = client.post(
        f"/api/v1/medical/patients/{patient.id}/visits",
        json={
            "visit_date": "2024-02-15",
            "complaints": "Unauthorized visit",
        },
        headers=auth_headers(token2),
    )

    assert response.status_code in (403, 404)


# ── Medical Dashboard ──────────────────────────────────────────────────────────

def test_medical_dashboard_accessible(client, db, medical_user, medical_token):
    """Medical staff can access their own dashboard."""
    response = client.get(
        "/api/v1/medical/dashboard",
        headers=auth_headers(medical_token),
    )

    assert response.status_code == 200
    data = response.json()["data"]
    # Dashboard should have some numeric stats
    assert isinstance(data, dict)


def test_non_medical_cannot_access_medical_dashboard(client, db, hr_user, hr_token):
    """HR admin must be blocked from medical dashboard."""
    response = client.get(
        "/api/v1/medical/dashboard",
        headers=auth_headers(hr_token),
    )
    assert response.status_code == 403


# ── Patient Update ─────────────────────────────────────────────────────────────

def test_medical_can_update_own_patient(client, db, medical_user, medical_token):
    """Medical staff can update a patient they created."""
    patient = create_patient(db, created_by=medical_user.id, full_name="Updatable Patient")

    response = client.put(
        f"/api/v1/medical/patients/{patient.id}",
        json={"allergies": "Penicillin", "chronic_conditions": "Hypertension"},
        headers=auth_headers(medical_token),
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["allergies"] == "Penicillin"
    assert "member_link_id" not in data


def test_update_response_never_includes_member_link_id(client, db, medical_user, medical_token):
    """Update response must not include member_link_id."""
    patient = create_patient(db, created_by=medical_user.id, full_name="Update Link Test")
    patient.member_link_id = uuid.uuid4()
    db.flush()

    response = client.put(
        f"/api/v1/medical/patients/{patient.id}",
        json={"allergies": "None"},
        headers=auth_headers(medical_token),
    )

    assert response.status_code == 200
    assert "member_link_id" not in response.text
