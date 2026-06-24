"""
Create a SUPER_ADMIN user for Genesis Global CMS.

Usage (from the backend/ directory):
    python scripts/create_admin.py --email admin@example.com --password YourPassword123!

What it does:
  1. Creates the user in Supabase Auth (email + password)
  2. Inserts a matching row in app_users with role=SUPER_ADMIN
  3. Uses the Supabase UUID as the app_users primary key (required for login)
"""
import argparse
import sys
import uuid

import httpx
from sqlalchemy import text
from sqlalchemy.orm import Session

# Allow running from the backend/ directory
sys.path.insert(0, ".")

from app.config import settings
from app.database import SessionLocal


def create_supabase_user(email: str, password: str) -> str:
    """Create user in Supabase Auth using service_role key. Returns the new user's UUID."""
    url = f"{settings.SUPABASE_URL}/auth/v1/admin/users"
    headers = {
        "apikey": settings.SUPABASE_SERVICE_KEY,
        "Authorization": f"Bearer {settings.SUPABASE_SERVICE_KEY}",
        "Content-Type": "application/json",
    }
    payload = {
        "email": email,
        "password": password,
        "email_confirm": True,  # skip confirmation email
    }

    response = httpx.post(url, json=payload, headers=headers, timeout=15.0)

    if response.status_code == 422:
        data = response.json()
        msg = data.get("msg") or data.get("message") or str(data)
        if "already been registered" in msg or "already exists" in msg:
            # User already exists in Supabase — fetch their ID instead
            return get_existing_supabase_user_id(email)
        print(f"Supabase error: {msg}")
        sys.exit(1)

    if response.status_code not in (200, 201):
        print(f"Supabase Auth error {response.status_code}: {response.text}")
        sys.exit(1)

    return response.json()["id"]


def get_existing_supabase_user_id(email: str) -> str:
    """Fetch an existing Supabase user's UUID by email."""
    url = f"{settings.SUPABASE_URL}/auth/v1/admin/users"
    headers = {
        "apikey": settings.SUPABASE_SERVICE_KEY,
        "Authorization": f"Bearer {settings.SUPABASE_SERVICE_KEY}",
    }
    # Supabase returns paginated list; search by email
    response = httpx.get(url, headers=headers, params={"page": 1, "per_page": 1000}, timeout=15.0)
    if response.status_code != 200:
        print(f"Could not list Supabase users: {response.text}")
        sys.exit(1)

    users = response.json().get("users", [])
    for user in users:
        if user.get("email", "").lower() == email.lower():
            return user["id"]

    print(f"User {email} not found in Supabase Auth.")
    sys.exit(1)


def create_app_user(db: Session, supabase_id: str, email: str, role: str) -> None:
    """Insert or update the app_users row."""
    user_uuid = uuid.UUID(supabase_id)

    existing = db.execute(
        text("SELECT id, role FROM app_users WHERE id = :id"),
        {"id": str(user_uuid)},
    ).fetchone()

    if existing:
        db.execute(
            text("UPDATE app_users SET role = :role, is_active = true WHERE id = :id"),
            {"role": role, "id": str(user_uuid)},
        )
        print(f"Updated existing app_users record → role={role}")
    else:
        db.execute(
            text(
                "INSERT INTO app_users (id, email, role, is_active, created_at, updated_at) "
                "VALUES (:id, :email, :role, true, NOW(), NOW())"
            ),
            {"id": str(user_uuid), "email": email, "role": role},
        )
        print(f"Created new app_users record with id={user_uuid}")

    db.commit()


def main() -> None:
    parser = argparse.ArgumentParser(description="Create a Genesis Global CMS admin account")
    parser.add_argument("--email", required=True, help="Admin email address")
    parser.add_argument("--password", required=True, help="Admin password (min 8 chars)")
    parser.add_argument(
        "--role",
        default="SUPER_ADMIN",
        choices=["SUPER_ADMIN", "PASTOR", "FINANCE_ADMIN", "HR_ADMIN"],
        help="Role to assign (default: SUPER_ADMIN)",
    )
    args = parser.parse_args()

    if not settings.SUPABASE_SERVICE_KEY:
        print("ERROR: SUPABASE_SERVICE_KEY is not set in your environment/.env")
        sys.exit(1)

    print(f"Creating {args.role} account for {args.email}...")

    # Step 1: Supabase Auth
    supabase_id = create_supabase_user(args.email, args.password)
    print(f"Supabase user ID: {supabase_id}")

    # Step 2: app_users table
    db: Session = SessionLocal()
    try:
        create_app_user(db, supabase_id, args.email, args.role)
    finally:
        db.close()

    print(f"\nDone! You can now log in with:")
    print(f"  Email:    {args.email}")
    print(f"  Password: {args.password}")
    print(f"  Role:     {args.role}")


if __name__ == "__main__":
    main()
