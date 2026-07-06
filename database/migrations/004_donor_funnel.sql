-- ============================================================================
-- Genesis Global CMS — Migration 004: Donor Payment Reminder & Tracking Funnel
--
-- 1. sponsor_payments.reminder_stage — tracks which funnel stage has fired for
--    the current payment cycle (0 = none, 1 = weekly reminder, 2 = week-3
--    nudge, 3 = final notice). A new cycle starts a new payment row, so the
--    stage resets naturally when the donor pays.
--
-- 2. app_settings — small key/value store (JSONB) for runtime-configurable
--    settings, starting with the funnel reminder schedule so intervals are
--    admin-configurable instead of hardcoded.
--
-- Idempotent: safe to re-run.
-- ============================================================================

ALTER TABLE sponsor_payments
    ADD COLUMN IF NOT EXISTS reminder_stage INTEGER NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS app_settings (
    key         VARCHAR(100) PRIMARY KEY,
    value       JSONB        NOT NULL,
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_by  UUID         REFERENCES app_users(id) ON DELETE SET NULL
);

-- Funnel scans: latest completed payment per sponsor with a due date
CREATE INDEX IF NOT EXISTS idx_sp_funnel_stage
    ON sponsor_payments (next_due_date, reminder_stage)
    WHERE status = 'COMPLETED' AND next_due_date IS NOT NULL AND deleted_at IS NULL;
