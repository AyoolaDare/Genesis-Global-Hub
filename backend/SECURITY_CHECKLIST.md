# Genesis Global CMS — Security Checklist

**System:** Genesis Global Church Management System  
**Version:** 1.0.0  
**Date:** 2026-06-23  
**Classification:** Internal Use Only

---

## 1. Authentication

| # | Control | Status | Notes |
|---|---------|--------|-------|
| 1.1 | All login attempts validated against Supabase Auth (not local password DB) | IMPLEMENTED | `auth/service.py → _supabase_sign_in()` |
| 1.2 | Passwords never stored or returned in any API response | IMPLEMENTED | No password fields in schemas; Supabase owns credentials |
| 1.3 | JWT access token expiry: 24 hours | IMPLEMENTED | `config.py → ACCESS_TOKEN_EXPIRE_HOURS=24` |
| 1.4 | JWT refresh token expiry: 30 days | IMPLEMENTED | `config.py → REFRESH_TOKEN_EXPIRE_DAYS=30` |
| 1.5 | JWT tokens signed with HS256 and minimum 32-character secret | IMPLEMENTED | `core/security.py → create_access_token()` |
| 1.6 | Token blacklist enforced on every request via Redis | IMPLEMENTED | `core/security.py → _is_token_blacklisted()` |
| 1.7 | Logout invalidates token immediately (not waiting for expiry) | IMPLEMENTED | `auth/service.py → logout() → blacklist_token()` |
| 1.8 | Token type field ("access"/"refresh") validated to prevent type confusion | IMPLEMENTED | `core/security.py → verify_token()` |
| 1.9 | `jti` (JWT ID) unique per token — enables per-token blacklisting | IMPLEMENTED | `uuid.uuid4()` added to every token payload |
| 1.10 | `is_active` flag checked on every authenticated request | IMPLEMENTED | `auth/dependencies.py → get_current_user()` |

---

## 2. Authorization (RBAC)

| # | Control | Status | Notes |
|---|---------|--------|-------|
| 2.1 | Complete RBAC permission matrix defined for all 10 roles | IMPLEMENTED | `auth/permissions.py → ROLE_PERMISSIONS` |
| 2.2 | HTTP 403 used for permission failures (not 401) | IMPLEMENTED | `core/exceptions.py → PermissionDenied.status_code=403` |
| 2.3 | HTTP 401 used only for missing/invalid/expired tokens | IMPLEMENTED | `core/exceptions.py → AuthenticationFailed.status_code=401` |
| 2.4 | Scope (dept/team/group UUIDs) embedded in JWT at login time | IMPLEMENTED | `core/security.py → build_user_scope()` |
| 2.5 | Scope filter helpers available for all query types | IMPLEMENTED | `auth/dependencies.py → ScopeFilter` |
| 2.6 | SUPER_ADMIN role bypasses all scope checks | IMPLEMENTED | `auth/dependencies.py → require_scope()` |
| 2.7 | Role wildcards handled correctly in permission checks | IMPLEMENTED | `auth/permissions.py → has_permission()` |
| 2.8 | `require_role()` factory usable on any endpoint | IMPLEMENTED | `auth/dependencies.py → require_role()` |
| 2.9 | `require_permission()` factory checks full RBAC matrix | IMPLEMENTED | `auth/dependencies.py → require_permission()` |
| 2.10 | Audit logs only accessible to SUPER_ADMIN | IMPLEMENTED | RLS policy + `PASTOR` read-only in permissions matrix |

---

## 3. Data Exposure Controls

| # | Control | Status | Notes |
|---|---------|--------|-------|
| 3.1 | `medical_patients.member_link_id` never exposed to MEDICAL role | IMPLEMENTED | Schema-level RLS + backend service views |
| 3.2 | `sponsors.member_link_id` never exposed to FINANCE_ADMIN | IMPLEMENTED | Schema-level RLS + `v_members_finance_safe` view |
| 3.3 | `workers.member_link_id` never exposed to HR_ADMIN | IMPLEMENTED | Schema-level RLS + `v_members_hr_safe` view |
| 3.4 | Role-based field stripping on member data | IMPLEMENTED | `auth/permissions.py → strip_member_fields()` |
| 3.5 | MEDICAL role sees no address, marital status, spiritual fields | IMPLEMENTED | `MEMBER_FIELD_RESTRICTIONS["MEDICAL"]` |
| 3.6 | FINANCE_ADMIN sees only full_name + phone on member lookups | IMPLEMENTED | `MEMBER_FIELD_RESTRICTIONS["FINANCE_ADMIN"]` |
| 3.7 | Stack traces NEVER returned in API responses | IMPLEMENTED | All exception handlers suppress traces; internal logging only |
| 3.8 | API documentation disabled in production | IMPLEMENTED | `main.py → docs_url=None` when `ENVIRONMENT != development` |
| 3.9 | Password reset does not reveal email existence | IMPLEMENTED | `auth/service.py → request_password_reset()` always returns 200 |

