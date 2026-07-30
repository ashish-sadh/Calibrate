-- 0009 — weekly activity stats, for the friends leaderboard.
--
-- Additive: one new table. Nothing existing is read, moved or rewritten, and
-- the file is re-runnable (IF NOT EXISTS + drop-then-create on policies).
--
-- SHAPE: one row per person per WEEK, upserted. Not a row per day and not a
-- row per sync — 52 rows per user per year, bounded forever, and the primary
-- key is exactly the lookup the leaderboard performs. Steps are ambient data
-- from HealthKit / Health Connect, so "this week's total" is the smallest thing
-- that answers the question; a daily series would be 7× the rows and would let
-- a coach or friend reconstruct a person's schedule, which is more than a
-- leaderboard needs to know.
--
-- HOW IT SCALES. The client ALWAYS passes an explicit
-- `user_id=in.(<friend ids>)&week_start=eq.<date>` filter, chunked to 50 ids.
-- That's a primary-key probe per friend: cost grows with YOUR friend count
-- (capped at 150) and stays flat as the user table grows.
--
-- The trap deliberately avoided: RLS below *would* allow
-- `select * from weekly_stats where week_start = X` and correctly return only
-- your friends' rows — but Postgres would have to evaluate `are_connected()`
-- for EVERY row in that week, i.e. once per user in the whole product. That
-- reads as "elegant, let RLS do the filtering" and is O(all users) per
-- leaderboard open. RLS here is a SECURITY check on a small candidate set, not
-- the filter. Never query this table without a user_id list.

create table if not exists public.weekly_stats (
    user_id           uuid not null references public.profiles(id) on delete cascade,
    -- Monday-anchored ISO week. A date, not a timestamp: the week is the
    -- identity, and a timestamp would let two devices in different zones write
    -- two rows for the same week.
    week_start        date not null,
    steps             integer not null default 0 check (steps >= 0),
    calories_burned   integer not null default 0 check (calories_burned >= 0),
    -- Split on purpose: a workout someone recorded is a different claim from one
    -- their watch noticed, and summing them silently rewards owning a watch.
    workouts_logged   integer not null default 0 check (workouts_logged >= 0),
    workouts_imported integer not null default 0 check (workouts_imported >= 0),
    updated_at        timestamptz not null default now(),
    primary key (user_id, week_start)
);

alter table public.weekly_stats enable row level security;

-- READ: your own rows, and rows of people you're connected to. Publishing is
-- opt-in client-side (Preferences.shareStatsWithFriends) — this policy governs
-- who MAY read a published row, not whether one exists.
drop policy if exists weekly_stats_read_connected on public.weekly_stats;
create policy weekly_stats_read_connected
    on public.weekly_stats for select
    to authenticated
    using (user_id = auth.uid() or public.are_connected(user_id));

-- WRITE: your own row only. Nobody can inflate — or flatter — someone else.
drop policy if exists weekly_stats_insert_self on public.weekly_stats;
create policy weekly_stats_insert_self
    on public.weekly_stats for insert
    to authenticated with check (user_id = auth.uid());

drop policy if exists weekly_stats_update_self on public.weekly_stats;
create policy weekly_stats_update_self
    on public.weekly_stats for update
    to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- DELETE: your own row. Turning sharing off must be able to REMOVE what was
-- already published — a switch that only stops future writes leaves last week's
-- numbers visible and is not consent.
drop policy if exists weekly_stats_delete_self on public.weekly_stats;
create policy weekly_stats_delete_self
    on public.weekly_stats for delete
    to authenticated using (user_id = auth.uid());

comment on table public.weekly_stats is
    'One row per user per ISO week: steps, calories burned, workouts (logged vs imported). Read ONLY with an explicit user_id=in.(...) list — see 0009 header for why RLS must not be used as the filter.';
