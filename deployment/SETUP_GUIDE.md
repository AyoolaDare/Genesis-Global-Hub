# Genesis Global CMS — Complete Deployment Guide

Organization: Genesis Global (Celestial Church of Christ)
Stack: Flutter Web + FastAPI + Supabase PostgreSQL + Upstash Redis
Hosting: Vercel (Frontend) + Render (Backend) — Free Tier

---

## Table of Contents

1. [Prerequisites](#section-1-prerequisites)
2. [Supabase Setup](#section-2-supabase-setup)
3. [Upstash Redis Setup](#section-3-upstash-redis-setup)
4. [Flutterwave Setup](#section-4-flutterwave-setup)
5. [Termii Setup](#section-5-termii-setup)
6. [SendGrid Setup](#section-6-sendgrid-setup)
7. [Backend Deployment (Render)](#section-7-backend-deployment-render)
8. [Frontend Deployment (Vercel)](#section-8-frontend-deployment-vercel)
9. [Update CORS](#section-9-update-cors)
10. [Create First Admin User](#section-10-create-first-admin-user)
11. [Verify Deployment](#section-11-verify-deployment)
12. [Free Tier Limits and Mitigation](#section-12-free-tier-limits-and-mitigation)
13. [Monitoring and Maintenance](#section-13-monitoring-and-maintenance)

---

## Section 1: Prerequisites

### Tools to Install Locally

| Tool | Minimum Version | Install |
|------|----------------|---------|
| Flutter SDK | 3.19.0 | https://docs.flutter.dev/get-started/install |
| Python | 3.11 | https://www.python.org/downloads/ |
| Git | 2.40+ | https://git-scm.com/downloads |
| Docker Desktop | 4.x | https://www.docker.com/products/docker-desktop (optional, for local dev) |

Verify your installs:

```bash
flutter --version
python --version
git --version
docker --version        # optional
docker compose version  # optional
```

### Accounts to Create

Create free accounts at each of the following services before starting:

| Service | URL | Purpose | Free Tier |
|---------|-----|---------|-----------|
| GitHub | https://github.com | Code hosting, CI/CD | Unlimited public/private repos |
| Supabase | https://supabase.com | PostgreSQL database + Auth | 500MB DB, 50K MAU |
| Render | https://render.com | Backend API hosting | 750 hrs/month |
| Vercel | https://vercel.com | Frontend hosting | 100GB bandwidth/month |
| Upstash | https://upstash.com | Redis (rate limiting, token blacklist) | 10K requests/day |
| Flutterwave | https://flutterwave.com | Payment processing | Pay-per-transaction only |
| Termii | https://termii.com | SMS gateway | Pay-as-you-go |
| SendGrid | https://sendgrid.com | Transactional email | 100 emails/day free |

### Push Code to GitHub

If not already done:

```bash
cd Church-App
git init
git add .
git commit -m "Initial commit: Genesis Global CMS"
git branch -M main
git remote add origin https://github.com/YOUR-USERNAME/genesis-global-cms.git
git push -u origin main
```

---

## Section 2: Supabase Setup

### 2.1 Create a New Project

1. Go to https://supabase.com/dashboard
2. Click "New Project"
3. Organization: select or create your org
4. Project name: `genesis-global-cms`
5. Database Password: generate a strong password and SAVE IT — you will need it for DATABASE_URL
6. Region: choose nearest to Nigeria (closest available: Europe West / us-east-1)
7. Click "Create new project"
8. Wait ~2 minutes for provisioning

### 2.2 Run the Database Migration

1. In Supabase Dashboard, go to: **SQL Editor** (left sidebar)
2. Click "New query"
3. Open the file `database/migrations/001_initial_schema.sql` from this repository
4. Copy the entire file contents
5. Paste into the SQL Editor
6. Click "Run" (or press Ctrl+Enter)
7. Verify success: you should see no errors in the results panel
8. Navigate to **Table Editor** and confirm the tables are created (members, app_users, etc.)

### 2.3 Copy API Credentials

Navigate to: **Project Settings → API**

Copy these three values — you will use them as environment variables:

```
Project URL:          SUPABASE_URL     = https://[your-ref].supabase.co
anon public key:      SUPABASE_ANON_KEY = eyJ...
service_role key:     SUPABASE_SERVICE_KEY = eyJ...   (keep this secret)
```

Navigate to: **Project Settings → Database → Connection string → URI**

Copy the **Transaction** connection string (port 6543, uses PgBouncer):

```
DATABASE_URL = postgresql+psycopg2://postgres:[YOUR-PASSWORD]@db.[YOUR-REF].supabase.co:6543/postgres?sslmode=require&pgbouncer=true
```

Replace `[YOUR-PASSWORD]` with the database password you set in step 2.1.

### 2.4 Enable Email Auth

1. Go to **Authentication → Providers**
2. Ensure "Email" is enabled (it is by default)
3. Configure settings:
   - Enable "Confirm email": set to your preference (recommended: ON for production)
   - Site URL: will update after Vercel deployment

### 2.5 Configure Auth Email Templates (Optional but Recommended)

1. Go to **Authentication → Email Templates**
2. Update "Confirm signup" template to include Genesis Global branding
3. Update "Reset password" template with your support email
4. Update "Magic Link" template if you plan to use it

### 2.6 Set Up Storage Bucket for Member Photos

1. Go to **Storage** (left sidebar)
2. Click "New bucket"
3. Bucket name: `member-photos`
4. Public bucket: OFF (leave unchecked — photos are private)
5. Click "Save"
6. Go to **Storage → Policies**
7. Add a policy for `member-photos`:
   - Allowed operations: SELECT, INSERT, UPDATE, DELETE
   - Policy: authenticated users can read/write their own files
   - Example policy (run in SQL Editor):

```sql
-- Allow authenticated users to upload member photos
CREATE POLICY "Auth users can upload member photos"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'member-photos');

-- Allow authenticated users to view member photos
CREATE POLICY "Auth users can view member photos"
ON storage.objects FOR SELECT
TO authenticated
USING (bucket_id = 'member-photos');

-- Allow users to update/delete their own uploads
CREATE POLICY "Users can manage their uploads"
ON storage.objects FOR UPDATE, DELETE
TO authenticated
USING (bucket_id = 'member-photos' AND auth.uid()::text = (storage.foldername(name))[1]);
```

---

## Section 3: Upstash Redis Setup

### 3.1 Create Account and Database

1. Go to https://console.upstash.com
2. Sign up or log in
3. Click "Create Database"
4. Name: `genesis-global-redis`
5. Type: Regional
6. Region: US-East-1 (lowest latency from Nigeria due to routing) or EU-West-1
7. TLS: ON (required — never use unencrypted Redis in production)
8. Click "Create"

### 3.2 Copy the Redis URL

1. Click on your new database
2. Go to "Details" tab
3. Find "Redis URL" — it must start with `rediss://` (double-s = TLS)
4. Copy the full URL including password

```
UPSTASH_REDIS_URL = rediss://:[YOUR-PASSWORD]@[YOUR-ENDPOINT].upstash.io:6379
```

### 3.3 Verify the Free Tier Limits

On the free tier, Upstash provides:
- 10,000 commands/day
- 256MB max data size
- 100 concurrent connections

For Genesis Global at <500 members, daily Redis usage will be roughly:
- ~5 commands per login (rate limit check + token blacklist)
- ~2 commands per API request (rate limit)
- Estimated: ~1,000-3,000 commands/day — safely within limits

---

## Section 4: Flutterwave Setup

### 4.1 Create Account

1. Go to https://flutterwave.com/ng
2. Sign up as a business account
3. Complete KYC (business registration documents required for live keys)
4. Use TEST mode for development

### 4.2 Get API Keys

1. Log into Flutterwave Dashboard
2. Go to **Settings → API Keys**
3. For development, copy "Test Secret Key" and "Test Encryption Key"
4. For production, complete KYC and copy "Live Secret Key" and "Live Encryption Key"

```
FLUTTERWAVE_SECRET_KEY     = FLWSECK_TEST-xxxxx   (or FLWSECK-xxxxx for live)
FLUTTERWAVE_ENCRYPTION_KEY = your-encryption-key
```

### 4.3 Configure Webhook

1. In Flutterwave Dashboard, go to **Settings → Webhooks**
2. Set webhook URL:
   ```
   https://genesis-global-api.onrender.com/api/v1/webhooks/flutterwave
   ```
   (Replace with your actual Render URL after backend deployment)
3. Set "Secret Hash" (verif-hash) to the same value as your FLUTTERWAVE_SECRET_KEY
4. Enable events: `charge.completed`, `transfer.completed`

### 4.4 Enable Payment Methods

1. Go to **Settings → Payment Methods**
2. Enable:
   - Card (Visa/Mastercard)
   - Bank Transfer
   - USSD
   - Mobile Money (if needed for West Africa members)

---

## Section 5: Termii Setup

### 5.1 Create Account

1. Go to https://termii.com
2. Sign up (requires business email)
3. Verify your email address

### 5.2 Get API Key

1. Log into Termii Dashboard
2. Go to **Settings → API Key**
3. Copy your API key

```
TERMII_API_KEY = TLbb_xxxxx
```

### 5.3 Register Sender ID

1. Go to **Settings → Sender IDs**
2. Click "Add Sender ID"
3. Sender ID: `GenesisGlb` (Termii limit is 11 characters — "GenesisGlobal" exceeds limit)
   - Note: Update `TERMII_SENDER_ID` in your .env to match the approved value exactly
4. Purpose: transactional
5. Upload business registration documents
6. Submit for approval (takes 24-48 business hours)

**While waiting for sender ID approval:** Termii provides a default sender ID for testing. Your messages will still go through with the generic sender.

### 5.4 Fund Your Account

1. Go to **Wallet → Fund Wallet**
2. Minimum deposit: NGN 1,000
3. SMS cost: approximately NGN 2-4 per message
4. For 500 members, budget NGN 5,000-10,000 initial load

---

## Section 6: SendGrid Setup

### 6.1 Create Account

1. Go to https://signup.sendgrid.com
2. Complete registration (requires phone number verification)

### 6.2 Verify Sender Domain

For best deliverability, verify your domain rather than a single email address:

1. Go to **Settings → Sender Authentication**
2. Click "Authenticate Your Domain"
3. Enter your domain (e.g., `genesisglob.al`)
4. Follow DNS record instructions (add CNAME and TXT records to your DNS provider)
5. Click "Verify"

Alternatively, for quick setup:
1. Go to **Settings → Sender Authentication → Single Sender Verification**
2. Add your from address (e.g., `noreply@genesisglob.al`)
3. Verify via the confirmation email sent to that address

### 6.3 Create API Key

1. Go to **Settings → API Keys**
2. Click "Create API Key"
3. Name: `genesis-global-cms-production`
4. API Key Permissions: **Restricted Access**
5. Enable: Mail Send → Full Access
6. Click "Create & View"
7. COPY THE KEY NOW — it is only shown once

```
SENDGRID_API_KEY = SG.xxxxx
FROM_EMAIL       = noreply@genesisglob.al
```

---

## Section 7: Backend Deployment (Render)

### 7.1 Push Code to GitHub

Ensure all code including `deployment/render.yaml` is pushed to your GitHub repository:

```bash
git add deployment/render.yaml backend/Dockerfile
git commit -m "Add Render deployment configuration"
git push origin main
```

### 7.2 Create Render Account and Deploy

1. Go to https://render.com and sign up
2. Click "New" → "Blueprint"
3. Connect your GitHub account if not already connected
4. Search for and select your `genesis-global-cms` repository
5. Render will detect `deployment/render.yaml` automatically
6. Click "Apply"
7. Name your environment group: `genesis-global-secrets` (matches render.yaml)

### 7.3 Set Environment Variables

After the blueprint is applied, go to each service and set the secret environment variables.

For the `genesis-global-api` service:

1. Go to **Dashboard → genesis-global-api → Environment**
2. Add each variable that has `sync: false` in render.yaml:

| Variable | Value | Where to get it |
|----------|-------|----------------|
| `DATABASE_URL` | `postgresql+psycopg2://postgres:...@db.[ref].supabase.co:6543/postgres?sslmode=require&pgbouncer=true` | Supabase → Project Settings → Database → Connection String |
| `SUPABASE_URL` | `https://[ref].supabase.co` | Supabase → Project Settings → API |
| `SUPABASE_SERVICE_KEY` | `eyJ...` | Supabase → Project Settings → API → service_role key |
| `SUPABASE_ANON_KEY` | `eyJ...` | Supabase → Project Settings → API → anon public key |
| `UPSTASH_REDIS_URL` | `rediss://:[pw]@[host].upstash.io:6379` | Upstash Console → Database → Details |
| `FLUTTERWAVE_SECRET_KEY` | `FLWSECK-...` | Flutterwave → Settings → API Keys |
| `FLUTTERWAVE_ENCRYPTION_KEY` | `...` | Flutterwave → Settings → API Keys |
| `TERMII_API_KEY` | `TLbb_...` | Termii → Settings → API Key |
| `SENDGRID_API_KEY` | `SG....` | SendGrid → Settings → API Keys |
| `FROM_EMAIL` | `noreply@genesisglob.al` | Your verified sender |
| `ALLOWED_ORIGINS` | *(add Vercel URL after frontend deploy)* | Update in Step 9 |

3. Click "Save Changes" — Render will redeploy automatically

### 7.4 Create the Environment Group for Workers

1. Go to **Dashboard → Environment → Environment Groups**
2. Click "New Environment Group"
3. Name: `genesis-global-secrets`
4. Add all the same environment variables as the API service above
5. Save

Render will link the worker and beat services to this group automatically per render.yaml.

### 7.5 Note Your Render URL

After first successful deploy, your API will be available at:

```
https://genesis-global-api.onrender.com
```

Verify: open `https://genesis-global-api.onrender.com/health` in your browser.

Expected response:
```json
{
  "status": "ok",
  "version": "1.0.0",
  "environment": "production",
  "database": "ok"
}
```

---

## Section 8: Frontend Deployment (Vercel)

### 8.1 Install Vercel CLI (optional but useful)

```bash
npm install -g vercel
```

### 8.2 Deploy via Vercel Dashboard

1. Go to https://vercel.com/new
2. Click "Import Git Repository"
3. Select your `genesis-global-cms` GitHub repository
4. Configuration:
   - **Framework Preset**: Other
   - **Root Directory**: leave blank (Vercel reads vercel.json from repo root)
   - **Build Command**: `cd frontend && flutter pub get && flutter build web --release --web-renderer canvaskit`
   - **Output Directory**: `frontend/build/web`
   - **Install Command**: leave blank (not needed for Flutter)

### 8.3 Add Flutter to Vercel Build Environment

Vercel does not have Flutter pre-installed. You need to install it during build.

Update `deployment/vercel.json` build command to install Flutter first:

The current vercel.json is configured for Vercel environments that support Flutter. If your build fails because Flutter is not found, use a Vercel Build Plugin or replace the build command with:

```bash
curl -fsSL https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.19.0-stable.tar.xz | tar -xJ -C $HOME && export PATH="$PATH:$HOME/flutter/bin" && cd frontend && flutter pub get && flutter build web --release --web-renderer canvaskit
```

Add this as the Build Command in Vercel project settings (override the vercel.json value).

### 8.4 Add Environment Variable

In Vercel project settings → **Environment Variables**:

| Variable | Value |
|----------|-------|
| `API_BASE_URL` | `https://genesis-global-api.onrender.com` |

### 8.5 Deploy

1. Click "Deploy"
2. Wait for build to complete (~5-10 minutes for first build — Flutter downloads take time)
3. Vercel will give you a URL like: `https://genesis-global-cms.vercel.app`

### 8.6 Note Your Vercel URL

```
Frontend URL: https://genesis-global-cms.vercel.app
```

---

## Section 9: Update CORS

The backend must explicitly allow requests from the Vercel frontend domain.

1. Go to **Render Dashboard → genesis-global-api → Environment**
2. Update `ALLOWED_ORIGINS`:
   ```
   https://genesis-global-cms.vercel.app
   ```
   If you have a custom domain on Vercel, add both:
   ```
   https://genesis-global-cms.vercel.app,https://cms.genesisglob.al
   ```
3. Click "Save Changes"
4. Render will automatically redeploy with the new CORS config

Also update the environment group `genesis-global-secrets` with the same ALLOWED_ORIGINS value so the worker services have consistent config.

---

## Section 10: Create First Admin User

The first super admin cannot self-register — you must create them manually.

### Step 1: Create Auth User in Supabase

1. Go to **Supabase Dashboard → Authentication → Users**
2. Click "Invite user" or "Add user"
3. Enter email: `admin@genesisglob.al` (or your admin email)
4. Set a temporary password
5. After creation, copy the UUID from the user row (format: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`)

### Step 2: Link to app_users Table

Run this in **Supabase → SQL Editor**:

```sql
-- Replace the UUID and email with the actual values from Step 1
INSERT INTO app_users (id, email, role, is_active, created_at, updated_at)
VALUES (
    'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',  -- UUID from Supabase Auth user
    'admin@genesisglob.al',                   -- Must match auth.users.email exactly
    'SUPER_ADMIN',
    true,
    NOW(),
    NOW()
);
```

### Step 3: Verify Login

1. Open the Flutter web app in your browser
2. Enter the admin email and password
3. You should be redirected to the super admin dashboard
4. Change the password immediately after first login

---

## Section 11: Verify Deployment

Work through this checklist after completing all sections:

### API Health Checks

```bash
# 1. Basic health check
curl https://genesis-global-api.onrender.com/health
# Expected: {"status":"ok","version":"1.0.0","environment":"production","database":"ok"}

# 2. Authentication endpoint exists (should return 422, not 404)
curl -X POST https://genesis-global-api.onrender.com/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{}'
# Expected: 422 Unprocessable Entity (validation error — correct behavior)

# 3. Login with admin credentials
curl -X POST https://genesis-global-api.onrender.com/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@genesisglob.al","password":"YOUR_PASSWORD"}'
# Expected: 200 OK with JWT access_token
```

### Frontend Checks

- [ ] Flutter web app loads at Vercel URL (no blank page or console errors)
- [ ] Login page renders correctly
- [ ] Login with admin credentials succeeds and redirects to dashboard
- [ ] No CORS errors in browser console (F12 → Console)
- [ ] Network requests to Render API succeed (F12 → Network tab)

### Database Checks

- [ ] All tables exist in Supabase (Table Editor shows: members, app_users, attendance, etc.)
- [ ] Migration ran without errors
- [ ] app_users table has your admin user row

### Integration Checks

- [ ] Upstash Redis: check Upstash Console → Database → Data Browser (no errors)
- [ ] Rate limiting works: try 6 failed logins in a row, 6th should be blocked

---

## Section 12: Free Tier Limits and Mitigation

| Service | Free Tier Limit | Current Usage Estimate | Mitigation Strategy |
|---------|----------------|----------------------|---------------------|
| Render (API) | 750 hrs/month, sleeps after 15 min idle | ~300-400 hrs/month (with UptimeRobot keepalive) | Set UptimeRobot to ping /health every 14 min |
| Render (Worker) | 750 hrs/month shared | ~300 hrs/month | Monitor usage in Render Dashboard → Metrics |
| Render (Beat) | 750 hrs/month shared | ~300 hrs/month | Consider combining worker + beat if approaching limit |
| Supabase DB | 500MB storage | <50MB for <500 members | Compress member photos; use Storage for files not DB |
| Supabase Storage | 1GB | Scales with member photos | Limit photo upload size to 2MB max in app |
| Supabase MAU | 50,000 monthly active users | <500 for church CMS | No concern at this scale |
| Vercel Bandwidth | 100GB/month | <1GB/month (Flutter static files cached) | Flutter CanvasKit = larger initial download; mitigate with CDN caching |
| Vercel Builds | 100 builds/month | ~20-30 builds/month with CI | No concern |
| Upstash Redis | 10,000 commands/day | ~1,000-3,000/day | Stays within limits; upgrade if rate limiting becomes aggressive |
| Flutterwave | No monthly fee, 1.4% + NGN 100 per transaction | Depends on donations volume | Budget transaction fees into financial planning |
| Termii | No monthly fee, ~NGN 2-4/SMS | Depends on notification volume | Use email as primary notification; SMS for critical alerts only |
| SendGrid | 100 emails/day free | <100/day for <500 members | Sufficient; upgrade to Essentials ($19.95/month) if exceeded |

### When Will the App Need Paid Plans?

| Trigger | Service | Upgrade Cost |
|---------|---------|-------------|
| >750 CPU hrs/month (all Render services combined) | Render | $7/month/service (Starter plan) |
| >500MB database | Supabase | $25/month (Pro plan) |
| >50,000 MAU | Supabase | Included in Pro plan above |
| >10,000 Redis commands/day | Upstash | Pay-as-you-go, ~$0.20/100K requests |
| >100 emails/day sustained | SendGrid | $19.95/month for 40K emails/month |

**Estimated time to hit limits at Genesis Global scale (500 members, 50 active users):**
- Render hours: ~12-18 months (with UptimeRobot, hours deplete faster)
- Supabase DB: 24+ months
- Upstash Redis: 12+ months
- SendGrid emails: 6-12 months if sending daily newsletters

**Estimated monthly cost when upgrading:**
- Render 3 services (API + Worker + Beat): $21/month
- Supabase Pro: $25/month
- Upstash Pay-as-you-go: ~$2-5/month
- SendGrid Essentials: $19.95/month
- **Total projected: ~$68-72/month**

---

## Section 13: Monitoring and Maintenance

### 13.1 Prevent Render Free Tier Sleep with UptimeRobot

Render free tier web services sleep after 15 minutes of inactivity. The first request after sleep takes ~20-30 seconds (cold start). Prevent this with UptimeRobot:

1. Go to https://uptimerobot.com and create a free account
2. Click "Add New Monitor"
3. Monitor Type: HTTP(s)
4. Friendly Name: `Genesis Global API`
5. URL: `https://genesis-global-api.onrender.com/health`
6. Monitoring Interval: **5 minutes** (free tier allows 5-min intervals)
7. Click "Create Monitor"

This ping keeps the service alive 24/7 and uses ~8,640 requests/month against Render's 750-hour allocation (equivalent to always-on usage — budget accordingly).

**Note:** 750 hours / 31 days = 24.2 hours/day = effectively always-on. UptimeRobot will keep the service running continuously, which means you use all 750 hours in a standard month. This is fine — just don't run more than one web service on free tier simultaneously.

### 13.2 Supabase Backups

Supabase free tier includes 7-day Point-in-Time Recovery (PITR):

1. Go to **Supabase Dashboard → Settings → Backups**
2. Download a manual backup weekly (recommended: every Sunday)
3. Store backups in Google Drive or a secure cloud location

To create an on-demand backup:

```bash
# Using pg_dump locally (requires PostgreSQL client tools)
pg_dump "postgresql://postgres:[PASSWORD]@db.[REF].supabase.co:5432/postgres?sslmode=require" \
  --format=custom \
  --no-acl \
  --no-owner \
  --file="genesis_backup_$(date +%Y%m%d).dump"
```

### 13.3 Log Monitoring

**Render logs (real-time):**
1. Go to **Render Dashboard → genesis-global-api → Logs**
2. Filter for `ERROR` or `CRITICAL` to find issues
3. Use "Download logs" for historical analysis

**Set up email alerts in Render:**
1. Go to **Render Dashboard → Notifications**
2. Add notification: Email on "Service fails to deploy" and "Service crashes"

**Log levels used in the API:**
- `CRITICAL`: database connection failed, unhandled exceptions
- `ERROR`: domain exceptions with 5xx status codes
- `WARNING`: authentication failures, rate limit hits
- `INFO`: startup, shutdown, request processing
- `DEBUG`: detailed tracing (development only)

### 13.4 Periodic Maintenance Tasks

| Task | Frequency | How |
|------|-----------|-----|
| Download Supabase backup | Weekly | Supabase Dashboard → Settings → Backups |
| Review Render logs for errors | Weekly | Render Dashboard → Logs |
| Check Upstash Redis memory usage | Monthly | Upstash Console → Database → Metrics |
| Rotate JWT_SECRET_KEY | Every 6 months | Update in Render env vars; all users re-login |
| Review failed login attempts | Monthly | Render Logs → filter "rate limit" |
| Check Flutterwave webhook delivery | Monthly | Flutterwave Dashboard → Webhooks → Logs |
| Update Python dependencies | Quarterly | `pip list --outdated`, update requirements.txt |
| Update Flutter SDK | Quarterly | `flutter upgrade` |

### 13.5 Emergency Contacts and Recovery

**If the API is down:**
1. Check Render Status: https://status.render.com
2. Check Supabase Status: https://status.supabase.com
3. Check your Render logs for the error message
4. If environment variable missing: add it in Render Dashboard → Redeploy

**If the database is unreachable:**
1. Check Supabase project is not paused (free tier projects pause after 7 days inactivity)
2. To unpause: go to Supabase Dashboard → click "Resume project"
3. To prevent: visit the Supabase dashboard at least once per week

**If you need to roll back the API:**
1. Go to **Render Dashboard → genesis-global-api → Deploys**
2. Click "..." on a previous successful deploy
3. Click "Rollback to this deploy"

**If you need to restore the database:**
1. Go to **Supabase Dashboard → Settings → Backups**
2. Select a recovery point
3. Click "Restore to this point"
4. Note: restoration creates a new project — update DATABASE_URL and SUPABASE_URL in Render
