# Genesis Global CMS — Security & Functional Audit Report

**Date:** 2026-07-04
**Scope:** `C:\Users\LENOVO\Desktop\CMS\Church-App` (FastAPI backend + Flutter web frontend + Supabase PostgreSQL + Celery/Redis workers, deployed on Render/Vercel)
**Method:** Full code-trace of every payment, PII, and messaging path. No code was changed. Every claim below cites the file and line it was verified against.

---

## PART 1 — DISCOVERY

### Stack (identified from code, not assumed)

| Layer | Technology | Evidence |
|---|---|---|
| Backend | Python 3.11 / FastAPI 0.115 | `backend/requirements.txt`, `render.yaml` |
| ORM | SQLAlchemy 2.0 (fully parameterized) | `backend/app/models/*` |
| DB | Supabase PostgreSQL | `app/database.py` |
| Auth | Supabase Auth (password check) + internal JWT (HS256, python-jose) | `app/auth/service.py:42-80`, `app/core/security.py` |
| Queue | Celery + Upstash Redis, Celery Beat scheduler | `app/workers/*`, `render.yaml` |
| Payments | Flutterwave v3 (Standard checkout client exists) | `app/integrations/flutterwave.py` |
| SMS/WhatsApp | Termii | `app/integrations/termii.py` |
| Email | Brevo (a `sendgrid.py` file is a Brevo compatibility shim, not SendGrid) | `app/integrations/brevo.py`, `app/integrations/__init__.py:7` |
| Frontend | Flutter web (Riverpod, Dio, go_router), tokens in `flutter_secure_storage` | `frontend/pubspec.yaml`, `frontend/lib/core/api/api_client.dart` |

### Portals implemented (backend roles ⇄ frontend feature folders)

| Portal / Role | Frontend | Backend routers | Server-side enforcement |
|---|---|---|---|
| SUPER_ADMIN | `features/admin` | all | `require_role` / wildcard permission |
| PASTOR | `features/admin` (shared) | members, structure, kpi, dashboard | `require_role` |
| FINANCE_ADMIN | `features/finance` | sponsors, payments, finance dashboard | `require_role("SUPER_ADMIN","FINANCE_ADMIN")` on all 11 endpoints ✔ |
| HR_ADMIN | `features/hr` | hr (13 endpoints) | `require_role` ✔ |
| DEPARTMENT_HEAD / TEAM_LEADER / GROUP_LEADER | own folders | structure, attendance, kpi | JWT-embedded scope + `ScopeFilter` — **but see gaps F-04** |
| FOLLOW_UP | `features/follow_up` | follow_up (12 endpoints) | `require_role` ✔ |
| MEDICAL | `features/medical` | medical (10 endpoints) | `require_role("SUPER_ADMIN","MEDICAL")` on all ✔ |
| MEMBER (self) | `features/member_self` | profile/self endpoints | role-blocked from registry ✔ |

Overall: auth dependencies are present on **every** endpoint inspected (92 endpoints across 10 routers + auth). The gaps are in *scope* checks (authenticated-but-wrong-tenant), not missing authentication.

Test suite exists: 14 files, ~300 test functions incl. `test_data_isolation.py`, `test_role_access.py`, `test_webhooks.py`.

---

## PART 2 — PORTAL FUNCTIONAL AUDIT (summary table)

| Portal | Dashboard real data? | CRUD | Pagination | Backend authz | Gaps found |
|---|---|---|---|---|---|
| Finance | ✔ real queries (`sponsor_service.py:300-405`) | ✔ | ✔ (`per_page` capped 100) | ✔ | **Payment initiation/verification are mocks — F-01/F-02** |
| Medical | ✔ (`medical_service.py:234-272`) | ✔ | ✔ | ✔ strong (`created_by` filter on every query) | Super-admin sees only own patients (design decision, F-16) |
| Members/Admin | ✔ | ✔ incl. approve/reject/merge | ✔ | ✔ + field stripping per role | Audit trail lacks old/new values (F-15) |
| Structure (dept/team/group) | ✔ | ✔ | ✔ | list endpoints scoped ✔ | **`{id}/members` endpoints NOT scope-checked — F-04** |
| Attendance | ✔ | ✔ | ✔ | create/mark scoped ✔ | **member history & stats NOT scope-checked — F-04** |
| Follow-up | ✔ | ✔ | ✔ | ✔ | none material found in trace |
| HR | ✔ | ✔ | ✔ | ✔ | not deep-traced (lower risk) |

