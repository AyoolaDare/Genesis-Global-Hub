-- ============================================================================
-- Genesis Global CMS — Migration 003: Finance domain indexes for scale
--
-- Purpose: keep the sponsorship/payments domain fast as donor volume grows
-- from tens to tens of thousands. Each index below matches a specific hot
-- query in the backend:
--
--   1. idx_sp_reconcile      → reconcile_pending_payments: finds PENDING
--                              Flutterwave payments in a created_at window.
--   2. idx_sp_sponsor_status → per-sponsor payment history filtered by status
--                              (sponsor detail page, overdue calculations).
--   3. idx_sp_completed_date → dashboard revenue aggregates over
--                              payment_date for COMPLETED payments only.
--   4. idx_sp_thank_you_gap  → ops monitoring: completed payments whose
--                              thank-you was never delivered.
--   5. idx_nq_process_queue  → process_notification_queue: due PENDING items
--                              under the retry limit, ordered by schedule.
--   6. idx_sponsors_name_lower → case-insensitive sponsor search.
--
-- All statements are idempotent (IF NOT EXISTS) and safe to re-run.
-- ============================================================================

-- 1. Reconcile scan: PENDING Flutterwave payments by age
CREATE INDEX IF NOT EXISTS idx_sp_reconcile
    ON sponsor_payments (status, payment_method, created_at)
    WHERE deleted_at IS NULL;

-- 2. Per-sponsor history filtered by status
CREATE INDEX IF NOT EXISTS idx_sp_sponsor_status
    ON sponsor_payments (sponsor_id, status)
    WHERE deleted_at IS NULL;

-- 3. Revenue aggregates: COMPLETED payments by payment_date
CREATE INDEX IF NOT EXISTS idx_sp_completed_date
    ON sponsor_payments (payment_date DESC)
    WHERE status = 'COMPLETED' AND deleted_at IS NULL;

-- 4. Thank-you coverage gap: completed but never thanked
CREATE INDEX IF NOT EXISTS idx_sp_thank_you_gap
    ON sponsor_payments (payment_date)
    WHERE status = 'COMPLETED' AND thank_you_sent_at IS NULL AND deleted_at IS NULL;

-- 5. Notification queue processing order
CREATE INDEX IF NOT EXISTS idx_nq_process_queue
    ON notification_queue (scheduled_for, retry_count)
    WHERE status = 'PENDING';

-- 6. Case-insensitive sponsor name search
CREATE INDEX IF NOT EXISTS idx_sponsors_name_lower
    ON sponsors (lower(full_name))
    WHERE deleted_at IS NULL;
