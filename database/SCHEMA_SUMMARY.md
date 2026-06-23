# Genesis Global CMS — Database Schema Summary

**Organization:** Genesis Global (Celestial Church of Christ)  
**Migration:** `001_initial_schema.sql`  
**Database:** Supabase PostgreSQL  
**Created:** 2026-06-23  

---

## Architecture Principles

| Principle | Implementation |
|-----------|---------------|
| Data Isolation | Four isolated domains: MEMBER, MEDICAL, SPONSOR, HR |
| No Sequential IDs | UUID primary keys via `gen_random_uuid()` everywhere |
| Soft Deletes | `deleted_at TIMESTAMPTZ` on every mutable table |
| Audit Trail | Append-only `audit_logs` table; UPDATE/DELETE blocked by trigger |
| Approval Workflow | Admin creates → ACTIVE; Follow-up/Medical creates → PENDING |
| Volunteer-First | No salary columns in `workers` table |
| Cross-Domain Access | Only SUPER_ADMIN; all others isolated by RLS |

---

## Extensions

- `uuid-ossp` — UUID generation utilities
- `pgcrypto` — Cryptographic functions

---

## Enums (11 total)

| Enum | Values |
|------|--------|
| `user_role` | SUPER_ADMIN, PASTOR, FINANCE_ADMIN, HR_ADMIN, DEPARTMENT_HEAD, TEAM_LEADER, GROUP_LEADER, FOLLOW_UP, MEDICAL, MEMBER |
| `member_status` | ACTIVE, INACTIVE, PENDING, PENDING_DUPLICATE_CHECK, PENDING_INFO_REQUESTED, REJECTED, MERGED |
| `gender` | MALE, FEMALE |
| `marital_status` | SINGLE, MARRIED, DIVORCED, WIDOWED |
| `employment_type` | VOLUNTEER, PART_TIME, FULL_TIME |
| `sponsorship_tier` | MONTHLY, QUARTERLY, ANNUAL, ONE_TIME |
| `payment_status` | PENDING, COMPLETED, FAILED, REFUNDED |
| `follow_up_stage` | FIRST_CONTACT, HOME_VISIT_SCHEDULED, ONBOARDING_CLASS_COMPLETED, DEPARTMENT_PLACEMENT, FULLY_INTEGRATED |
| `attendance_status` | PRESENT, ABSENT, EXCUSED |
| `kpi_period` | MONTHLY, QUARTERLY, ANNUAL |
| `audit_action` | CREATE, READ, UPDATE, DELETE, LOGIN, LOGOUT, APPROVE, REJECT, MERGE, VIEW_SENSITIVE |

---

## Tables (25 total)

### Domain: Core Auth

| # | Table | Key Columns | Notes |
|---|-------|-------------|-------|
| 1 | `app_users` | id (FK auth.users), email, role, member_id | Supabase auth integration; role-based identity |

### Domain: Member

| # | Table | Key Columns | Notes |
|---|-------|-------------|-------|
| 2 | `members` | id, full_name, phone, email, gender, membership_status, submitted_by, approved_by | Golden record; phone normalized to last 11 digits |
| 3 | `pending_member_data` | member_id, submitter_notes, admin_notes, additional_info_requested | Extra data during PENDING review phase |
| 4 | `member_duplicates` | new_member_id, existing_member_id, overall_score, status | Duplicate detection queue with per-field scoring |

### Domain: Structure

| # | Table | Key Columns | Notes |
|---|-------|-------------|-------|
| 5 | `departments` | id, name, head_user_id | Org chart root; unique names |
| 6 | `teams` | id, name, department_id, leader_user_id | Unique per department |
| 7 | `groups` | id, name, department_id, team_id, leader_user_id | Can be standalone under dept or nested in team |
| 8 | `member_assignments` | member_id, assignment_type, assignment_id, role_in_assignment | Many-to-many: members ↔ dept/team/group |

### Domain: Attendance

| # | Table | Key Columns | Notes |
|---|-------|-------------|-------|
| 9 | `meetings` | id, title, meeting_date, meeting_type, entity_id | Supports DEPARTMENT, TEAM, GROUP, CHURCH types |
| 10 | `attendance_records` | meeting_id, member_id, status | Unique constraint per (meeting, member) |

### Domain: KPI

| # | Table | Key Columns | Notes |
|---|-------|-------------|-------|
| 11 | `kpi_definitions` | id, name, entity_type, entity_id, target_value, period | Defines what to measure per entity |
| 12 | `kpi_records` | kpi_definition_id, period_start, period_end, actual_value | Unique per (definition, period_start) |

### Domain: Follow-Up

| # | Table | Key Columns | Notes |
|---|-------|-------------|-------|
| 13 | `follow_up_contacts` | id, full_name, phone, registered_by, member_id | New convert registrations; links to member once approved |
| 14 | `follow_up_tasks` | contact_id, assigned_to, stage, due_date, escalated_to | Task management per contact with stage progression |
| 15 | `follow_up_notes` | task_id, note_type, content, recorded_by | Per-task interaction log (CALL, VISIT, SMS, EMAIL, OTHER) |

### Domain: Medical (Completely Isolated)

| # | Table | Key Columns | Notes |
|---|-------|-------------|-------|
| 16 | `medical_patients` | id, full_name, member_link_id (hidden), consent_given | MEDICAL staff see only own patients; `member_link_id` never exposed |
| 17 | `medical_visits` | patient_id, visit_date, diagnosis, treatment, attended_by | Visit records; visible only within medical domain |

### Domain: Sponsor/Finance (Completely Isolated)

