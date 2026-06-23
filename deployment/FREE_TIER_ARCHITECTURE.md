# Genesis Global CMS — Free Tier Architecture Reference

This document explains the infrastructure decisions, service limits, and operational strategies
for running the Genesis Global Church Management System at zero monthly cost.

---

## 1. Service Selection Rationale

### Why Vercel for Flutter Web?

Flutter Web produces a static output (HTML + JavaScript + WASM). It does not require a Node.js
server or any server-side rendering. This makes it a perfect fit for Vercel's static hosting model.

Specific advantages for this project:
- **Zero build configuration:** vercel.json handles the entire Flutter build pipeline
- **Global CDN:** Vercel distributes assets across edge nodes; Nigerian users get served from
  the nearest PoP (typically London or Johannesburg)
- **Automatic HTTPS:** TLS certificates provisioned and renewed automatically
- **Preview deployments:** every branch push gets a unique preview URL (useful for testing
  feature branches before merging to main)
- **Free tier fit:** Flutter Web bundles are ~5-15MB for CanvasKit renderer. The 100GB/month
  bandwidth limit supports ~7,000-20,000 page loads per month — far more than a 500-member church

Alternatives considered:
- GitHub Pages: no CDN, no custom headers, no redirect rules (Flutter SPA routing breaks)
- Netlify: comparable to Vercel, but Vercel has better Flutter community support and documentation
- Firebase Hosting: ties you deeper into Google ecosystem, overkill for this use case

### Why Render for FastAPI?

Render provides managed Python hosting with automatic TLS, zero-config PostgreSQL (though we
use Supabase for the DB), and GitHub-connected deployments.

Specific advantages:
- **render.yaml Blueprint:** infrastructure-as-code deployment — the entire service configuration
  lives in the repository
- **Native Python buildpack:** no Docker required; Render detects Python and installs
  requirements.txt automatically
- **Free web services:** 750 hours/month is sufficient for a single always-on service with
  UptimeRobot keepalive
- **Environment groups:** secrets are managed in the dashboard, not in code
- **Region:** Oregon (us-west-2) chosen for best connectivity to Supabase us-east-1 region

Alternatives considered:
- Railway: similar feature set, but free tier is more restrictive (500 hours execution time)
- Fly.io: excellent performance, but free tier requires credit card and has complex networking
- Heroku: eliminated when free tier was discontinued in 2022
- AWS Lambda / Cloud Run: serverless cold starts incompatible with SQLAlchemy connection pools

### Why Supabase for PostgreSQL?

Supabase provides managed PostgreSQL with additional features that directly benefit this project:

- **Built-in Auth:** Supabase Auth handles password hashing, JWT issuance, email verification,
  and password reset flows — reducing custom code the team must maintain
- **Row Level Security (RLS):** database-level access control policies complement API-level
  role checks for defense in depth
- **PgBouncer built-in:** connection pooling is automatic (port 6543 = transaction pooling)
  without any additional infrastructure
- **Storage:** S3-compatible object storage for member photos, integrated with auth policies
- **SQL Editor:** non-technical administrators can run ad-hoc queries if needed
- **Free tier:** 500MB database, 1GB storage, 50,000 MAU — comfortably serves a 500-member church

Alternatives considered:
- PlanetScale: MySQL only (project uses PostgreSQL-specific features)
- Neon: PostgreSQL, but less mature auth/storage integration
- Self-hosted PostgreSQL on Render: additional operational burden, no managed backups

### Why Upstash for Redis?

The API uses Redis for two purposes:
1. **Token blacklisting:** when a user logs out, their JWT is added to Redis with a TTL equal
   to the token's remaining lifetime. This makes logout instant without waiting for token expiry.
2. **Rate limiting:** failed login attempts are tracked per-IP with a sliding window counter.

Upstash is chosen because:
- **Serverless pricing:** $0 for under 10,000 commands/day — compatible with free-tier philosophy
- **TLS by default:** `rediss://` (double-s) connections are enforced — no insecure Redis
- **Persistence:** unlike in-memory Redis, Upstash persists data across restarts
- **No server management:** fully managed with automatic failover

Alternatives considered:
- Redis Cloud (free tier): 30MB limit, single region
- Self-hosted Redis on Render: counted against CPU hours, no TLS without stunnel

---

## 2. Current Limits and Upgrade Triggers

### Render

| Metric | Free Tier | Upgrade Trigger | Upgrade Plan |
|--------|-----------|----------------|-------------|
| CPU hours/month (per service) | 750 hrs | >700 hrs/month | Starter: $7/month |
| RAM | 512MB | OOM errors in logs | Starter: 512MB guaranteed |
| Disk | 1GB ephemeral | Large log files | Starter: persistent disk optional |
| Services | Unlimited | N/A | N/A |
| Bandwidth | 100GB/month | N/A | N/A |
| Sleep after inactivity | 15 minutes | Mitigated by UptimeRobot | Starter: no sleep |

