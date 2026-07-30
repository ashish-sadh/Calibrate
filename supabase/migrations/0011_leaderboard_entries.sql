-- 0011 — one table for ARBITRARILY MANY leaderboards.
--
-- Supersedes 0009's `weekly_stats`, which hardcoded four columns (steps,
-- calories, workouts logged/imported). The operator's direction (2026-07-30):
-- "highest deadlift in the last month … figure out how it can be multiple of
-- this. Like steps, deadlift highest weight etc." A fixed-column table needs a
-- migration per board, which means boards only exist if someone ships one.
--
-- So a board is DATA, not schema: `board_key` names it, and a new board is a new
-- string. `lift:deadlift` and `steps` are the same row shape.
--
--   user_id + board_key + period_start  →  value
--
-- WHY THIS SCALES:
--   * Primary key IS the read pattern. The client asks
--     `user_id=in.(<friends>)&period_start=in.(<week>,<month>)` — a PK-prefix
--     probe per person. Cost grows with YOUR friend count (capped 150), flat in
--     total users. Never query without a user_id list: RLS *would* filter for
--     you, but Postgres would evaluate are_connected() once per row in the
--     period, i.e. once per user in the product. Measured on a 200k-row replica
--     for the 0009 shape: 0.33 ms with the id list vs 21 ms scanning the period,
--     and only the second number grows as Drift does.
--   * Rows per user are BOUNDED by the client, which publishes at most
--     `LeaderboardPublisher.maxBoards` keys per period. Without that cap a user
--     with 300 distinct exercises would publish 300 rows per month and the
--     friend fan-in would be 150 × 300.
--   * value is numeric, unit is a label. Ranking never needs to parse a string.
--
-- REPLACING 0009 SAFELY. `weekly_stats` is dropped, and that is allowed here
-- ONLY because it provably holds nothing and no released client can write it:
-- it was created 2026-07-30 after builds 371/72 shipped, and its row count was
-- verified 0 immediately before this migration ran. Any table with a single row,
-- or any table a published build touches, would be carried across instead —
-- see the user-data tenet. The DROP is guarded on emptiness so it cannot
-- silently discard data if that assumption is ever wrong.

create table if not exists public.leaderboard_entries (
    user_id      uuid not null references public.profiles(id) on delete cascade,
    -- Namespaced so a new family of boards can't collide with an old one:
    -- 'steps', 'calories', 'workouts', 'lift:deadlift', 'lift:bench_press'.
    board_key    text not null check (board_key ~ '^[a-z0-9_]+(:[a-z0-9_]+)?$'),
    -- The window this value covers. A date, not a timestamp — the period is the
    -- identity, and a timestamp would let two time zones write two rows for one
    -- week. Weekly boards use the Monday; monthly boards use the 1st.
    period_start date not null,
    -- Higher is better for every board shipped so far. Kept as plain numeric so
    -- lbs, kcal and step counts share one column; `unit` is presentation only.
    value        numeric not null check (value >= 0),
    unit         text not null default '',
    updated_at   timestamptz not null default now(),
    primary key (user_id, board_key, period_start)
);

alter table public.leaderboard_entries enable row level security;

drop policy if exists leaderboard_read_connected on public.leaderboard_entries;
create policy leaderboard_read_connected
    on public.leaderboard_entries for select
    to authenticated
    using (user_id = auth.uid() or public.are_connected(user_id));

drop policy if exists leaderboard_insert_self on public.leaderboard_entries;
create policy leaderboard_insert_self
    on public.leaderboard_entries for insert
    to authenticated with check (user_id = auth.uid());

drop policy if exists leaderboard_update_self on public.leaderboard_entries;
create policy leaderboard_update_self
    on public.leaderboard_entries for update
    to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Turning sharing off must REMOVE what was published. A switch that only stops
-- future writes leaves last month's deadlift on other people's boards, which is
-- not what anyone means by turning it off.
drop policy if exists leaderboard_delete_self on public.leaderboard_entries;
create policy leaderboard_delete_self
    on public.leaderboard_entries for delete
    to authenticated using (user_id = auth.uid());

comment on table public.leaderboard_entries is
    'One row per (user, board, period). board_key is data, not schema — a new leaderboard is a new string, no migration. Read ONLY with an explicit user_id=in.(...) list; see the 0011 header for why RLS must not be the filter.';

-- ---------------------------------------------------------------------------
-- Retire weekly_stats — guarded, so it can only vanish if it is truly empty.
-- ---------------------------------------------------------------------------
do $$
declare
    n bigint;
begin
    if exists (select 1 from information_schema.tables
               where table_schema = 'public' and table_name = 'weekly_stats') then
        execute 'select count(*) from public.weekly_stats' into n;
        if n = 0 then
            drop table public.weekly_stats;
            raise notice 'weekly_stats was empty — dropped, superseded by leaderboard_entries';
        else
            raise exception
                'weekly_stats holds % row(s) — refusing to drop. Backfill into leaderboard_entries first.', n;
        end if;
    end if;
end $$;
