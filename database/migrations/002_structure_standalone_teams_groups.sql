-- Allow teams and groups to exist independently from departments.
-- Existing department/team links remain valid when present.

ALTER TABLE teams
  ALTER COLUMN department_id DROP NOT NULL;

ALTER TABLE groups
  ALTER COLUMN department_id DROP NOT NULL;
