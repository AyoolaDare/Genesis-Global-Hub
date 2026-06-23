# Genesis Global Church Management System
## Product Requirements Document (PRD) + AI System Prompt

**Organization:** Genesis Global (Celestial Church of Christ)  
**Date:** 2026-06-23  
**Version:** 1.0.0  
**Development Approach:** Vibe Coding (AI-Assisted)

---

# PART 1: PRODUCT REQUIREMENTS DOCUMENT

## 1. PRODUCT OVERVIEW

**Product Name:** Genesis Global Church Management System  
**Type:** Web Application (Responsive PWA)  
**Users:** Church administrators, department heads, team leaders, group leaders, follow-up workers, medical staff, finance team, HR team, and church members

**Current Problem:** Genesis Global manages church operations using Excel sheets and WhatsApp groups. This creates no centralized member database, no sponsor payment tracking, no systematic follow-up, no attendance tracking, no medical records, no performance visibility, duplicate records across departments, and manual repetitive tasks.

**Solution:** A unified church operations platform with 6 core modules.

---

## 2. CORE MODULES

| Module | Purpose | Primary Users |
|--------|---------|---------------|
| **Member Registry** | Golden record for all people data | All roles (scoped) |
| **Sponsorship & Donor Management** | Track sponsors, automate payments, send thank-yous | Finance Admin, Admin |
| **HR & Volunteer Management** | Track volunteers, departments, performance | HR Admin, Admin |
| **Medical Records** | Lightweight patient record keeping | Medical staff |
| **Follow-up & Onboarding** | Systematic new convert follow-up | Follow-up team |
| **Department/Team/Group Management** | Hierarchical structure, attendance, KPIs | All leadership roles |

---

## 3. USER ROLES & ACCESS MATRIX

| Role | Can See | Cannot See |
|------|---------|------------|
| **Super Admin** | Everything | Nothing |
| **Pastor/Overseer** | All members, all summaries | Individual donor details, individual patient details |
| **Finance Admin** | Sponsors, payments, revenue | Members, medical, HR |
| **HR Admin** | Workers, payroll, performance | Members, medical, sponsors |
| **Department Head** | Members in THEIR department only | Other departments, medical, sponsors, HR |
| **Team Leader** | Members in THEIR team only | Other teams, dept-level data, medical, sponsors, HR |
| **Group Leader** | Members in THEIR group only | Other groups, teams, depts, medical, sponsors, HR |
| **Follow-up Team** | Basic member info (name, phone, address, status) | Medical, financial, performance data |
| **Medical Team** | Their patients + name/phone/gender/age only | Member directory, church data, sponsors, HR |
| **Member (Self)** | Own profile, own giving history, own groups | Everything else |

**CRITICAL RULE:** Medical records are COMPLETELY isolated. Medical staff cannot browse the member directory. They search patients by name/phone within their own patient records only.

---

## 4. MEMBER REGISTRY (Golden Record)

### 4.1 Member Profile Fields
- Full Name, Phone, Email, Gender, Date of Birth
- Address, Marital Status
- Salvation Date, Water Baptism Status, Holy Spirit Baptism Status
- Membership Status (Active/Inactive/Pending)
- Photo
- Department(s), Team(s), Group(s) assignments
- Role in each assignment

### 4.2 Member Creation Flows

**FLOW A: Admin Creates Member (INSTANT)**
```
Admin fills form -> POST /api/v1/members -> Backend checks duplicates
  -> If clean: Create ACTIVE member immediately
  -> If duplicate: Show duplicate info, suggest merge
  -> Return 201 with member data
```

**FLOW B: Medical Staff Creates Member (PENDING)**
```
Medical staff fills form -> POST /api/v1/members/pending
  -> Create PENDING record
  -> Run duplicate detection
  -> If duplicate: status = "pending_duplicate_check"
  -> Notify all admins
  -> Medical staff CAN immediately add visit records to pending_id
  -> Admin reviews -> Approve/Reject/Request Info
```

**FLOW C: Follow-up Staff Creates Member (PENDING)**
```
Follow-up staff fills form -> POST /api/v1/members/pending
  -> Create PENDING record
  -> Run duplicate detection
  -> If duplicate: status = "pending_duplicate_check"
  -> Notify all admins
  -> Follow-up staff CAN immediately add follow-up notes to pending_id
  -> Admin reviews -> Approve/Reject/Request Info
```

### 4.3 During Pending Status
- Member does NOT appear in church directory
- Medical staff CAN add visit records (linked to pending_id)
- Follow-up staff CAN add outreach notes (linked to pending_id)
- Admin sees pending queue with all details
- Submitter gets notification when approved/rejected