---

## 4. Rate Limiting & Brute Force Protection

| # | Control | Status | Notes |
|---|---------|--------|-------|
| 4.1 | Auth endpoints limited to 5 attempts / 15 min / IP | IMPLEMENTED | `core/security.py → check_auth_rate_limit()` |
| 4.2 | Failed auth increments counter; success clears it | IMPLEMENTED | `record_failed_auth()` + `clear_auth_rate_limit()` |
| 4.3 | Global rate limit: 200 req / 60s / IP | IMPLEMENTED | `middleware/rate_limit.py → RateLimitMiddleware` |
| 4.4 | Rate limit headers included in all responses | IMPLEMENTED | `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset` |
| 4.5 | Redis failure for rate limiting: fail open (not block all traffic) | IMPLEMENTED | `try/except` in `_check_rate_limit()` with log warning |
| 4.6 | `Retry-After` header included in 429 responses | IMPLEMENTED | `middleware/rate_limit.py → RateLimitMiddleware.dispatch()` |

---

## 5. CORS

| # | Control | Status | Notes |
|---|---------|--------|-------|
| 5.1 | CORS wildcard (`*`) never used | IMPLEMENTED | `middleware/cors.py` reads from `ALLOWED_ORIGINS` env var |
| 5.2 | Empty `ALLOWED_ORIGINS` in production logs CRITICAL alert | IMPLEMENTED | `middleware/cors.py → configure_cors()` |
| 5.3 | `allow_credentials=True` to support auth headers | IMPLEMENTED | `middleware/cors.py` |
| 5.4 | Preflight cache set to 600 seconds | IMPLEMENTED | `max_age=600` |
| 5.5 | Only specific headers allowed (not all) | IMPLEMENTED | `allow_headers` list in `configure_cors()` |

---

## 6. Audit Logging

| # | Control | Status | Notes |
|---|---------|--------|-------|
| 6.1 | All POST/PUT/PATCH/DELETE requests generate audit log | IMPLEMENTED | `middleware/audit.py → AuditMiddleware` |
| 6.2 | Sensitive GET endpoints generate READ audit entries | IMPLEMENTED | `/medical/*`, `/sponsors/*`, `/members/*`, `/hr/*` |
| 6.3 | LOGIN and LOGOUT events explicitly logged | IMPLEMENTED | `auth/service.py → login()` + `logout()` |
| 6.4 | Audit log captures: user_id, action, resource_type, resource_id, IP, user_agent | IMPLEMENTED | `auth/models.py → AuditLog` |
| 6.5 | Audit log writes are non-blocking (background task) | IMPLEMENTED | `asyncio.create_task()` in middleware |
| 6.6 | Audit write failures never break the main request | IMPLEMENTED | `try/except` in `_write_audit_log_async()` |
| 6.7 | Database triggers prevent UPDATE/DELETE on audit_logs | DATABASE LEVEL | `trg_audit_logs_deny_update` + `trg_audit_logs_deny_delete` |
| 6.8 | Only SUPER_ADMIN can query audit logs via API | ENFORCED BY RLS | PostgreSQL RLS + RBAC matrix |

---

## 7. Database Security

| # | Control | Status | Notes |
|---|---------|--------|-------|
| 7.1 | All queries use SQLAlchemy ORM — no raw SQL with user input | IMPLEMENTED | All models use typed columns; parameterised queries only |
| 7.2 | Raw `text()` calls use named bind parameters | IMPLEMENTED | `core/security.py → build_user_scope()` uses `{"uid": ...}` |
| 7.3 | Connection pool with pre-ping to avoid stale connections | IMPLEMENTED | `database.py → pool_pre_ping=True` |
| 7.4 | Database connection timeout configured | IMPLEMENTED | `connect_timeout=10` |
| 7.5 | Soft deletes on all mutable tables (`deleted_at`) | DATABASE LEVEL | Schema design by DatabaseArchitect |
| 7.6 | UUID primary keys on all tables (no sequential IDs) | DATABASE LEVEL | `gen_random_uuid()` in schema |
| 7.7 | PostgreSQL RLS policies enforce row-level isolation | DATABASE LEVEL | 001_initial_schema.sql |
| 7.8 | Service role key used only server-side, never exposed to frontend | IMPLEMENTED | `SUPABASE_SERVICE_KEY` in server env only |

---

## 8. Secret Management