**Current usage projection (500 members, 50 active users):**
- API: always-on via UptimeRobot = ~744 hrs/month (just under limit)
- Worker: background tasks run infrequently = ~200-300 hrs/month
- Beat: scheduler runs constantly = ~200 hrs/month
- Total: ~1,144-1,344 hrs/month across three services

**Recommendation:** Monitor via Render Dashboard → Metrics → CPU Hours. When API service
approaches 700 hrs/month, upgrade API to Starter ($7/month). Keep worker and beat on free tier
until those also approach limits.

### Supabase

| Metric | Free Tier | Upgrade Trigger | Upgrade Plan |
|--------|-----------|----------------|-------------|
| Database size | 500MB | >400MB (leave 20% headroom) | Pro: $25/month |
| File storage | 1GB | >800MB | Pro: $25/month (includes 8GB storage) |
| Monthly active users | 50,000 | >45,000 | Pro: $25/month |
| Edge functions | 500K invocations | N/A (not used) | N/A |
| Project auto-pause | After 7 days inactive | Login weekly | Pro: no pause |

**Database size estimate for 500 members:**
- app_users table: ~500 rows × 500 bytes = 250KB
- members table: ~500 rows × 2KB = 1MB
- attendance table: ~500 members × 52 weeks × 50 bytes = 1.3MB/year
- notifications table: ~5,000 rows/month × 200 bytes = 12MB/year
- sponsor_payments: ~100/month × 300 bytes = 360KB/year
- Total estimated: ~15-20MB/year

**Conclusion:** 500MB limit supports this church for 20+ years at current scale.

### Vercel

| Metric | Free Tier | Upgrade Trigger | Upgrade Plan |
|--------|-----------|----------------|-------------|
| Bandwidth | 100GB/month | >80GB/month | Pro: $20/month |
| Build minutes | 6,000 min/month | >5,000 min/month | Pro: $20/month |
| Deployments | 100/day | N/A | N/A |
| Functions | 100GB-hours | N/A (not used) | N/A |

**Bandwidth estimate:**
- Flutter CanvasKit initial bundle: ~8-12MB (downloaded once, cached by browser)
- Subsequent visits: ~100-500KB (service worker serves from cache)
- 500 members, 4 visits/month = 2,000 visits × 10MB average = 20GB/month (worst case)
- With browser caching: ~2-3GB/month realistically

**Conclusion:** 100GB limit is far more than needed for this use case.

### Upstash Redis

| Metric | Free Tier | Upgrade Trigger | Upgrade Plan |
|--------|-----------|----------------|-------------|
| Commands/day | 10,000 | >9,000/day | Pay-as-you-go: $0.20/100K |
| Max data size | 256MB | >200MB | Pay-as-you-go: $0.25/GB |
| Concurrent connections | 100 | >80 | Pay-as-you-go: no change |

**Command usage estimate:**
- Login: 3 commands (rate limit check, token blacklist write, session tracking) = 150 commands/day (50 users × 3 logins)
- API requests: 1 command (rate limit check) = 500-2,000 commands/day
- Total estimate: ~650-2,150 commands/day

**Conclusion:** 10,000/day limit is 4-15x current estimated usage. Comfortable on free tier.

---

## 3. Render Cold Start Mitigation

### The Problem

Render free tier web services spin down after 15 minutes of inactivity. When the next request
arrives, the service must:
1. Start the Python process
2. Load FastAPI and all dependencies
3. Establish the SQLAlchemy database connection pool
4. Accept the request

This cold start takes approximately 20-40 seconds. For a church management system where users
expect immediate login response, this is unacceptable.

### Solution 1: UptimeRobot Keepalive (Recommended)

Configure UptimeRobot to ping the `/health` endpoint every 5 minutes:

1. Monitor type: HTTP(s)
2. URL: `https://genesis-global-api.onrender.com/health`
3. Interval: 5 minutes (free tier minimum)

The `/health` endpoint is deliberately lightweight — it checks DB connectivity but makes no
complex queries. A ping response from Render resets the 15-minute inactivity timer.

**Trade-off:** This effectively makes the service always-on, consuming all 750 hours/month.
This is intentional — the service is needed during church hours and potentially 24/7 for
members in different time zones.

### Solution 2: Frontend Preloader

In the Flutter app's startup, send a silent preload request to the API when the login page loads:

```dart
// In LoginPage initState
Future<void> _preloadApi() async {
  try {
    await ApiClient.get('/health', timeout: const Duration(seconds: 5));
  } catch (_) {
    // Silently ignore errors — this is a warm-up request only
  }
}
```

This gives the API ~5-10 seconds to wake up while the user reads the login screen.