---

## PART 3 — SPONSOR / FLUTTERWAVE MODULE (highest risk)

### Confidence ratings

| Sub-area | Rating | Evidence |
|---|---|---|
| 1. Link generation | **LOW** | Mocked — see F-01 |
| 2. Payment monitoring (webhook) | **LOW** | Wrong signature scheme (F-02), tx_ref mismatch (F-03), no re-verification (F-06), partial idempotency (F-07), no reconciliation (F-09) |
| 3. Sponsor notifications | **LOW-MEDIUM** | Thank-you correctly fires from backend events, never from frontend — but admin "verify" fires it without any real payment check (F-01), and queued thank-yous never send (F-08) |
| 4. Data integrity | **LOW** | Webhook trusts payload amount (F-06); admin verify trusts nothing at all (F-01) |
| Secret-key handling | **HIGH** | `FLUTTERWAVE_SECRET_KEY` only in env (`config.py:47`, `render.yaml`), used only server-side; zero Flutterwave code in the frontend (verified by grep of `frontend/lib`); no keys committed (`git ls-files` + secret-pattern grep clean) |

### F-01 — CRITICAL: The live payment code path is a mock
- `initiate_flutterwave_payment` (`app/services/sponsor_service.py:214-250`) **never calls Flutterwave**. It fabricates `https://checkout.flutterwave.com/v3/hosted/pay/{tx_ref}` — a URL that does not correspond to any created payment. Comment in code: *"Returns a mock response for now."*
- `verify_flutterwave_payment` (`sponsor_service.py:253-295`) marks any PENDING payment **COMPLETED without contacting Flutterwave** (*"For now, mark as completed"*), sets `verified_by`, and queues the thank-you. `GET /payments/verify/{tx_ref}` (`app/routers/sponsors.py:203`) exposes this to any FINANCE_ADMIN → fake revenue records + thank-you messages with zero payment.
- The real, well-written client (`app/integrations/flutterwave.py` — `initiate_payment`, `verify_payment`, `build_tx_ref`) is **dead code**: grep confirms nothing calls it except the redirect-verify handler's `get_transaction_by_ref`.
- The Flutter frontend contains **no payment initiation or verification calls at all** (`grep flutterwave|verify|initiate` over `frontend/lib` → only manual sponsor/payment CRUD). So the only working payment feature today is *manual payment recording* by finance admins.

### F-02 — CRITICAL: Webhook signature verification uses the wrong scheme
`verify_webhook_signature` (`app/integrations/flutterwave.py:210-236`) computes **HMAC-SHA256 of the request body** keyed with `FLUTTERWAVE_SECRET_KEY`. Flutterwave v3 does not sign the body — it sends your dashboard-configured **secret hash verbatim** in the `verif-hash` header. Result: **every genuine Flutterwave webhook fails verification and is rejected 400** at `app/routers/webhooks.py:73`. There is also no `FLUTTERWAVE_SECRET_HASH` setting in `config.py` at all. Payments can only ever be confirmed via the redirect-verify endpoint — which the frontend never calls.

### F-03 — CRITICAL: tx_ref formats are incompatible between initiation and webhook
Initiation writes `GEN-GLOBAL-{sponsor_id}-{unix_ts}` (`sponsor_service.py:229`); the webhook handler parses only `genesis-{uuid}-{suffix}` (`app/integrations/webhook_handlers.py:84-103`, checks `parts[0] == "genesis"`). Even with F-02 fixed, no webhook could ever match a sponsor. (`build_tx_ref` in `flutterwave.py:238` produces the right format but is never called.)

### F-06 — HIGH: Webhook handler trusts payload without API re-verification
`handle_flutterwave_payment` (`webhook_handlers.py:21-201`) takes `status`, `amount`, `currency` straight from the webhook body and writes them to the payment record. It never calls `GET /transactions/{id}/verify`, and never compares the paid amount against the expected `payment.amount`.

### F-07 — HIGH: Webhook path is not idempotent for notifications
The redirect-verify path guards with `payment.status != COMPLETED` (`webhook_handlers.py:264`), but the webhook path has **no completed check** (`webhook_handlers.py:146-174`): a re-delivered webhook re-updates the record and **queues a second thank-you SMS/email** (`thank_you_sent_at` is set by the task but never consulted before sending).