| # | Table | Key Columns | Notes |
|---|-------|-------------|-------|
| 18 | `sponsors` | id, full_name, sponsorship_tier, amount, member_link_id (hidden) | Visible only to SUPER_ADMIN and FINANCE_ADMIN |
| 19 | `sponsor_payments` | sponsor_id, amount, payment_method, status, flutterwave_tx_ref | Tracks Flutterwave, bank transfer, and cash payments |

### Domain: HR (Completely Isolated)

| # | Table | Key Columns | Notes |
|---|-------|-------------|-------|
| 20 | `workers` | id, full_name, employment_type, member_link_id (hidden), skills[] | No salary fields; volunteer-first design |
| 21 | `worker_performance_reviews` | worker_id, reviewer_id, self_score, supervisor_score, overall_score | 1–5 scale scoring |
| 22 | `worker_leave_requests` | worker_id, leave_type, start_date, end_date, status | PENDING → APPROVED/REJECTED |
| 23 | `worker_recognitions` | worker_id, recognition_type, title, awarded_by | AWARD, COMMENDATION, MILESTONE |

### Domain: System

| # | Table | Key Columns | Notes |
|---|-------|-------------|-------|
| 24 | `audit_logs` | user_id, action, resource_type, resource_id, old_values, new_values | Append-only; DB trigger blocks UPDATE/DELETE |
| 25 | `notification_queue` | recipient_id, channel, template_key, payload, status, scheduled_for | Multi-channel queue: SMS, EMAIL, WHATSAPP, IN_APP |

---

## Indexes Summary

| Table | Indexed Columns |
|-------|----------------|
| `members` | phone, email, membership_status, full_name (GIN text search) |
| `member_assignments` | member_id, assignment_id, assignment_type, composite |
| `attendance_records` | meeting_id, member_id, status |
| `follow_up_tasks` | assigned_to, stage, due_date, contact_id |
| `medical_patients` | phone, created_by, full_name (GIN text search) |
| `sponsors` | phone, email, sponsorship_tier, is_active |
| `sponsor_payments` | sponsor_id, status, next_due_date, payment_date |
| `audit_logs` | user_id, resource_type, resource_id, created_at (DESC), action |
| `notification_queue` | status, scheduled_for (WHERE PENDING), recipient_id, recipient_type |

---

## RLS Policy Matrix

| Table | SUPER_ADMIN | PASTOR | FINANCE_ADMIN | HR_ADMIN | DEPT_HEAD | TEAM_LEADER | GROUP_LEADER | FOLLOW_UP | MEDICAL | MEMBER |
|-------|:-----------:|:------:|:-------------:|:--------:|:---------:|:-----------:|:------------:|:---------:|:-------:|:------:|
| `members` | ALL | ALL | SEL (linked only) | SEL (linked only) | SEL (own dept) | SEL (own team) | SEL (own group) | SEL (limited cols) | NONE | SEL (own row) |
| `medical_patients` | ALL | NONE | NONE | NONE | NONE | NONE | NONE | NONE | SEL/INS/UPD (own) | NONE |
| `medical_visits` | ALL | NONE | NONE | NONE | NONE | NONE | NONE | NONE | ALL (own patients) | NONE |
| `sponsors` | ALL | NONE | ALL | NONE | NONE | NONE | NONE | NONE | NONE | NONE |
| `sponsor_payments` | ALL | NONE | ALL | NONE | NONE | NONE | NONE | NONE | NONE | NONE |
| `workers` | ALL | NONE | NONE | ALL | NONE | NONE | NONE | NONE | NONE | NONE |
| `audit_logs` | SEL ALL | NONE | NONE | NONE | NONE | NONE | NONE | NONE | NONE | NONE |

---

## Security Design Notes

### Hidden Link Columns
Three tables contain `member_link_id` that is a soft foreign key to `members.id` but is **never exposed** through RLS to the domain users:
- `medical_patients.member_link_id` — Medical staff cannot see this
- `sponsors.member_link_id` — Finance staff cannot see this
- `workers.member_link_id` — HR staff cannot see this

These columns are only accessible to SUPER_ADMIN and via service-role backend queries.

### Audit Log Immutability
The `audit_logs` table has two database triggers (`trg_audit_logs_deny_update` and `trg_audit_logs_deny_delete`) that raise exceptions on any UPDATE or DELETE attempt. Combined with RLS policies that grant INSERT-only to regular users, this ensures the audit trail is truly append-only.

### Approval Workflow
- **Admin-created members** (`submitted_by` with role SUPER_ADMIN/PASTOR/DEPT_HEAD/TEAM/GROUP_LEADER): backend should set `membership_status = 'ACTIVE'` immediately
- **Follow-up-created members**: `membership_status = 'PENDING'` by default; requires admin approval
- Duplicate detection creates entries in `member_duplicates` with `status = 'PENDING'`

### Column-Level Restriction
Since PostgreSQL RLS restricts rows (not columns), three restricted views enforce column-level isolation:
- `v_members_finance_safe` — id, full_name, phone only (for Finance domain)
- `v_members_hr_safe` — id, full_name, phone only (for HR domain)
- `v_members_follow_up_safe` — id, full_name, phone, address, membership_status (for Follow-up)

The API/backend layer must use these views instead of the base `members` table for non-admin roles.

---

## Trigger Summary

| Trigger | Table | Purpose |
|---------|-------|---------|
| `trg_*_updated_at` | All mutable tables | Auto-updates `updated_at` on every row modification |
| `trg_audit_logs_deny_update` | `audit_logs` | Raises exception on any UPDATE attempt |
| `trg_audit_logs_deny_delete` | `audit_logs` | Raises exception on any DELETE attempt |

---

## Helper Function

```sql
current_user_role() RETURNS user_role
```
Returns the authenticated user's role from `app_users` using `auth.uid()`. Used by all RLS policies. Defined as `STABLE SECURITY DEFINER`.