### 4.4 Approval Actions
| Action | Result | Notifications |
|--------|--------|---------------|
| **Approve** | Member becomes ACTIVE, can assign departments/teams/groups | Submitter + new member (welcome SMS) |
| **Reject** | Record kept for audit, status = "rejected" | Submitter only |
| **Request Info** | Status = "pending_info_requested", back to submitter | Submitter only |
| **Merge** | Merge with existing member, transfer all records | Submitter + existing member |

### 4.5 Deduplication Rules
- Normalize phone: remove non-digits, handle 234 prefix, use last 11 digits
- Name similarity: exact match (100%), token match (100%), Jaccard (60%) + SequenceMatcher (40%)
- Overall score: exact phone = 60% + name (40%), otherwise name (70%) + email (30%)
- Flag at 85%+ overall score
- 100% phone match always flags even if name differs

### 4.6 Field Visibility by Role
| Field | Admin/Pastor | Dept Head | Team Lead | Group Lead | Follow-up | Medical | Finance | HR | Member |
|-------|-------------|-----------|-----------|------------|-----------|---------|---------|-----|--------|
| full_name | Yes | Yes | Yes | Yes | Yes | Yes* | Yes* | Yes* | Self |
| phone | Yes | Yes | Yes | Yes | Yes | Yes* | Yes* | Yes* | Self |
| email | Yes | Yes | Yes | Yes | Yes | No | No | No | Self |
| gender | Yes | Yes | Yes | Yes | Yes | Yes | No | No | Self |
| date_of_birth | Yes | Yes | Yes | Yes | Yes | Yes | No | No | Self |
| address | Yes | Yes | Yes | Yes | Yes | No | No | No | Self |
| marital_status | Yes | Yes | Yes | Yes | Yes | No | No | No | Self |
| salvation_date | Yes | Yes | Yes | Yes | Yes | No | No | No | No |
| water_baptism | Yes | Yes | Yes | Yes | Yes | No | No | No | No |
| holy_spirit_baptism | Yes | Yes | Yes | Yes | Yes | No | No | No | No |
| departments | Yes | Yes | Yes | Yes | Yes | No | No | No | Self |
| teams | Yes | Yes | Yes | Yes | Yes | No | No | No | Self |
| groups | Yes | Yes | Yes | Yes | Yes | No | No | No | Self |

*Medical sees name, phone, gender, DOB only for THEIR patients  
*Finance sees name, phone only for sponsors  
*HR sees name, phone only for workers

---

## 5. SPONSORSHIP & DONOR MANAGEMENT

### 5.1 Sponsor Profile
- Name, Phone, Email, Sponsorship Tier (Monthly/Quarterly/Annual/One-time)
- Amount, Preferred Communication Channel
- Payment History

### 5.2 Payment Tracking
- Flutterwave integration (linked to Wema Bank account)
- Online payments via Flutterwave
- Manual entry for bank transfers/cash
- Automated reconciliation via Flutterwave webhooks
- Manual verification dashboard for non-Flutterwave payments

### 5.3 Automations
- Instant SMS/WhatsApp on payment: "Thank you [Name] for your generous support of N[Amount]. God bless you!"
- Payment due reminders (3 days before, day of)
- Missed payment follow-up sequence
- Annual sponsorship summary report

---

## 6. HR & VOLUNTEER MANAGEMENT

### 6.1 Volunteer Profile (NO employee numbers visible)
- Name, Phone, Email, Department, Role
- Employment Type: Volunteer / Part-time / Full-time
- Start Date, Status (Active/Inactive)
- Time Commitment (self-reported hours/week)
- Skills & Interests
- Recognition/Awards

**NO salary information visible to general users. Finance admin sees payment records separately.**

### 6.2 Performance Tracking
- KPI dashboards per department
- Quarterly/Annual performance reviews with scoring
- 360-degree feedback (peer, supervisor, self)
- Attendance tracking

### 6.3 Leave Management
- Request, approval workflow, balance tracking

---

## 7. MEDICAL RECORDS (Lightweight)

### 7.1 Patient Record
- Patient Name, Phone, Gender, Age
- Church Member? (Yes/No - backend link only, invisible to medical staff)
- Visit Log: Date, Complaints, Diagnosis, Treatment, Medications
- Medical History: Allergies, Chronic Conditions, Previous Visits

### 7.2 Critical Isolation Rules
- Medical staff sees ONLY their own patients
- Search restricted to their patient records by name/phone
- Cannot click to see full member profile
- Cannot see member's department, group, or sponsor status
- If patient is a church member: backend silently links, but medical staff only sees "Linked to member: Yes" with NO clickable link