### F-09 — HIGH: No missed-webhook reconciliation
None of the 7 Celery Beat jobs (`app/workers/beat_schedule.py`) re-queries Flutterwave for PENDING `SponsorPayment` rows. A missed webhook + user closing the redirect page = payment permanently stuck PENDING.

### F-10 — MEDIUM: Worker availability undermines webhook processing
Webhook handling is queued to Celery (`webhooks.py:106-118`) and the endpoint returns 200 even if **queuing fails** (comment acknowledges the webhook will then never be retried). `render.yaml` runs worker+beat on the free plan with an explicit note that workers spin down; queued Redis tasks survive, but a dead broker at enqueue time = silently lost payment event.

---

## PART 4 — COMMUNICATIONS (SMS & EMAIL)

What works: Termii and Brevo clients make real HTTP calls with logging (`termii.py`, `brevo.py:58-77`); direct Celery tasks (`send_sms`, `send_payment_thank_you`, `send_payment_reminder`, `send_admin_notification`) have retries with exponential backoff and update queue status (`notification_tasks.py:33-98`). Scheduler exists and is real (Celery Beat, 7 jobs, `beat_schedule.py`). Phone normalization to E.164/234 exists (`termii.py:71-112`); emails validated via Pydantic `EmailStr`.

### F-08 — HIGH: DB-queued notifications can never send (payload contract mismatch)
`queue_notification` inserts rows whose payload is template variables (`{"sponsor_name", "amount", ...}` with `template_key="PAYMENT_THANK_YOU"`) — `sponsor_service.py:137-151, 280-293`. The processor `process_notification_queue` (`notification_tasks.py:460-504`) **ignores `template_key` entirely** and reads only `payload["phone"]` / `payload["message"]` / `payload["email"]` — which are never present. Every queued item silently retries 5× then goes FAILED. **Net effect: thank-you messages for manually recorded payments are never delivered**, with no alert.

### F-11 — MEDIUM: Silent send failures in `NotificationService`
`queue_sms` / `queue_email` (`app/services/notification_service.py:33-56`) wrap everything in `except: pass` — the exact "swallowed exception" anti-pattern. `queue_sms` also misuses `asyncio.get_event_loop()` from sync context (deprecated; can raise or attach to a dead loop).

### F-12 — MEDIUM: Duplicate/overlapping overdue-reminder logic
`check_overdue_payments` (daily) and `send_overdue_payment_alerts` (weekly) both SMS the 7+ days-overdue cohort; the weekly job **ignores `reminder_sent_at`** (`payment_tasks.py:242-296`) so sponsors get repeat messages regardless of recency. Queue processor also lacks row locking (`SELECT … FOR UPDATE SKIP LOCKED`) so overlapping runs may double-send (partially mitigated by the 240s beat `expires`).

### F-13 — MEDIUM: No opt-out/consent handling for SMS
No `sms_opt_out`/unsubscribe field exists on Sponsor or Member; templates have no opt-out language. NDPR/Termii policy exposure.

---

## PART 5 — MEDICAL SECTION

**What it does (from code):** standalone patient registry (`medical_patients`) + visit records (`medical_visits`) with complaints/diagnosis/treatment/medications, per-practitioner dashboard. Silent linkage to church members by normalized phone, exposing only a boolean `is_church_member`.

**Verdict: this is the best-engineered module.** Evidence:
- Every query filters `created_by == current_user.id` (`medical_service.py:85-122, 195-229`) — practitioner-level isolation, verified on get/list/search/visits/update.
- All 10 endpoints require `SUPER_ADMIN|MEDICAL` (`routers/medical.py:95-214`).
- `member_link_id` is excluded from every serializer (`medical.py:56-73`) and the model documents it as backend-only.
- Sensitive GETs are audit-logged as metadata only — no request/response bodies are persisted (`middleware/audit.py:35-40, 244-253`), so no PHI leaks into audit rows.
- Role field-stripping removes `medical_info` from member payloads for FINANCE/HR/FOLLOW_UP/MEMBER (`auth/permissions.py:239-303`).