### Solution 3: Optimized Startup Time

The current FastAPI app is already optimized for fast startup:
- `asynccontextmanager` lifespan hook runs only DB check on startup
- No heavy ML models or large in-memory caches to load
- Dependencies are installed at build time, not startup

Estimated startup time breakdown:
- Python interpreter start: ~0.5s
- FastAPI + middleware load: ~1.5s
- SQLAlchemy pool creation: ~2s
- First DB connection: ~3-5s (network to Supabase)
- Total: ~7-9 seconds (better than typical 20-40s cold start)

### Solution 4: Horizontal Scaling on Render Starter (Future)

When upgrading to Render Starter ($7/month), enable "Zero-downtime deploys" which keeps
one instance running at all times. Cold starts become a non-issue.

---

## 4. Database Connection Pooling Strategy

### The Problem with Serverless/Free-Tier Deployments

Traditional SQLAlchemy connection pools open persistent connections to PostgreSQL. With:
- 3 Render services (API + Worker + Beat)
- Each potentially running 2-4 workers
- Supabase PostgreSQL free tier limit: 60 connections

If not managed correctly, connection exhaustion causes `too many connections` errors.

### How Supabase PgBouncer Solves This

Supabase provides two connection strings:

**Port 5432 — Direct (Session Mode)**
- Traditional PostgreSQL connection
- Each application connection = one database connection
- Use for: Alembic migrations, administrative queries
- Max useful connections: 60 (Supabase free tier limit)

**Port 6543 — PgBouncer (Transaction Mode)**
- Connection pooler — multiplexes many app connections onto few DB connections
- One app connection doesn't hold a DB connection during idle time
- Use for: all API runtime queries
- Max effective connections: effectively unlimited from app perspective

### Configuration in This Project

The `DATABASE_URL` in production should use port 6543:

```
postgresql+psycopg2://postgres:[PASS]@db.[REF].supabase.co:6543/postgres?sslmode=require&pgbouncer=true
```

The `pgbouncer=true` query parameter tells SQLAlchemy to disable prepared statements
(which are not supported in PgBouncer transaction mode).

SQLAlchemy pool settings in `database.py`:

```python
engine = create_engine(
    settings.DATABASE_URL,
    pool_size=5,            # Keep 5 connections warm per worker process
    max_overflow=10,        # Allow up to 10 additional burst connections
    pool_pre_ping=True,     # Verify connection health before use (handles Supabase timeouts)
    pool_recycle=300,       # Recycle connections every 5 minutes (avoids stale connections)
    connect_args={
        "connect_timeout": 10,
        "options": "-c timezone=UTC"
    }
)
```

With 2 API workers × (5 pool + 10 overflow) = maximum 30 connections from API alone.
Worker and Beat add another ~15 connections each = 60 total (at the Supabase free tier limit).

**If you exceed the connection limit:**
1. Reduce `pool_size` from 5 to 3 in database.py
2. Or upgrade to Supabase Pro ($25/month) for 200 connections

### Alembic Migrations

Alembic should always use the direct port 5432 connection (not PgBouncer) because
DDL statements require session-level control.

Create a separate Alembic URL in your local `.env`:

```bash
# For migrations only — use port 5432, not 6543
ALEMBIC_DATABASE_URL=postgresql+psycopg2://postgres:[PASS]@db.[REF].supabase.co:5432/postgres?sslmode=require
```

Run migrations locally:

```bash
# In backend/ directory
alembic -x dburl=$ALEMBIC_DATABASE_URL upgrade head
```

---

## 5. Redis Key Naming Conventions and TTL Strategy

### Key Naming Convention

All Redis keys follow the format: `{namespace}:{type}:{identifier}`

| Namespace | Type | Identifier | Example |
|-----------|------|-----------|---------|
| `genesis` | `blacklist` | JWT token ID (jti) | `genesis:blacklist:abc123-def456` |
| `genesis` | `ratelimit:auth` | IP address | `genesis:ratelimit:auth:192.168.1.1` |
| `genesis` | `ratelimit:api` | User ID or IP | `genesis:ratelimit:api:user:uuid-here` |
| `genesis` | `session` | User ID | `genesis:session:uuid-here` |
| `genesis` | `cache` | Resource key | `genesis:cache:member:uuid-here` |

### TTL Strategy

Every key in Redis has a TTL (time to live). No key lives forever.

| Key Type | TTL | Rationale |
|----------|-----|-----------|
| `blacklist:{jti}` | Remaining lifetime of the JWT | Token becomes invalid at natural expiry regardless; blacklist just makes logout immediate |
| `ratelimit:auth:{ip}` | 900 seconds (15 minutes) | Matches `RATE_LIMIT_AUTH_WINDOW_SECONDS`. Resets after window. |
| `ratelimit:api:{user}` | 60 seconds | Per-minute API rate limiting per user |
| `session:{user_id}` | 86400 seconds (24 hours) | Matches `ACCESS_TOKEN_EXPIRE_HOURS` |
| `cache:member:{id}` | 300 seconds (5 minutes) | Member data refreshed every 5 minutes |