### 7.3 Privacy
- Role-based access (only medical team + admin)
- Consent checkbox for data collection
- Encrypted storage

---

## 8. FOLLOW-UP & ONBOARDING

### 8.1 New Convert Registration
- Name, Contact, Address, Prayer Requests
- How they heard about the church

### 8.2 Follow-up Stages
1. First Contact (within 48 hours)
2. Home Visit Scheduled
3. Onboarding Class Completed
4. Department Placement
5. Fully Integrated Member

### 8.3 Task Management
- Auto-assign to follow-up team member based on location/availability
- Daily task list: who to call/visit
- Overdue escalation (uncontacted after 72 hours -> supervisor alert)

### 8.4 Automations
- Auto-reminder: "You have 3 pending follow-ups due today"
- Auto-escalation: Uncontacted new convert after 72h
- Welcome SMS/Email sequence

---

## 9. DEPARTMENT / TEAM / GROUP MANAGEMENT

### 9.1 Hierarchical Structure
```
Church
├── Departments (Follow-up, Medical, Choir, Ushering, etc.)
│   ├── Teams (e.g., Follow-up -> New Converts Team, Backsliders Team)
│   └── Groups (e.g., House Fellowship Groups, Bible Study Groups)
```

### 9.2 Member Assignment
- One member can belong to multiple departments/teams/groups
- Track join date and role for each assignment

### 9.3 Attendance Tracking
- Meeting/event attendance with manual check-in or QR code
- Attendance rate analytics per group/department/team

### 9.4 KPI Tracking
- Admin-configurable KPIs per department/team/group
- Grace-based targets (ministry health, not performance evaluation)
- Monthly tracking with trends
- Dashboards showing progress bars, comparisons, rankings

**Example KPIs:**
| Department | KPI | Target |
|-----------|-----|--------|
| Follow-up | New Converts Onboarded | 40/month |
| Follow-up | Members Completed Foundation Class | 25/month |
| Follow-up | Backsliders Restored | 15/month |
| Choir | Rehearsal Attendance | 90% |
| Medical | Patients Attended | Track monthly |

---

## 10. AUTOMATION RULES

| Trigger | Action |
|---------|--------|
| Flutterwave payment received | Send thank-you SMS + update sponsor ledger + notify finance |
| Sponsor payment overdue 7 days | Send gentle reminder + notify sponsorship coordinator |
| New convert registered | Create follow-up task + send welcome SMS + add to "New Converts" group |
| Follow-up task overdue | Escalate to supervisor + send alert |
| Member not attended any group in 30 days | Add to "At Risk" list + notify follow-up team |
| Medical visit completed | Schedule follow-up appointment reminder |
| Quarterly performance review due | Notify supervisor + generate review form |
| Duplicate member detected | Add to merge review queue + notify admin |

---

## 11. TECHNOLOGY STACK

| Layer | Technology | Hosting |
|-------|-----------|---------|
| Frontend | Flutter Web | Vercel (Free) |
| Backend API | Python FastAPI | Render (Free) |
| Database | PostgreSQL | Supabase (Free) |
| Cache/Queue | Redis | Upstash (Free) |
| File Storage | Supabase Storage | Supabase (Free) |
| Payments | Flutterwave API | External |
| SMS/WhatsApp | Termii | External |
| Email | SendGrid/Resend | External |

---

## 12. DATA PRIVACY & SECURITY

- **Medical records:** Completely isolated domain, encrypted at rest
- **Financial data:** Isolated domain, no cross-reference with member profiles
- **HR data:** Isolated domain, no cross-reference with general members
- **Audit trail:** Every data access and modification logged (timestamp, user, action, record)
- **Role-based access:** Enforced at API level AND database level (Supabase RLS)
- **No internal IDs on frontend:** Backend handles all referencing
- **Soft deletes:** Never hard delete, use deleted_at timestamp

---

## 13. SUCCESS METRICS

- [ ] Admin can add members instantly
- [ ] Medical/Follow-up submissions go to pending queue
- [ ] Department Heads see only their department data
- [ ] Team Leaders see only their team data
- [ ] Group Leaders see only their group data
- [ ] Medical staff see only their patients
- [ ] Finance sees only sponsors
- [ ] HR sees only workers
- [ ] Sponsors receive instant thank-you on payment
- [ ] Payment reminders send automatically
- [ ] Attendance can be marked per group/team/department
- [ ] KPIs display with trends
- [ ] Duplicate members flagged before approval
- [ ] All access attempts logged

---

# PART 2: AI SYSTEM PROMPT