| # | Control | Status | Notes |
|---|---------|--------|-------|
| 8.1 | All secrets loaded from environment variables via pydantic-settings | IMPLEMENTED | `config.py → Settings` |
| 8.2 | `.env` file excluded from version control | REQUIRED | Add `.env` to `.gitignore` |
| 8.3 | `.env.example` committed with no real secrets | IMPLEMENTED | `backend/.env.example` |
| 8.4 | `JWT_SECRET_KEY` minimum length enforced (32 chars) | IMPLEMENTED | `config.py → validate_jwt_secret()` |
| 8.5 | `SUPABASE_SERVICE_KEY` vs `SUPABASE_ANON_KEY` separation | IMPLEMENTED | Service key for server; anon key for Supabase Auth REST calls |
| 8.6 | Secrets not logged at any level | IMPLEMENTED | No logger calls reference secret vars |

---

## 9. Transport Security

| # | Control | Status | Notes |
|---|---------|--------|-------|
| 9.1 | HTTPS enforced in production (via Render/reverse proxy) | INFRASTRUCTURE | Enforce at Render / Cloudflare level |
| 9.2 | Redis connection uses TLS (`rediss://`) | IMPLEMENTED | `UPSTASH_REDIS_URL` starts with `rediss://` |
| 9.3 | Supabase connections use HTTPS | IMPLEMENTED | Supabase SDK enforces HTTPS |
| 9.4 | HTTP Strict Transport Security (HSTS) header | REQUIRED | Add via Render custom headers or Cloudflare |
| 9.5 | X-Frame-Options: DENY header | REQUIRED | Add via Render custom headers or Cloudflare |
| 9.6 | X-Content-Type-Options: nosniff header | REQUIRED | Add via Render custom headers or Cloudflare |

---

## 10. Flutter Client Security Requirements

| # | Control | Status | Notes |
|---|---------|--------|-------|
| 10.1 | Tokens stored in `flutter_secure_storage` (NOT SharedPreferences) | REQUIRED | Flutter team must enforce this |
| 10.2 | Refresh token sent only to `/api/v1/auth/refresh` — never elsewhere | REQUIRED | Flutter team must enforce this |
| 10.3 | Token cleared from storage on logout | REQUIRED | Flutter team must enforce this |
| 10.4 | Certificate pinning for production builds | RECOMMENDED | Flutter team: use `http_certificate_pinning` package |
| 10.5 | Screenshot prevention on sensitive screens (medical, finance) | RECOMMENDED | `FlutterWindowManager.addFlags(FLAG_SECURE)` on Android |

---

## 11. Operational Security

| # | Control | Status | Notes |
|---|---------|--------|-------|
| 11.1 | Database backup configured (Supabase Point-in-Time Recovery) | REQUIRED | Enable in Supabase Dashboard |
| 11.2 | Redis persistence configured (Upstash) | REQUIRED | Verify in Upstash Console |
| 11.3 | Alerting on repeated 401/403 errors | RECOMMENDED | Configure in Render / Sentry |
| 11.4 | Alerting on unusual audit log volume | RECOMMENDED | Supabase Realtime or cron query |
| 11.5 | Regular secret rotation schedule (JWT key, API keys) | REQUIRED | Rotate every 90 days minimum |
| 11.6 | Dependency vulnerability scanning | RECOMMENDED | `pip-audit` in CI/CD pipeline |
| 11.7 | SUPER_ADMIN accounts limited to 2–3 named individuals | POLICY | Org policy enforcement |
| 11.8 | SUPER_ADMIN MFA enforced via Supabase Auth | REQUIRED | Enable in Supabase Auth settings |

---

## Pre-Deployment Checklist

Before going live, verify all of the following:

- [ ] `ENVIRONMENT=production` in deployment env vars
- [ ] `ALLOWED_ORIGINS` set to actual production domain(s)
- [ ] `JWT_SECRET_KEY` is 64+ character random hex (not the example value)
- [ ] `.env` is NOT committed to version control
- [ ] `SUPABASE_SERVICE_KEY` is server-only (not in any frontend config)
- [ ] Redis TLS URL (`rediss://`) is configured
- [ ] Database connection pool size matches Supabase connection limits
- [ ] HTTPS is enforced at the load balancer / CDN level
- [ ] API docs (`/docs`, `/redoc`) return 404 in production
- [ ] SUPER_ADMIN MFA is enabled in Supabase Auth settings
- [ ] All PostgreSQL RLS policies are active (`ALTER TABLE ... ENABLE ROW LEVEL SECURITY`)
- [ ] Audit log triggers are in place (`trg_audit_logs_deny_update`, `trg_audit_logs_deny_delete`)
- [ ] At least one SUPER_ADMIN user exists in `app_users` table
- [ ] Dependency audit run: `pip-audit -r requirements.txt`
- [ ] Render health check configured to monitor `/health`

---

*This checklist should be reviewed on every major release and quarterly for operational controls.*
