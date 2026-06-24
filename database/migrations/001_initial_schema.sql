-- Genesis Global CMS Initial Schema Migration
-- Organization: Genesis Global (Celestial Church of Christ)
-- Version: 001
-- Created: 2026-06-23
-- Description: Complete initial schema for the Church Management System
--              covering Member, Medical, Sponsor, and HR isolated domains.

-- ============================================================
-- EXTENSIONS
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- UTILITY: updated_at TRIGGER FUNCTION
-- ============================================================

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- ENUMS
-- ============================================================

DO $$ BEGIN
  CREATE TYPE user_role AS ENUM (
    'SUPER_ADMIN',
    'PASTOR',
    'FINANCE_ADMIN',
    'HR_ADMIN',
    'DEPARTMENT_HEAD',
    'TEAM_LEADER',
    'GROUP_LEADER',
    'FOLLOW_UP',
    'MEDICAL',
    'MEMBER'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE member_status AS ENUM (
    'ACTIVE',
    'INACTIVE',
    'PENDING',
    'PENDING_DUPLICATE_CHECK',
    'PENDING_INFO_REQUESTED',
    'REJECTED',
    'MERGED'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE gender AS ENUM (
    'MALE',
    'FEMALE'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE marital_status AS ENUM (
    'SINGLE',
    'MARRIED',
    'DIVORCED',
    'WIDOWED'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE employment_type AS ENUM (
    'VOLUNTEER',
    'PART_TIME',
    'FULL_TIME'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE sponsorship_tier AS ENUM (
    'MONTHLY',
    'QUARTERLY',
    'ANNUAL',
    'ONE_TIME'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE payment_status AS ENUM (
    'PENDING',
    'COMPLETED',
    'FAILED',
    'REFUNDED'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE follow_up_stage AS ENUM (
    'FIRST_CONTACT',
    'HOME_VISIT_SCHEDULED',
    'ONBOARDING_CLASS_COMPLETED',
    'DEPARTMENT_PLACEMENT',
    'FULLY_INTEGRATED'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE attendance_status AS ENUM (
    'PRESENT',
    'ABSENT',
    'EXCUSED'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE kpi_period AS ENUM (
    'MONTHLY',
    'QUARTERLY',
    'ANNUAL'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE audit_action AS ENUM (
    'CREATE',
    'READ',
    'UPDATE',
    'DELETE',
    'LOGIN',
    'LOGOUT',
    'APPROVE',
    'REJECT',
    'MERGE',
    'VIEW_SENSITIVE'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ============================================================
-- TABLE 1: app_users (Core Auth — references Supabase auth.users)
-- ============================================================

CREATE TABLE IF NOT EXISTS app_users (
  id              UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email           TEXT UNIQUE NOT NULL,
  role            user_role NOT NULL,
  member_id       UUID,                          -- FK added after members table
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  last_login_at   TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at      TIMESTAMPTZ
);

CREATE TRIGGER trg_app_users_updated_at
  BEFORE UPDATE ON app_users
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================
-- TABLE 2: members (Golden record — MEMBER DOMAIN)
-- ============================================================

CREATE TABLE IF NOT EXISTS members (
  id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name                   TEXT NOT NULL,
  phone                       TEXT,              -- normalized to last 11 digits
  email                       TEXT,
  gender                      gender,
  date_of_birth               DATE,
  address                     TEXT,
  marital_status              marital_status,
  salvation_date              DATE,
  water_baptism_status        BOOLEAN NOT NULL DEFAULT FALSE,
  holy_spirit_baptism_status  BOOLEAN NOT NULL DEFAULT FALSE,
  membership_status           member_status NOT NULL DEFAULT 'PENDING',
  photo_url                   TEXT,
  submitted_by                UUID REFERENCES app_users(id) ON DELETE SET NULL,
  approved_by                 UUID REFERENCES app_users(id) ON DELETE SET NULL,
  approved_at                 TIMESTAMPTZ,
  rejection_reason            TEXT,
  duplicate_of                UUID REFERENCES members(id) ON DELETE SET NULL,
  created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at                  TIMESTAMPTZ
);

CREATE TRIGGER trg_members_updated_at
  BEFORE UPDATE ON members
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Now add the FK from app_users.member_id to members
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'fk_app_users_member_id'
      AND table_name = 'app_users'
  ) THEN
    ALTER TABLE app_users
      ADD CONSTRAINT fk_app_users_member_id
      FOREIGN KEY (member_id) REFERENCES members(id) ON DELETE SET NULL;
  END IF;
END $$;

-- ============================================================
-- TABLE 3: pending_member_data
-- ============================================================

CREATE TABLE IF NOT EXISTS pending_member_data (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id                UUID NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  submitter_notes          TEXT,
  admin_notes              TEXT,
  additional_info_requested TEXT,
  info_provided_at         TIMESTAMPTZ,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_pending_member_data_updated_at
  BEFORE UPDATE ON pending_member_data
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================
-- TABLE 4: member_duplicates
-- ============================================================

CREATE TABLE IF NOT EXISTS member_duplicates (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  new_member_id       UUID NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  existing_member_id  UUID NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  overall_score       NUMERIC(5,2),
  phone_score         NUMERIC(5,2),
  name_score          NUMERIC(5,2),
  email_score         NUMERIC(5,2),
  status              TEXT NOT NULL DEFAULT 'PENDING'
                        CHECK (status IN ('PENDING', 'RESOLVED', 'IGNORED')),
  resolved_by         UUID REFERENCES app_users(id) ON DELETE SET NULL,
  resolved_at         TIMESTAMPTZ,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT member_duplicates_different_members
    CHECK (new_member_id <> existing_member_id)
);

-- ============================================================
-- TABLE 5: departments (STRUCTURE DOMAIN)
-- ============================================================

CREATE TABLE IF NOT EXISTS departments (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name         TEXT NOT NULL UNIQUE,
  description  TEXT,
  head_user_id UUID REFERENCES app_users(id) ON DELETE SET NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at   TIMESTAMPTZ
);

CREATE TRIGGER trg_departments_updated_at
  BEFORE UPDATE ON departments
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================
-- TABLE 6: teams
-- ============================================================

CREATE TABLE IF NOT EXISTS teams (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name            TEXT NOT NULL,
  department_id   UUID NOT NULL REFERENCES departments(id) ON DELETE CASCADE,
  leader_user_id  UUID REFERENCES app_users(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at      TIMESTAMPTZ,
  UNIQUE (name, department_id)
);

CREATE TRIGGER trg_teams_updated_at
  BEFORE UPDATE ON teams
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================
-- TABLE 7: groups
-- ============================================================

CREATE TABLE IF NOT EXISTS groups (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name            TEXT NOT NULL,
  team_id         UUID REFERENCES teams(id) ON DELETE SET NULL,   -- nullable
  department_id   UUID NOT NULL REFERENCES departments(id) ON DELETE CASCADE,
  leader_user_id  UUID REFERENCES app_users(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at      TIMESTAMPTZ
);

CREATE TRIGGER trg_groups_updated_at
  BEFORE UPDATE ON groups
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================
-- TABLE 8: member_assignments
-- ============================================================

CREATE TABLE IF NOT EXISTS member_assignments (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id         UUID NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  assignment_type   TEXT NOT NULL CHECK (assignment_type IN ('DEPARTMENT', 'TEAM', 'GROUP')),
  assignment_id     UUID NOT NULL,              -- references dept/team/group id
  role_in_assignment TEXT,
  joined_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  left_at           TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at        TIMESTAMPTZ
);

CREATE TRIGGER trg_member_assignments_updated_at
  BEFORE UPDATE ON member_assignments
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================
-- TABLE 9: meetings (ATTENDANCE DOMAIN)
-- ============================================================

CREATE TABLE IF NOT EXISTS meetings (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title        TEXT NOT NULL,
  meeting_date DATE NOT NULL,
  meeting_type TEXT CHECK (meeting_type IN ('DEPARTMENT', 'TEAM', 'GROUP', 'CHURCH')),
  entity_id    UUID,                            -- dept/team/group id
  notes        TEXT,
  created_by   UUID REFERENCES app_users(id) ON DELETE SET NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at   TIMESTAMPTZ
);

CREATE TRIGGER trg_meetings_updated_at
  BEFORE UPDATE ON meetings
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================
-- TABLE 10: attendance_records
-- ============================================================

CREATE TABLE IF NOT EXISTS attendance_records (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  meeting_id  UUID NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
  member_id   UUID NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  status      attendance_status NOT NULL DEFAULT 'ABSENT',
  marked_by   UUID REFERENCES app_users(id) ON DELETE SET NULL,
  marked_at   TIMESTAMPTZ,
  notes       TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (meeting_id, member_id)
);

CREATE TRIGGER trg_attendance_records_updated_at
  BEFORE UPDATE ON attendance_records
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================
-- TABLE 11: kpi_definitions (KPI DOMAIN)
-- ============================================================

CREATE TABLE IF NOT EXISTS kpi_definitions (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name         TEXT NOT NULL,
  description  TEXT,
  entity_type  TEXT NOT NULL CHECK (entity_type IN ('DEPARTMENT', 'TEAM', 'GROUP')),
  entity_id    UUID NOT NULL,
  target_value NUMERIC,
  target_unit  TEXT,
  period       kpi_period NOT NULL DEFAULT 'MONTHLY',
  is_active    BOOLEAN NOT NULL DEFAULT TRUE,
  created_by   UUID REFERENCES app_users(id) ON DELETE SET NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at   TIMESTAMPTZ
);

CREATE TRIGGER trg_kpi_definitions_updated_at
  BEFORE UPDATE ON kpi_definitions
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================
-- TABLE 12: kpi_records
-- ============================================================

CREATE TABLE IF NOT EXISTS kpi_records (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  kpi_definition_id   UUID NOT NULL REFERENCES kpi_definitions(id) ON DELETE CASCADE,
  period_start        DATE NOT NULL,
  period_end          DATE NOT NULL,
  actual_value        NUMERIC,
  notes               TEXT,
  recorded_by         UUID REFERENCES app_users(id) ON DELETE SET NULL,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (kpi_definition_id, period_start),
  CONSTRAINT kpi_records_period_order CHECK (period_end >= period_start)
);

CREATE TRIGGER trg_kpi_records_updated_at
  BEFORE UPDATE ON kpi_records
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================
-- TABLE 13: follow_up_contacts (FOLLOW-UP DOMAIN)
-- ============================================================

CREATE TABLE IF NOT EXISTS follow_up_contacts (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name      TEXT NOT NULL,
  phone          TEXT,
  address        TEXT,
  prayer_requests TEXT,
  how_heard      TEXT,
  registered_by  UUID REFERENCES app_users(id) ON DELETE SET NULL,
  member_id      UUID REFERENCES members(id) ON DELETE SET NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at     TIMESTAMPTZ
);

CREATE TRIGGER trg_follow_up_contacts_updated_at
  BEFORE UPDATE ON follow_up_contacts
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================
-- TABLE 14: follow_up_tasks
-- ============================================================

CREATE TABLE IF NOT EXISTS follow_up_tasks (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  contact_id    UUID NOT NULL REFERENCES follow_up_contacts(id) ON DELETE CASCADE,
  member_id     UUID REFERENCES members(id) ON DELETE SET NULL,
  assigned_to   UUID NOT NULL REFERENCES app_users(id) ON DELETE RESTRICT,
  stage         follow_up_stage NOT NULL DEFAULT 'FIRST_CONTACT',
  due_date      TIMESTAMPTZ,
  completed_at  TIMESTAMPTZ,
  notes         TEXT,
  escalated_at  TIMESTAMPTZ,
  escalated_to  UUID REFERENCES app_users(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at    TIMESTAMPTZ
);

CREATE TRIGGER trg_follow_up_tasks_updated_at
  BEFORE UPDATE ON follow_up_tasks
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================
-- TABLE 15: follow_up_notes
-- ============================================================

CREATE TABLE IF NOT EXISTS follow_up_notes (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id      UUID NOT NULL REFERENCES follow_up_tasks(id) ON DELETE CASCADE,
  contact_id   UUID REFERENCES follow_up_contacts(id) ON DELETE SET NULL,
  member_id    UUID,                            -- pending_id allowed; loose reference
  note_type    TEXT CHECK (note_type IN ('CALL', 'VISIT', 'SMS', 'EMAIL', 'OTHER')),
  content      TEXT NOT NULL,
  recorded_by  UUID NOT NULL REFERENCES app_users(id) ON DELETE RESTRICT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_follow_up_notes_updated_at
  BEFORE UPDATE ON follow_up_notes
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================
-- TABLE 16: medical_patients (MEDICAL DOMAIN — COMPLETELY ISOLATED)
-- ============================================================

CREATE TABLE IF NOT EXISTS medical_patients (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name          TEXT NOT NULL,
  phone              TEXT,
  gender             gender,
  date_of_birth      DATE,
  is_church_member   BOOLEAN NOT NULL DEFAULT FALSE,
  member_link_id     UUID,    -- backend-only FK; never exposed to medical staff via RLS
  consent_given      BOOLEAN NOT NULL DEFAULT FALSE,
  consent_date       TIMESTAMPTZ,
  allergies          TEXT,
  chronic_conditions TEXT,
  created_by         UUID REFERENCES app_users(id) ON DELETE SET NULL,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at         TIMESTAMPTZ
);

COMMENT ON COLUMN medical_patients.member_link_id IS
  'Backend-only soft FK to members.id. NEVER expose this column in RLS or API responses to medical staff.';

CREATE TRIGGER trg_medical_patients_updated_at
  BEFORE UPDATE ON medical_patients
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================
-- TABLE 17: medical_visits
-- ============================================================

CREATE TABLE IF NOT EXISTS medical_visits (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id    UUID NOT NULL REFERENCES medical_patients(id) ON DELETE CASCADE,
  visit_date    DATE NOT NULL,
  complaints    TEXT,
  diagnosis     TEXT,
  treatment     TEXT,
  medications   TEXT,
  follow_up_date DATE,
  notes         TEXT,
  attended_by   UUID NOT NULL REFERENCES app_users(id) ON DELETE RESTRICT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at    TIMESTAMPTZ
);

CREATE TRIGGER trg_medical_visits_updated_at
  BEFORE UPDATE ON medical_visits
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================
-- TABLE 18: sponsors (SPONSOR/FINANCE DOMAIN — COMPLETELY ISOLATED)
-- ============================================================

CREATE TABLE IF NOT EXISTS sponsors (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name         TEXT NOT NULL,
  phone             TEXT,
  email             TEXT,
  sponsorship_tier  sponsorship_tier NOT NULL,
  amount            NUMERIC(15,2) NOT NULL CHECK (amount > 0),
  preferred_channel TEXT CHECK (preferred_channel IN ('SMS', 'WHATSAPP', 'EMAIL')),
  member_link_id    UUID,    -- backend-only soft FK; never shown in non-admin contexts
  is_active         BOOLEAN NOT NULL DEFAULT TRUE,
  created_by        UUID REFERENCES app_users(id) ON DELETE SET NULL,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at        TIMESTAMPTZ
);

COMMENT ON COLUMN sponsors.member_link_id IS
  'Backend-only soft FK to members.id. NEVER expose this column via RLS to non-finance roles.';

CREATE TRIGGER trg_sponsors_updated_at
  BEFORE UPDATE ON sponsors
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================
-- TABLE 19: sponsor_payments
-- ============================================================

CREATE TABLE IF NOT EXISTS sponsor_payments (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sponsor_id          UUID NOT NULL REFERENCES sponsors(id) ON DELETE CASCADE,
  amount              NUMERIC(15,2) NOT NULL CHECK (amount > 0),
  payment_date        TIMESTAMPTZ,
  payment_method      TEXT CHECK (payment_method IN ('FLUTTERWAVE', 'BANK_TRANSFER', 'CASH')),
  status              payment_status NOT NULL DEFAULT 'PENDING',
  tx_ref              TEXT UNIQUE,
  flutterwave_tx_id   TEXT,
  verified_by         UUID REFERENCES app_users(id) ON DELETE SET NULL,
  verified_at         TIMESTAMPTZ,
  notes               TEXT,
  next_due_date       DATE,
  reminder_sent_at    TIMESTAMPTZ,
  thank_you_sent_at   TIMESTAMPTZ,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at          TIMESTAMPTZ
);

CREATE TRIGGER trg_sponsor_payments_updated_at
  BEFORE UPDATE ON sponsor_payments
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================
-- TABLE 20: workers (HR DOMAIN — COMPLETELY ISOLATED)
-- ============================================================

CREATE TABLE IF NOT EXISTS workers (
  id                            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name                     TEXT NOT NULL,
  phone                         TEXT,
  email                         TEXT,
  department_id                 UUID REFERENCES departments(id) ON DELETE SET NULL,
  role_title                    TEXT,
  employment_type               employment_type NOT NULL DEFAULT 'VOLUNTEER',
  start_date                    DATE,
  status                        TEXT NOT NULL DEFAULT 'ACTIVE'
                                  CHECK (status IN ('ACTIVE', 'INACTIVE', 'ON_LEAVE')),
  time_commitment_hours_per_week INTEGER CHECK (time_commitment_hours_per_week >= 0),
  skills                        TEXT[],
  interests                     TEXT[],
  member_link_id                UUID,    -- backend-only soft FK; never shown to general users
  created_by                    UUID REFERENCES app_users(id) ON DELETE SET NULL,
  created_at                    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at                    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at                    TIMESTAMPTZ
);

COMMENT ON COLUMN workers.member_link_id IS
  'Backend-only soft FK to members.id. NEVER expose this column via RLS to non-HR roles.';
COMMENT ON COLUMN workers.employment_type IS
  'Volunteer-first architecture: salary fields deliberately omitted from this table.';

CREATE TRIGGER trg_workers_updated_at
  BEFORE UPDATE ON workers
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================
-- TABLE 21: worker_performance_reviews
-- ============================================================

CREATE TABLE IF NOT EXISTS worker_performance_reviews (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  worker_id           UUID NOT NULL REFERENCES workers(id) ON DELETE CASCADE,
  review_period_start DATE NOT NULL,
  review_period_end   DATE NOT NULL,
  reviewer_id         UUID NOT NULL REFERENCES app_users(id) ON DELETE RESTRICT,
  self_score          INTEGER CHECK (self_score BETWEEN 1 AND 5),
  peer_score          NUMERIC(3,2) CHECK (peer_score BETWEEN 1 AND 5),
  supervisor_score    INTEGER CHECK (supervisor_score BETWEEN 1 AND 5),
  overall_score       NUMERIC(3,2) CHECK (overall_score BETWEEN 1 AND 5),
  strengths           TEXT,
  areas_for_growth    TEXT,
  goals               TEXT,
  notes               TEXT,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT wpr_period_order CHECK (review_period_end >= review_period_start)
);

CREATE TRIGGER trg_worker_performance_reviews_updated_at
  BEFORE UPDATE ON worker_performance_reviews
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================
-- TABLE 22: worker_leave_requests
-- ============================================================

CREATE TABLE IF NOT EXISTS worker_leave_requests (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  worker_id    UUID NOT NULL REFERENCES workers(id) ON DELETE CASCADE,
  leave_type   TEXT NOT NULL CHECK (leave_type IN ('ANNUAL', 'SICK', 'PERSONAL', 'OTHER')),
  start_date   DATE NOT NULL,
  end_date     DATE NOT NULL,
  reason       TEXT,
  status       TEXT NOT NULL DEFAULT 'PENDING'
                 CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED')),
  approved_by  UUID REFERENCES app_users(id) ON DELETE SET NULL,
  approved_at  TIMESTAMPTZ,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT wlr_date_order CHECK (end_date >= start_date)
);

CREATE TRIGGER trg_worker_leave_requests_updated_at
  BEFORE UPDATE ON worker_leave_requests
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================
-- TABLE 23: worker_recognitions
-- ============================================================

CREATE TABLE IF NOT EXISTS worker_recognitions (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  worker_id        UUID NOT NULL REFERENCES workers(id) ON DELETE CASCADE,
  recognition_type TEXT CHECK (recognition_type IN ('AWARD', 'COMMENDATION', 'MILESTONE')),
  title            TEXT NOT NULL,
  description      TEXT,
  awarded_by       UUID REFERENCES app_users(id) ON DELETE SET NULL,
  awarded_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- TABLE 24: audit_logs (APPEND-ONLY — NEVER UPDATE OR DELETE)
-- ============================================================

CREATE TABLE IF NOT EXISTS audit_logs (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID NOT NULL REFERENCES app_users(id) ON DELETE RESTRICT,
  action         audit_action NOT NULL,
  resource_type  TEXT NOT NULL,
  resource_id    UUID,
  old_values     JSONB,
  new_values     JSONB,
  ip_address     INET,
  user_agent     TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE audit_logs IS
  'Append-only audit log. No UPDATE or DELETE operations are permitted on this table.';

-- Prevent any UPDATE or DELETE on audit_logs
CREATE OR REPLACE FUNCTION deny_audit_log_mutation()
RETURNS TRIGGER AS $$
BEGIN
  RAISE EXCEPTION 'audit_logs is append-only: UPDATE and DELETE operations are forbidden.';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_audit_logs_deny_update
  BEFORE UPDATE ON audit_logs
  FOR EACH ROW EXECUTE FUNCTION deny_audit_log_mutation();

CREATE TRIGGER trg_audit_logs_deny_delete
  BEFORE DELETE ON audit_logs
  FOR EACH ROW EXECUTE FUNCTION deny_audit_log_mutation();

-- ============================================================
-- TABLE 25: notification_queue
-- ============================================================

CREATE TABLE IF NOT EXISTS notification_queue (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_type  TEXT CHECK (recipient_type IN ('USER', 'MEMBER', 'SPONSOR')),
  recipient_id    UUID NOT NULL,
  channel         TEXT NOT NULL CHECK (channel IN ('SMS', 'EMAIL', 'WHATSAPP', 'IN_APP')),
  template_key    TEXT NOT NULL,
  payload         JSONB,
  status          TEXT NOT NULL DEFAULT 'PENDING'
                    CHECK (status IN ('PENDING', 'SENT', 'FAILED', 'CANCELLED')),
  sent_at         TIMESTAMPTZ,
  error_message   TEXT,
  retry_count     INTEGER NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  scheduled_for   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- INDEXES
-- ============================================================

-- app_users
CREATE INDEX IF NOT EXISTS idx_app_users_role         ON app_users (role) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_app_users_member_id    ON app_users (member_id) WHERE member_id IS NOT NULL;

-- members
CREATE INDEX IF NOT EXISTS idx_members_phone           ON members (phone) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_members_email           ON members (email) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_members_status          ON members (membership_status) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_members_submitted_by    ON members (submitted_by);
CREATE INDEX IF NOT EXISTS idx_members_approved_by     ON members (approved_by);
CREATE INDEX IF NOT EXISTS idx_members_fullname_gin    ON members USING gin (to_tsvector('english', full_name));

-- member_duplicates
CREATE INDEX IF NOT EXISTS idx_member_duplicates_new      ON member_duplicates (new_member_id);
CREATE INDEX IF NOT EXISTS idx_member_duplicates_existing ON member_duplicates (existing_member_id);
CREATE INDEX IF NOT EXISTS idx_member_duplicates_status   ON member_duplicates (status);

-- departments / teams / groups
CREATE INDEX IF NOT EXISTS idx_departments_head_user    ON departments (head_user_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_teams_department_id      ON teams (department_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_groups_department_id     ON groups (department_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_groups_team_id           ON groups (team_id) WHERE team_id IS NOT NULL AND deleted_at IS NULL;

-- member_assignments
CREATE INDEX IF NOT EXISTS idx_ma_member_id        ON member_assignments (member_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_ma_assignment_id    ON member_assignments (assignment_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_ma_assignment_type  ON member_assignments (assignment_type) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_ma_composite        ON member_assignments (assignment_type, assignment_id) WHERE deleted_at IS NULL;

-- meetings
CREATE INDEX IF NOT EXISTS idx_meetings_date        ON meetings (meeting_date) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_meetings_entity_id   ON meetings (entity_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_meetings_type        ON meetings (meeting_type) WHERE deleted_at IS NULL;

-- attendance_records
CREATE INDEX IF NOT EXISTS idx_attendance_meeting_id  ON attendance_records (meeting_id);
CREATE INDEX IF NOT EXISTS idx_attendance_member_id   ON attendance_records (member_id);
CREATE INDEX IF NOT EXISTS idx_attendance_status      ON attendance_records (status);

-- kpi_definitions / kpi_records
CREATE INDEX IF NOT EXISTS idx_kpi_def_entity     ON kpi_definitions (entity_type, entity_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_kpi_records_def    ON kpi_records (kpi_definition_id);
CREATE INDEX IF NOT EXISTS idx_kpi_records_period ON kpi_records (period_start, period_end);

-- follow_up_contacts / tasks / notes
CREATE INDEX IF NOT EXISTS idx_fuc_registered_by  ON follow_up_contacts (registered_by) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_fuc_member_id      ON follow_up_contacts (member_id) WHERE member_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_fut_assigned_to    ON follow_up_tasks (assigned_to) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_fut_stage          ON follow_up_tasks (stage) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_fut_due_date       ON follow_up_tasks (due_date) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_fut_contact_id     ON follow_up_tasks (contact_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_fun_task_id        ON follow_up_notes (task_id);
CREATE INDEX IF NOT EXISTS idx_fun_recorded_by    ON follow_up_notes (recorded_by);

-- medical_patients
CREATE INDEX IF NOT EXISTS idx_medical_phone      ON medical_patients (phone) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_medical_created_by ON medical_patients (created_by) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_medical_name_gin   ON medical_patients USING gin (to_tsvector('english', full_name));

-- medical_visits
CREATE INDEX IF NOT EXISTS idx_mv_patient_id   ON medical_visits (patient_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_mv_visit_date   ON medical_visits (visit_date) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_mv_attended_by  ON medical_visits (attended_by);

-- sponsors
CREATE INDEX IF NOT EXISTS idx_sponsors_phone          ON sponsors (phone) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_sponsors_email          ON sponsors (email) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_sponsors_tier           ON sponsors (sponsorship_tier) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_sponsors_is_active      ON sponsors (is_active) WHERE deleted_at IS NULL;

-- sponsor_payments
CREATE INDEX IF NOT EXISTS idx_sp_sponsor_id     ON sponsor_payments (sponsor_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_sp_status         ON sponsor_payments (status) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_sp_next_due_date  ON sponsor_payments (next_due_date) WHERE next_due_date IS NOT NULL AND deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_sp_payment_date   ON sponsor_payments (payment_date) WHERE deleted_at IS NULL;

-- workers
CREATE INDEX IF NOT EXISTS idx_workers_dept_id    ON workers (department_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_workers_status     ON workers (status) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_workers_emp_type   ON workers (employment_type) WHERE deleted_at IS NULL;

-- worker sub-tables
CREATE INDEX IF NOT EXISTS idx_wpr_worker_id  ON worker_performance_reviews (worker_id);
CREATE INDEX IF NOT EXISTS idx_wlr_worker_id  ON worker_leave_requests (worker_id);
CREATE INDEX IF NOT EXISTS idx_wlr_status     ON worker_leave_requests (status);
CREATE INDEX IF NOT EXISTS idx_wr_worker_id   ON worker_recognitions (worker_id);

-- audit_logs
CREATE INDEX IF NOT EXISTS idx_audit_user_id       ON audit_logs (user_id);
CREATE INDEX IF NOT EXISTS idx_audit_resource_type ON audit_logs (resource_type);
CREATE INDEX IF NOT EXISTS idx_audit_resource_id   ON audit_logs (resource_id) WHERE resource_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_audit_created_at    ON audit_logs (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_action        ON audit_logs (action);

-- notification_queue
CREATE INDEX IF NOT EXISTS idx_nq_status         ON notification_queue (status);
CREATE INDEX IF NOT EXISTS idx_nq_scheduled_for  ON notification_queue (scheduled_for) WHERE status = 'PENDING';
CREATE INDEX IF NOT EXISTS idx_nq_recipient_id   ON notification_queue (recipient_id);
CREATE INDEX IF NOT EXISTS idx_nq_recipient_type ON notification_queue (recipient_type);

-- ============================================================
-- ROW LEVEL SECURITY — enable on all tables
-- ============================================================

ALTER TABLE app_users                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE members                     ENABLE ROW LEVEL SECURITY;
ALTER TABLE pending_member_data         ENABLE ROW LEVEL SECURITY;
ALTER TABLE member_duplicates           ENABLE ROW LEVEL SECURITY;
ALTER TABLE departments                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE teams                       ENABLE ROW LEVEL SECURITY;
ALTER TABLE groups                      ENABLE ROW LEVEL SECURITY;
ALTER TABLE member_assignments          ENABLE ROW LEVEL SECURITY;
ALTER TABLE meetings                    ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance_records          ENABLE ROW LEVEL SECURITY;
ALTER TABLE kpi_definitions             ENABLE ROW LEVEL SECURITY;
ALTER TABLE kpi_records                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE follow_up_contacts          ENABLE ROW LEVEL SECURITY;
ALTER TABLE follow_up_tasks             ENABLE ROW LEVEL SECURITY;
ALTER TABLE follow_up_notes             ENABLE ROW LEVEL SECURITY;
ALTER TABLE medical_patients            ENABLE ROW LEVEL SECURITY;
ALTER TABLE medical_visits              ENABLE ROW LEVEL SECURITY;
ALTER TABLE sponsors                    ENABLE ROW LEVEL SECURITY;
ALTER TABLE sponsor_payments            ENABLE ROW LEVEL SECURITY;
ALTER TABLE workers                     ENABLE ROW LEVEL SECURITY;
ALTER TABLE worker_performance_reviews  ENABLE ROW LEVEL SECURITY;
ALTER TABLE worker_leave_requests       ENABLE ROW LEVEL SECURITY;
ALTER TABLE worker_recognitions         ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_queue          ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- HELPER: Get current user's role from app_users
-- ============================================================

CREATE OR REPLACE FUNCTION current_user_role()
RETURNS user_role AS $$
  SELECT role FROM app_users
  WHERE id = auth.uid()
    AND is_active = TRUE
    AND deleted_at IS NULL
  LIMIT 1;
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- ============================================================
-- RLS POLICIES: app_users
-- ============================================================

-- SUPER_ADMIN/PASTOR: see all active users
CREATE POLICY "app_users_select_admin" ON app_users
  FOR SELECT USING (
    current_user_role() IN ('SUPER_ADMIN', 'PASTOR')
    AND deleted_at IS NULL
  );

-- Each user can see their own record
CREATE POLICY "app_users_select_self" ON app_users
  FOR SELECT USING (
    id = auth.uid()
  );

-- Only SUPER_ADMIN can insert/update/delete app_users
CREATE POLICY "app_users_write_super_admin" ON app_users
  FOR ALL USING (
    current_user_role() = 'SUPER_ADMIN'
  );

-- ============================================================
-- RLS POLICIES: members
-- ============================================================

-- SUPER_ADMIN and PASTOR: full access
CREATE POLICY "members_select_super_admin_pastor" ON members
  FOR SELECT USING (
    current_user_role() IN ('SUPER_ADMIN', 'PASTOR')
    AND deleted_at IS NULL
  );

-- FINANCE_ADMIN: can only see members linked to a sponsor (id, full_name, phone)
-- NOTE: Column-level restriction is enforced at the API/view layer.
--       RLS here restricts ROWS; column restriction handled by dedicated DB view.
CREATE POLICY "members_select_finance_admin" ON members
  FOR SELECT USING (
    current_user_role() = 'FINANCE_ADMIN'
    AND deleted_at IS NULL
    AND id IN (SELECT member_link_id FROM sponsors WHERE member_link_id IS NOT NULL AND deleted_at IS NULL)
  );

-- HR_ADMIN: can only see members linked to a worker record
CREATE POLICY "members_select_hr_admin" ON members
  FOR SELECT USING (
    current_user_role() = 'HR_ADMIN'
    AND deleted_at IS NULL
    AND id IN (SELECT member_link_id FROM workers WHERE member_link_id IS NOT NULL AND deleted_at IS NULL)
  );

-- DEPARTMENT_HEAD: can see members in their department
CREATE POLICY "members_select_dept_head" ON members
  FOR SELECT USING (
    current_user_role() = 'DEPARTMENT_HEAD'
    AND deleted_at IS NULL
    AND id IN (
      SELECT ma.member_id FROM member_assignments ma
      JOIN departments d ON d.id = ma.assignment_id
      WHERE ma.assignment_type = 'DEPARTMENT'
        AND d.head_user_id = auth.uid()
        AND ma.deleted_at IS NULL
    )
  );

-- TEAM_LEADER: can see members in their team
CREATE POLICY "members_select_team_leader" ON members
  FOR SELECT USING (
    current_user_role() = 'TEAM_LEADER'
    AND deleted_at IS NULL
    AND id IN (
      SELECT ma.member_id FROM member_assignments ma
      JOIN teams t ON t.id = ma.assignment_id
      WHERE ma.assignment_type = 'TEAM'
        AND t.leader_user_id = auth.uid()
        AND ma.deleted_at IS NULL
    )
  );

-- GROUP_LEADER: can see members in their group
CREATE POLICY "members_select_group_leader" ON members
  FOR SELECT USING (
    current_user_role() = 'GROUP_LEADER'
    AND deleted_at IS NULL
    AND id IN (
      SELECT ma.member_id FROM member_assignments ma
      JOIN groups g ON g.id = ma.assignment_id
      WHERE ma.assignment_type = 'GROUP'
        AND g.leader_user_id = auth.uid()
        AND ma.deleted_at IS NULL
    )
  );

-- FOLLOW_UP: limited columns (id, full_name, phone, address, membership_status)
-- Row-level: all non-deleted members visible; column restriction via DB view
CREATE POLICY "members_select_follow_up" ON members
  FOR SELECT USING (
    current_user_role() = 'FOLLOW_UP'
    AND deleted_at IS NULL
  );

-- MEMBER: can only see their own record
CREATE POLICY "members_select_own" ON members
  FOR SELECT USING (
    current_user_role() = 'MEMBER'
    AND id IN (SELECT member_id FROM app_users WHERE id = auth.uid() AND deleted_at IS NULL)
  );

-- MEDICAL: NO ACCESS to members table (excluded from any SELECT policy)

-- INSERT: Admin creates = instant ACTIVE; Follow-up/Medical creates = PENDING
CREATE POLICY "members_insert_admin" ON members
  FOR INSERT WITH CHECK (
    current_user_role() IN ('SUPER_ADMIN', 'PASTOR', 'DEPARTMENT_HEAD', 'TEAM_LEADER', 'GROUP_LEADER')
  );

CREATE POLICY "members_insert_follow_up" ON members
  FOR INSERT WITH CHECK (
    current_user_role() = 'FOLLOW_UP'
  );

-- UPDATE: SUPER_ADMIN, PASTOR can update any; others limited
CREATE POLICY "members_update_admin" ON members
  FOR UPDATE USING (
    current_user_role() IN ('SUPER_ADMIN', 'PASTOR')
    AND deleted_at IS NULL
  );

-- Soft delete (set deleted_at): SUPER_ADMIN only
CREATE POLICY "members_soft_delete_super_admin" ON members
  FOR UPDATE USING (
    current_user_role() = 'SUPER_ADMIN'
  );

-- ============================================================
-- RLS POLICIES: pending_member_data
-- ============================================================

CREATE POLICY "pmd_select_admin" ON pending_member_data
  FOR SELECT USING (
    current_user_role() IN ('SUPER_ADMIN', 'PASTOR')
  );

CREATE POLICY "pmd_select_follow_up" ON pending_member_data
  FOR SELECT USING (
    current_user_role() = 'FOLLOW_UP'
    AND member_id IN (
      SELECT id FROM members WHERE submitted_by = auth.uid() AND deleted_at IS NULL
    )
  );

CREATE POLICY "pmd_insert" ON pending_member_data
  FOR INSERT WITH CHECK (
    current_user_role() IN ('SUPER_ADMIN', 'PASTOR', 'FOLLOW_UP', 'DEPARTMENT_HEAD', 'TEAM_LEADER', 'GROUP_LEADER')
  );

CREATE POLICY "pmd_update_admin" ON pending_member_data
  FOR UPDATE USING (
    current_user_role() IN ('SUPER_ADMIN', 'PASTOR')
  );

-- ============================================================
-- RLS POLICIES: member_duplicates
-- ============================================================

CREATE POLICY "member_dup_select_admin" ON member_duplicates
  FOR SELECT USING (
    current_user_role() IN ('SUPER_ADMIN', 'PASTOR')
  );

CREATE POLICY "member_dup_insert_system" ON member_duplicates
  FOR INSERT WITH CHECK (
    current_user_role() IN ('SUPER_ADMIN', 'PASTOR')
  );

CREATE POLICY "member_dup_update_admin" ON member_duplicates
  FOR UPDATE USING (
    current_user_role() IN ('SUPER_ADMIN', 'PASTOR')
  );

-- ============================================================
-- RLS POLICIES: departments
-- ============================================================

CREATE POLICY "departments_select_all_active" ON departments
  FOR SELECT USING (
    current_user_role() IS NOT NULL
    AND deleted_at IS NULL
  );

CREATE POLICY "departments_write_admin" ON departments
  FOR ALL USING (
    current_user_role() IN ('SUPER_ADMIN', 'PASTOR')
  );

-- ============================================================
-- RLS POLICIES: teams
-- ============================================================

CREATE POLICY "teams_select_all_active" ON teams
  FOR SELECT USING (
    current_user_role() IS NOT NULL
    AND deleted_at IS NULL
  );

CREATE POLICY "teams_write_admin" ON teams
  FOR ALL USING (
    current_user_role() IN ('SUPER_ADMIN', 'PASTOR', 'DEPARTMENT_HEAD')
  );

-- ============================================================
-- RLS POLICIES: groups
-- ============================================================

CREATE POLICY "groups_select_all_active" ON groups
  FOR SELECT USING (
    current_user_role() IS NOT NULL
    AND deleted_at IS NULL
  );

CREATE POLICY "groups_write_admin" ON groups
  FOR ALL USING (
    current_user_role() IN ('SUPER_ADMIN', 'PASTOR', 'DEPARTMENT_HEAD', 'TEAM_LEADER')
  );

-- ============================================================
-- RLS POLICIES: member_assignments
-- ============================================================

CREATE POLICY "ma_select_admin" ON member_assignments
  FOR SELECT USING (
    current_user_role() IN ('SUPER_ADMIN', 'PASTOR')
    AND deleted_at IS NULL
  );

CREATE POLICY "ma_select_dept_head" ON member_assignments
  FOR SELECT USING (
    current_user_role() = 'DEPARTMENT_HEAD'
    AND deleted_at IS NULL
    AND assignment_type = 'DEPARTMENT'
    AND assignment_id IN (SELECT id FROM departments WHERE head_user_id = auth.uid())
  );

CREATE POLICY "ma_select_team_leader" ON member_assignments
  FOR SELECT USING (
    current_user_role() = 'TEAM_LEADER'
    AND deleted_at IS NULL
    AND assignment_type = 'TEAM'
    AND assignment_id IN (SELECT id FROM teams WHERE leader_user_id = auth.uid())
  );

CREATE POLICY "ma_select_group_leader" ON member_assignments
  FOR SELECT USING (
    current_user_role() = 'GROUP_LEADER'
    AND deleted_at IS NULL
    AND assignment_type = 'GROUP'
    AND assignment_id IN (SELECT id FROM groups WHERE leader_user_id = auth.uid())
  );

CREATE POLICY "ma_write_admin" ON member_assignments
  FOR ALL USING (
    current_user_role() IN ('SUPER_ADMIN', 'PASTOR', 'DEPARTMENT_HEAD', 'TEAM_LEADER', 'GROUP_LEADER')
  );

-- ============================================================
-- RLS POLICIES: meetings
-- ============================================================

CREATE POLICY "meetings_select_relevant" ON meetings
  FOR SELECT USING (
    current_user_role() IS NOT NULL
    AND deleted_at IS NULL
  );

CREATE POLICY "meetings_write_leaders" ON meetings
  FOR ALL USING (
    current_user_role() IN ('SUPER_ADMIN', 'PASTOR', 'DEPARTMENT_HEAD', 'TEAM_LEADER', 'GROUP_LEADER')
  );

-- ============================================================
-- RLS POLICIES: attendance_records
-- ============================================================

CREATE POLICY "attendance_select_admin" ON attendance_records
  FOR SELECT USING (
    current_user_role() IN ('SUPER_ADMIN', 'PASTOR')
  );

CREATE POLICY "attendance_select_leaders" ON attendance_records
  FOR SELECT USING (
    current_user_role() IN ('DEPARTMENT_HEAD', 'TEAM_LEADER', 'GROUP_LEADER')
    AND meeting_id IN (
      SELECT id FROM meetings WHERE created_by = auth.uid() AND deleted_at IS NULL
    )
  );

CREATE POLICY "attendance_write_leaders" ON attendance_records
  FOR ALL USING (
    current_user_role() IN ('SUPER_ADMIN', 'PASTOR', 'DEPARTMENT_HEAD', 'TEAM_LEADER', 'GROUP_LEADER')
  );

-- ============================================================
-- RLS POLICIES: kpi_definitions / kpi_records
-- ============================================================

CREATE POLICY "kpi_def_select_admin" ON kpi_definitions
  FOR SELECT USING (
    current_user_role() IN ('SUPER_ADMIN', 'PASTOR')
    AND deleted_at IS NULL
  );

CREATE POLICY "kpi_def_select_leaders" ON kpi_definitions
  FOR SELECT USING (
    current_user_role() IN ('DEPARTMENT_HEAD', 'TEAM_LEADER', 'GROUP_LEADER')
    AND deleted_at IS NULL
    AND (
      (entity_type = 'DEPARTMENT' AND entity_id IN (SELECT id FROM departments WHERE head_user_id = auth.uid()))
      OR (entity_type = 'TEAM'       AND entity_id IN (SELECT id FROM teams       WHERE leader_user_id = auth.uid()))
      OR (entity_type = 'GROUP'      AND entity_id IN (SELECT id FROM groups      WHERE leader_user_id = auth.uid()))
    )
  );

CREATE POLICY "kpi_def_write_admin" ON kpi_definitions
  FOR ALL USING (
    current_user_role() IN ('SUPER_ADMIN', 'PASTOR')
  );

CREATE POLICY "kpi_records_select_admin" ON kpi_records
  FOR SELECT USING (
    current_user_role() IN ('SUPER_ADMIN', 'PASTOR')
  );

CREATE POLICY "kpi_records_select_leaders" ON kpi_records
  FOR SELECT USING (
    current_user_role() IN ('DEPARTMENT_HEAD', 'TEAM_LEADER', 'GROUP_LEADER')
    AND kpi_definition_id IN (
      SELECT id FROM kpi_definitions
      WHERE deleted_at IS NULL
        AND (
          (entity_type = 'DEPARTMENT' AND entity_id IN (SELECT id FROM departments WHERE head_user_id = auth.uid()))
          OR (entity_type = 'TEAM'   AND entity_id IN (SELECT id FROM teams       WHERE leader_user_id = auth.uid()))
          OR (entity_type = 'GROUP'  AND entity_id IN (SELECT id FROM groups      WHERE leader_user_id = auth.uid()))
        )
    )
  );

CREATE POLICY "kpi_records_write_leaders" ON kpi_records
  FOR ALL USING (
    current_user_role() IN ('SUPER_ADMIN', 'PASTOR', 'DEPARTMENT_HEAD', 'TEAM_LEADER', 'GROUP_LEADER')
  );

-- ============================================================
-- RLS POLICIES: follow_up_contacts / tasks / notes
-- ============================================================

CREATE POLICY "fuc_select_admin" ON follow_up_contacts
  FOR SELECT USING (
    current_user_role() IN ('SUPER_ADMIN', 'PASTOR')
    AND deleted_at IS NULL
  );

CREATE POLICY "fuc_select_follow_up" ON follow_up_contacts
  FOR SELECT USING (
    current_user_role() = 'FOLLOW_UP'
    AND deleted_at IS NULL
  );

CREATE POLICY "fuc_insert_follow_up" ON follow_up_contacts
  FOR INSERT WITH CHECK (
    current_user_role() IN ('SUPER_ADMIN', 'PASTOR', 'FOLLOW_UP')
  );

CREATE POLICY "fuc_update_admin" ON follow_up_contacts
  FOR UPDATE USING (
    current_user_role() IN ('SUPER_ADMIN', 'PASTOR')
  );

CREATE POLICY "fut_select_admin" ON follow_up_tasks
  FOR SELECT USING (
    current_user_role() IN ('SUPER_ADMIN', 'PASTOR')
    AND deleted_at IS NULL
  );

CREATE POLICY "fut_select_follow_up_assigned" ON follow_up_tasks
  FOR SELECT USING (
    current_user_role() = 'FOLLOW_UP'
    AND deleted_at IS NULL
    AND assigned_to = auth.uid()
  );

CREATE POLICY "fut_write_admin" ON follow_up_tasks
  FOR ALL USING (
    current_user_role() IN ('SUPER_ADMIN', 'PASTOR')
  );

CREATE POLICY "fut_insert_follow_up" ON follow_up_tasks
  FOR INSERT WITH CHECK (
    current_user_role() = 'FOLLOW_UP'
  );

CREATE POLICY "fut_update_follow_up_own" ON follow_up_tasks
  FOR UPDATE USING (
    current_user_role() = 'FOLLOW_UP'
    AND assigned_to = auth.uid()
    AND deleted_at IS NULL
  );

CREATE POLICY "fun_select_admin" ON follow_up_notes
  FOR SELECT USING (
    current_user_role() IN ('SUPER_ADMIN', 'PASTOR')
  );

CREATE POLICY "fun_select_follow_up" ON follow_up_notes
  FOR SELECT USING (
    current_user_role() = 'FOLLOW_UP'
    AND task_id IN (
      SELECT id FROM follow_up_tasks WHERE assigned_to = auth.uid() AND deleted_at IS NULL
    )
  );

CREATE POLICY "fun_insert_follow_up" ON follow_up_notes
  FOR INSERT WITH CHECK (
    current_user_role() IN ('SUPER_ADMIN', 'PASTOR', 'FOLLOW_UP')
    AND recorded_by = auth.uid()
  );

-- ============================================================
-- RLS POLICIES: medical_patients (COMPLETELY ISOLATED)
-- ============================================================

-- SUPER_ADMIN only: sees all
CREATE POLICY "medical_patients_select_super_admin" ON medical_patients
  FOR SELECT USING (
    current_user_role() = 'SUPER_ADMIN'
    AND deleted_at IS NULL
  );

-- MEDICAL: sees only their own created patients
CREATE POLICY "medical_patients_select_medical" ON medical_patients
  FOR SELECT USING (
    current_user_role() = 'MEDICAL'
    AND deleted_at IS NULL
    AND created_by = auth.uid()
  );

-- ALL OTHER ROLES: NO ACCESS (no policy = no access with RLS enabled)

CREATE POLICY "medical_patients_insert_medical" ON medical_patients
  FOR INSERT WITH CHECK (
    current_user_role() IN ('SUPER_ADMIN', 'MEDICAL')
    AND created_by = auth.uid()
  );

CREATE POLICY "medical_patients_update_own" ON medical_patients
  FOR UPDATE USING (
    current_user_role() IN ('SUPER_ADMIN', 'MEDICAL')
    AND created_by = auth.uid()
    AND deleted_at IS NULL
  );

-- ============================================================
-- RLS POLICIES: medical_visits
-- ============================================================

CREATE POLICY "medical_visits_select_super_admin" ON medical_visits
  FOR SELECT USING (
    current_user_role() = 'SUPER_ADMIN'
    AND deleted_at IS NULL
  );

CREATE POLICY "medical_visits_select_medical" ON medical_visits
  FOR SELECT USING (
    current_user_role() = 'MEDICAL'
    AND deleted_at IS NULL
    AND patient_id IN (
      SELECT id FROM medical_patients WHERE created_by = auth.uid() AND deleted_at IS NULL
    )
  );

CREATE POLICY "medical_visits_write_medical" ON medical_visits
  FOR ALL USING (
    current_user_role() IN ('SUPER_ADMIN', 'MEDICAL')
    AND patient_id IN (
      SELECT id FROM medical_patients WHERE created_by = auth.uid() AND deleted_at IS NULL
    )
  );

-- ============================================================
-- RLS POLICIES: sponsors (COMPLETELY ISOLATED)
-- ============================================================

CREATE POLICY "sponsors_select_finance" ON sponsors
  FOR SELECT USING (
    current_user_role() IN ('SUPER_ADMIN', 'FINANCE_ADMIN')
    AND deleted_at IS NULL
  );

-- ALL OTHER ROLES: NO ACCESS

CREATE POLICY "sponsors_write_finance" ON sponsors
  FOR ALL USING (
    current_user_role() IN ('SUPER_ADMIN', 'FINANCE_ADMIN')
  );

-- ============================================================
-- RLS POLICIES: sponsor_payments
-- ============================================================

CREATE POLICY "sponsor_payments_select_finance" ON sponsor_payments
  FOR SELECT USING (
    current_user_role() IN ('SUPER_ADMIN', 'FINANCE_ADMIN')
    AND deleted_at IS NULL
  );

CREATE POLICY "sponsor_payments_write_finance" ON sponsor_payments
  FOR ALL USING (
    current_user_role() IN ('SUPER_ADMIN', 'FINANCE_ADMIN')
  );

-- ============================================================
-- RLS POLICIES: workers (COMPLETELY ISOLATED)
-- ============================================================

CREATE POLICY "workers_select_hr" ON workers
  FOR SELECT USING (
    current_user_role() IN ('SUPER_ADMIN', 'HR_ADMIN')
    AND deleted_at IS NULL
  );

-- ALL OTHER ROLES: NO ACCESS

CREATE POLICY "workers_write_hr" ON workers
  FOR ALL USING (
    current_user_role() IN ('SUPER_ADMIN', 'HR_ADMIN')
  );

-- ============================================================
-- RLS POLICIES: worker_performance_reviews
-- ============================================================

CREATE POLICY "wpr_select_hr" ON worker_performance_reviews
  FOR SELECT USING (
    current_user_role() IN ('SUPER_ADMIN', 'HR_ADMIN')
  );

CREATE POLICY "wpr_write_hr" ON worker_performance_reviews
  FOR ALL USING (
    current_user_role() IN ('SUPER_ADMIN', 'HR_ADMIN')
  );

-- ============================================================
-- RLS POLICIES: worker_leave_requests
-- ============================================================

CREATE POLICY "wlr_select_hr" ON worker_leave_requests
  FOR SELECT USING (
    current_user_role() IN ('SUPER_ADMIN', 'HR_ADMIN')
  );

CREATE POLICY "wlr_write_hr" ON worker_leave_requests
  FOR ALL USING (
    current_user_role() IN ('SUPER_ADMIN', 'HR_ADMIN')
  );

-- ============================================================
-- RLS POLICIES: worker_recognitions
-- ============================================================

CREATE POLICY "wr_select_hr" ON worker_recognitions
  FOR SELECT USING (
    current_user_role() IN ('SUPER_ADMIN', 'HR_ADMIN')
  );

CREATE POLICY "wr_write_hr" ON worker_recognitions
  FOR ALL USING (
    current_user_role() IN ('SUPER_ADMIN', 'HR_ADMIN')
  );

-- ============================================================
-- RLS POLICIES: audit_logs (SUPER_ADMIN read; INSERT via service role)
-- ============================================================

-- SUPER_ADMIN: can read all audit logs
CREATE POLICY "audit_logs_select_super_admin" ON audit_logs
  FOR SELECT USING (
    current_user_role() = 'SUPER_ADMIN'
  );

-- All authenticated users: INSERT only (through service role in practice)
-- Direct user INSERT is allowed so the backend can log on behalf of the user.
-- The deny trigger prevents any UPDATE or DELETE regardless.
CREATE POLICY "audit_logs_insert_authenticated" ON audit_logs
  FOR INSERT WITH CHECK (
    auth.uid() IS NOT NULL
    AND user_id = auth.uid()
  );

-- NO UPDATE or DELETE policies exist (deny trigger enforces this at DB level too)

-- ============================================================
-- RLS POLICIES: notification_queue
-- ============================================================

CREATE POLICY "nq_select_admin" ON notification_queue
  FOR SELECT USING (
    current_user_role() IN ('SUPER_ADMIN', 'PASTOR', 'FINANCE_ADMIN', 'HR_ADMIN')
  );

CREATE POLICY "nq_select_own" ON notification_queue
  FOR SELECT USING (
    recipient_id = auth.uid()
    AND recipient_type = 'USER'
  );

CREATE POLICY "nq_write_service" ON notification_queue
  FOR ALL USING (
    current_user_role() IN ('SUPER_ADMIN', 'PASTOR', 'FINANCE_ADMIN', 'HR_ADMIN', 'FOLLOW_UP')
  );

-- ============================================================
-- RESTRICTED VIEWS (column-level isolation for cross-domain reads)
-- ============================================================

-- Finance-safe view: only exposes non-sensitive member columns to FINANCE_ADMIN
CREATE OR REPLACE VIEW v_members_finance_safe AS
  SELECT m.id, m.full_name, m.phone
  FROM members m
  WHERE m.deleted_at IS NULL
    AND m.id IN (SELECT member_link_id FROM sponsors WHERE member_link_id IS NOT NULL AND deleted_at IS NULL);

-- HR-safe view: only exposes non-sensitive member columns to HR_ADMIN
CREATE OR REPLACE VIEW v_members_hr_safe AS
  SELECT m.id, m.full_name, m.phone
  FROM members m
  WHERE m.deleted_at IS NULL
    AND m.id IN (SELECT member_link_id FROM workers WHERE member_link_id IS NOT NULL AND deleted_at IS NULL);

-- Follow-up view: limited columns for FOLLOW_UP role
CREATE OR REPLACE VIEW v_members_follow_up_safe AS
  SELECT m.id, m.full_name, m.phone, m.address, m.membership_status
  FROM members m
  WHERE m.deleted_at IS NULL;

-- ============================================================
-- VERIFICATION — all table names created in this migration
-- ============================================================
--
-- Tables created:
--   01. app_users
--   02. members
--   03. pending_member_data
--   04. member_duplicates
--   05. departments
--   06. teams
--   07. groups
--   08. member_assignments
--   09. meetings
--   10. attendance_records
--   11. kpi_definitions
--   12. kpi_records
--   13. follow_up_contacts
--   14. follow_up_tasks
--   15. follow_up_notes
--   16. medical_patients
--   17. medical_visits
--   18. sponsors
--   19. sponsor_payments
--   20. workers
--   21. worker_performance_reviews
--   22. worker_leave_requests
--   23. worker_recognitions
--   24. audit_logs
--   25. notification_queue
--
-- Views created:
--   v_members_finance_safe
--   v_members_hr_safe
--   v_members_follow_up_safe
--
-- Enums created:
--   user_role, member_status, gender, marital_status,
--   employment_type, sponsorship_tier, payment_status,
--   follow_up_stage, attendance_status, kpi_period, audit_action
--
-- End of migration 001_initial_schema.sql