## SYSTEM PROMPT FOR AI CODING ASSISTANT

```
You are an expert full-stack developer building the Genesis Global Church Management System. You write production-quality code following these strict rules:

## PROJECT CONTEXT
- Organization: Genesis Global (Celestial Church of Christ)
- Stack: Flutter Web (Frontend) + Python FastAPI (Backend) + Supabase PostgreSQL + Upstash Redis
- Hosting: Vercel (Frontend) + Render (Backend) - FREE TIER ONLY
- Development Approach: Vibe Coding (AI-assisted rapid development)

## CRITICAL ARCHITECTURAL RULES (NEVER BREAK THESE)

1. DATA ISOLATION (NON-NEGOTIABLE)
   - Four isolated domains: MEMBER, MEDICAL, SPONSOR, HR
   - Medical staff CANNOT access member directory - they search their own patients only
   - Finance CANNOT see member addresses or medical data
   - HR CANNOT see medical records or sponsor payments
   - Cross-domain access ONLY for Super Admin

2. NO INTERNAL IDs ON FRONTEND
   - UUIDs exist in backend only
   - Frontend never displays: employee numbers, patient numbers, transaction IDs, database IDs
   - Backend handles all internal referencing transparently

3. VOLUNTEER-FIRST MODEL
   - All workers are volunteers
   - NO salary fields visible to general users
   - NO employee numbers visible anywhere
   - Time commitment is self-reported, not enforced

4. APPROVAL WORKFLOW
   - Admin creates member = INSTANT ACTIVE
   - Medical/Follow-up creates member = PENDING ADMIN APPROVAL
   - During pending: submitter can still add records
   - Admin reviews: Approve / Reject / Request Info / Merge

5. GRACE-BASED KPIs
   - Track ministry HEALTH, not individual performance
   - No punitive consequences for missing targets
   - Collaborative target setting

## TECH STACK DETAILS

Frontend:
- Flutter Web (responsive PWA)
- Riverpod for state management
- GoRouter for navigation
- Dio for HTTP client
- SecureStorage for JWT tokens

Backend:
- Python FastAPI
- SQLAlchemy ORM (never raw SQL with user input)
- Pydantic for validation
- JWT authentication
- Celery + Upstash Redis for background jobs
- Supabase Auth for user management

Database:
- Supabase PostgreSQL with Row Level Security (RLS)
- UUID primary keys everywhere
- Soft deletes (deleted_at timestamp)
- Audit logs table (append-only)

## API DESIGN RULES

- Response format ALWAYS:
  {"success": true|false, "data": {...}|null, "meta": {page, per_page, total, total_pages}, "message": "..."}

- Error format ALWAYS:
  {"success": false, "error": {"code": "UPPER_SNAKE_CASE", "message": "...", "details": null}}

- Pagination: default page=1, per_page=20, max per_page=100
- HTTP 403 for insufficient permissions (not 401)
- Scope filtering at database query level, not just API level

## FLUTTER IMPLEMENTATION RULES

- Role-based routing: redirect to role-specific dashboard after login
- Dynamic sidebar based on user role
- Role-aware tabs on member detail screen
- Skeleton loading states for all async operations
- Search debounce: 300ms
- Form validation before submission
- Confirmation dialogs for destructive actions

## CODE QUALITY RULES

- Type hints everywhere (Python)
- Null safety (Flutter)
- Error handling on EVERY async operation
- Loading states for EVERY async UI operation
- Form validation client-side AND server-side
- Never trust user input - validate everything
- Never expose stack traces to frontend
- Log all errors with context

## WHEN IMPLEMENTING FEATURES

1. Start with database schema (migrations)
2. Create Pydantic schemas (request/response)
3. Implement service layer (business logic)
4. Create API router (endpoints)
5. Add middleware (auth, scope, audit)
6. Build Flutter screen
7. Add Riverpod provider
8. Connect UI to API
9. Test the feature end-to-end

## IF ASKED TO IMPLEMENT A FEATURE

- Ask clarifying questions if requirements are unclear
- Suggest the simplest viable implementation first
- Highlight any security implications
- Provide complete, working code (not pseudocode)
- Include error handling
- Include loading states
- Include validation
- Write code that works on FREE TIER hosting

## NEVER

- Expose medical records to non-medical roles
- Expose sponsor payments to non-finance roles
- Expose worker performance to non-HR roles
- Hard delete records (always soft delete)
- Skip input validation
- Return raw database errors to frontend
- Store passwords in plain text
- Use sequential integer IDs (always UUID)
- Show internal database IDs to users
```

---

*End of PRD + System Prompt Document*