Gaps:
- **F-14 — MEDIUM:** `/members/lookup` is open to the MEDICAL role and returns any member's name+phone (`routers/members.py:148-174`) — contradicting the module's own "medical staff cannot access member endpoints" rule; combined with silent phone-matching, a medical user can probe membership.
- **F-16 — LOW (design decision):** even SUPER_ADMIN only sees self-created patients — no supervisory/continuity access if a practitioner leaves. Confirm this is intended.
- No application-level encryption at rest for diagnosis/treatment text — relies on Supabase disk encryption + access control. Acceptable baseline; column-level crypto is an optional hardening step.

---

## PART 6 — GENERAL SECURITY AUDIT

| Check | Verdict | Evidence |
|---|---|---|
| Password hashing | **PASS** | Delegated to Supabase Auth (bcrypt) (`auth/service.py:42-80`); local passlib/bcrypt(12) utilities exist for completeness (`core/security.py:31`) |
| JWT expiry / revocation | **PASS w/ notes** | 24h access + 30d refresh; `jti` blacklisting in Redis on logout (`security.py:151-190`). Notes: 24h is long; scope embedded in JWT goes stale until refresh (F-17); blacklist **fails open** if Redis is down |
| Token storage (frontend) | **PASS** | `flutter_secure_storage` with `encryptedSharedPreferences` (`api_client.dart:237`) — best available in this framework |
| Server-side authorization | **PARTIAL** | All endpoints authenticated; role checks solid; **scope checks missing on 5 read endpoints → F-04** |
| SQL injection | **PASS** | ORM everywhere; the few `text()` uses are parameterized (`security.py:220-238`) |
| Secrets | **PASS** | Nothing committed (git-tracked-file scan + key-pattern grep clean); all via env (`config.py`, `render.yaml` `sync:false`); prod validator rejects default JWT secret (`config.py:78-105`). Minor: Termii key in query string in health check (`main.py:183`) — F-20 |
| CORS | **FAIL** | `allow_origin_regex` accepts **any** `https://*.vercel.app` / `*.onrender.com` with `allow_credentials=True` (`middleware/cors.py:55-64`). Anyone can host on those domains. Impact tempered because auth is header-token, not cookies — F-05 (Medium) |
| Input validation | **PASS** | Pydantic schemas on all bodies; `Query` constraints on pagination; phone normalization |
| Rate limiting | **PASS w/ notes** | Global 200/min + auth 5/15min, both Redis (`middleware/rate_limit.py`); **fails open** on Redis outage, and client-spoofable first-hop `X-Forwarded-For` used for identity — F-18 |
| Error handling | **PASS** | Global handlers never leak traces (`main.py:295-316`); docs/openapi disabled in prod (`main.py:76-78`) |
| Dependency audit | **ACTION NEEDED** | `python-jose==3.3.0` has known CVEs (CVE-2024-33663 algorithm-confusion, CVE-2024-33664 DoS) → upgrade ≥3.4 — F-19. `passlib 1.7.4` unmaintained (bcrypt 4.x warning). Run `pip-audit` in CI |
| Sensitive data in logs | **PASS w/ notes** | No passwords/tokens logged; audit rows are metadata-only. Note: Flutterwave error logs include full response bodies (`flutterwave.py:108-113`) — fine, but keep an eye on PII in provider error payloads |
| Audit trail completeness | **PARTIAL** | Who/when/what-resource logged for all writes + sensitive reads (`middleware/audit.py`), but `old_values/new_values` only populated for login/logout — "what changed" is not captured for edits (F-15) |

### F-04 — HIGH: Missing scope checks on member-data read endpoints
Any authenticated user of **any** role (including MEMBER and MEDICAL) can read any department/team/group roster (names + phones) and any member's attendance history:
- `GET /structure/departments/{dept_id}/members` — `routers/structure.py:147-157` (only `get_current_user`)
- `GET /structure/teams/{team_id}/members` — `structure.py:228-239`
- `GET /structure/groups/{group_id}/members` — `structure.py:315-326`
- `GET /attendance/members/{member_id}/attendance` — `routers/attendance.py:159-168`
- `GET /attendance/stats/{entity_type}/{entity_id}` — `attendance.py:171-182`

The infrastructure to fix this already exists (`require_scope`, `ScopeFilter` in `auth/dependencies.py:157-363`) — it just isn't applied here.

