-- 0013 — actually run the retention we wrote in 0002.
--
-- Additive: one extension, one schedule. No table is touched by this file; the
-- job it schedules only DELETES telemetry, never user content.
--
-- THE GAP. 0002 defined `prune_telemetry()` — 90 days for `ai_turns` (they carry
-- health content), 365 for `telemetry_events` — with a comment saying "run from
-- the scheduler (pg_cron) or manually". Nothing ever called it, and pg_cron was
-- not installed, so retention existed as an intention. `telemetry_events` was
-- already the largest table in the database (5,090 rows in ~31 hours, from a
-- handful of installs) and grows with users × events forever.
--
-- WHY THIS IS ONLY LANDING NOW: I had written "there is no server-side
-- application code" as a constraint on this project and reasoned from it —
-- wrongly. Postgres functions ARE server-side code (we already ship several),
-- pg_cron was available all along, and `supabase_realtime` already publishes
-- `messages`. The operator asked "I think supabase has something to run on
-- server side?" and was right. Docs/designs/social-scale-limits.md is corrected.

create extension if not exists pg_cron;

-- 03:20 UTC daily — a quiet hour, and off the hour so it doesn't pile up with
-- everything else scheduled at :00.
--
-- `schedule` is idempotent by job name: re-running this file re-points the same
-- job rather than creating a second one, which is what makes the migration
-- safely repeatable.
select cron.schedule(
    'prune-telemetry-daily',
    '20 3 * * *',
    $$select public.prune_telemetry();$$
);

comment on extension pg_cron is
    'Scheduled jobs. Currently: prune-telemetry-daily (0013). Note that user CONTENT has no scheduled deletion by design — retention for shared workouts is a READ WINDOW (0012), never a DELETE, so that a client changing coaches keeps their base work.';