### Implementation Pattern

```python
# Token blacklisting on logout
async def blacklist_token(jti: str, expires_at: datetime, redis: Redis):
    remaining_ttl = int((expires_at - datetime.utcnow()).total_seconds())
    if remaining_ttl > 0:
        await redis.setex(
            f"genesis:blacklist:{jti}",
            remaining_ttl,
            "1"
        )

# Check if token is blacklisted
async def is_token_blacklisted(jti: str, redis: Redis) -> bool:
    return await redis.exists(f"genesis:blacklist:{jti}") > 0

# Rate limit check
async def check_auth_rate_limit(ip: str, redis: Redis) -> bool:
    key = f"genesis:ratelimit:auth:{ip}"
    count = await redis.incr(key)
    if count == 1:
        await redis.expire(key, settings.RATE_LIMIT_AUTH_WINDOW_SECONDS)
    return count <= settings.RATE_LIMIT_AUTH_ATTEMPTS
```

### Upstash-Specific Considerations

Upstash Redis has a 256MB data limit on the free tier. At an estimated:
- 500 active tokens (blacklist keys): ~500 × 100 bytes = 50KB
- 1,000 rate limit keys: ~1,000 × 50 bytes = 50KB
- Total Redis usage: <1MB

This is negligible. The 256MB limit would only be reached if caching large objects in Redis,
which this application does not do.

---

## 6. Cost Projection and Growth Model

### Baseline: Current State (500 Members, 50 Active Users)

| Service | Monthly Cost |
|---------|-------------|
| Vercel | $0 |
| Render (API + Worker + Beat) | $0 |
| Supabase | $0 |
| Upstash | $0 |
| Flutterwave | $0 (charges per transaction) |
| Termii | Variable (pay-as-you-go, ~$0-5/month) |
| SendGrid | $0 (within 100 emails/day) |
| UptimeRobot | $0 (free tier) |
| **Total Fixed** | **$0/month** |

Transaction costs (variable):
- Flutterwave: 1.4% + NGN 100 per donation/payment
- Termii: ~NGN 2-4 per SMS
- These are passed through as operational costs, not infrastructure costs

### Growth Scenario 1: 1,000 Members, 100 Active Users

No infrastructure changes needed. All services remain within free tier.

- Database: ~30-40MB (still well within 500MB)
- API requests: ~5,000-10,000/day (Redis comfortably handles this)
- Email: ~80-100 emails/day (at limit — watch carefully)

**Trigger to watch:** SendGrid emails. If sending weekly newsletters to 1,000 members,
you'll hit 1,000 emails per batch = 10x the daily limit.

**Mitigation:** Send newsletters in batches over 10 days, or upgrade SendGrid ($19.95/month).

### Growth Scenario 2: 2,000 Members, 200 Active Users

**Changes needed:**
- SendGrid: upgrade to Essentials ($19.95/month) for 40,000 emails/month
- Render API: may need Starter ($7/month) if CPU hours exceed 750
- Upstash: may exceed 10,000 commands/day — upgrade to pay-as-you-go (~$5-10/month)

**Estimated monthly cost: ~$32-37/month**

### Growth Scenario 3: 5,000 Members, 500 Active Users (Diocese Level)

**Changes needed:**
- Supabase Pro ($25/month): database approaching 500MB limit, need 200 connections
- Render Starter for all three services ($21/month): CPU hours exhausted
- SendGrid Essentials ($19.95/month): email volume
- Upstash pay-as-you-go ($10-20/month): high Redis usage
- Vercel Pro ($20/month): may exceed bandwidth if 5,000 members download app monthly

**Estimated monthly cost: ~$96-107/month**

### Cost Decision Framework

| Threshold | Signal | Action | Monthly Cost Impact |
|-----------|--------|--------|---------------------|
| Render CPU > 700 hrs | Render Dashboard → Metrics | Upgrade API to Starter | +$7/month |
| DB > 400MB | Supabase Dashboard → Storage | Upgrade to Supabase Pro | +$25/month |
| Redis > 8,000 cmds/day | Upstash Console → Metrics | Switch to pay-as-you-go | +$2-10/month |
| Email > 90 emails/day | SendGrid Activity → Volume | Upgrade to Essentials | +$19.95/month |
| Service crashes daily | Render Logs | Upgrade affected service | +$7/month/service |

The architecture is designed so each service can be upgraded independently. You do not need to
upgrade everything at once — upgrade only the service that is hitting its limit.