### Other Medium/Low
- **F-05 (Medium):** CORS wildcard-by-regex (above).
- **F-17 (Medium):** JWT-embedded scope stale up to 24h after a leader is unassigned; `is_active` is re-checked per request, scope is not.
- **F-18 (Medium):** rate limit + blacklist fail open; spoofable XFF identity.
- **F-19 (Medium):** python-jose 3.3.0 CVEs.
- **F-20 (Low):** Termii API key in URL query (`main.py:183`); `/health/integrations` is unauthenticated (status-only info disclosure).
- **F-21 (Low):** `tx_ref` uses second-resolution timestamp (`sponsor_service.py:229`) — collision possible for same sponsor within one second; confirm DB unique constraint on `tx_ref`.
- **F-22 (Low):** `sendgrid.py` naming (it's a Brevo shim) invites confusion; two parallel notification paths (direct Celery vs DB queue) with different reliability semantics.

---

## PART 7 — PRIORITIZED FIX PLAN

### Batch 1 — Payments correctness (CRITICAL) — est. 1–2 days
1. **F-01:** Wire `initiate_flutterwave_payment` to the real `FlutterwaveClient.initiate_payment` (use `build_tx_ref`); return Flutterwave's actual `data.link`. Rewrite `verify_flutterwave_payment` to call `get_transaction_by_ref`/`verify_payment` and only mark COMPLETED on a verified `successful` + amount/currency match.
2. **F-02:** Add `FLUTTERWAVE_SECRET_HASH` setting; replace the HMAC computation with a constant-time compare of the `verif-hash` header against the configured hash (keep `hmac.compare_digest`).
3. **F-03:** Single tx_ref builder (`genesis-{sponsor_id}-{suffix}`) used by both initiation and parsing — or better, stop parsing sponsor from tx_ref and look up the local `SponsorPayment` row by `tx_ref`.
4. **F-06:** In the webhook handler, call `verify_payment(data.id)` before crediting; compare verified amount/currency to the pending record.
5. **F-07:** Guard the webhook path with `if payment.status == COMPLETED: return` before updating/notifying.

### Batch 2 — Data exposure (HIGH) — est. 0.5–1 day
6. **F-04:** Apply `require_scope`/role gates to the five unscoped endpoints (SUPER_ADMIN/PASTOR global; DEPT_HEAD/TEAM_LEADER/GROUP_LEADER within scope; block MEDICAL/FINANCE/HR/MEMBER).
7. **F-14:** Remove MEDICAL (and reconsider FINANCE/HR) from `/members/lookup`, or reduce it to an exact-match yes/no linking API.
8. **F-05:** Drop the `allow_origin_regex` wildcard; pin the exact Vercel production/preview URLs via `ALLOWED_ORIGINS`.

### Batch 3 — Notifications actually deliver (HIGH) — est. 1 day
9. **F-08:** Make `process_notification_queue` render templates from `template_key` + payload and resolve recipient contact from `recipient_type`/`recipient_id` (or store phone/email/message at enqueue time). Add a failure-alert (admin email when items hit FAILED).
10. **F-11:** Replace `except: pass` in `NotificationService` with logging + Celery task dispatch.
11. **F-12:** Honor `reminder_sent_at` in the weekly job; add `FOR UPDATE SKIP LOCKED` (or status=PROCESSING claim) in the queue processor.

### Batch 4 — Reconciliation & resilience (HIGH/MEDIUM) — est. 1 day
12. **F-09:** New beat job (e.g. hourly): query PENDING `SponsorPayment` older than 15 min, verify each against Flutterwave, complete/fail accordingly (reuses Batch 1 verification code).
13. **F-10:** Alert (admin email/log-critical) when webhook enqueue fails; document worker uptime requirement or move webhook processing inline with a fast DB write + background verify.

### Batch 5 — Hardening (MEDIUM/LOW) — est. 1 day
14. **F-19:** `python-jose>=3.4`; add `pip-audit` to CI. Consider migrating passlib→direct `bcrypt`.
15. **F-17:** Reduce access-token life (1–4h) and/or re-derive scope from DB per request for scoped roles.
16. **F-18:** Fail-closed option for auth rate limit; trust only the last proxy hop for client IP.
17. **F-15:** Populate `old_values/new_values` in `write_audit_log` for member/sponsor/HR edits.
18. **F-20/21/22:** Termii key to header if supported; auth-gate `/health/integrations`; unique constraint check on `tx_ref`; rename/remove the sendgrid shim.

**No fixes have been applied.** Per the brief, implementation starts only after this plan is approved, one batch at a time.
