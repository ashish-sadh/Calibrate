-- 0012 — global boards, profile discovery, and retention as a READ WINDOW.
--
-- Additive. Re-runnable. No existing row is read, moved, rewritten or deleted.
--
-- HOW THE RETENTION DESIGN CHANGED, MID-WRITE. The first draft of this file
-- pruned shared workouts older than 30 days and let a coach's copies die with
-- the coaching relationship. The operator stopped it: "I don't want coach
-- history to get lost — what if someone wants to restart or transfer coaching, I
-- want them to start with some base work."
--
-- That was right, and it was a tenet violation I should have caught myself:
-- losing ACCESS to data is losing it. A client's training history is the
-- CLIENT'S. It must survive changing coaches, and a new coach should be able to
-- start from the base work rather than from nothing.
--
-- So retention is no longer deletion. Nothing is deleted:
--   * ONE row per workout, owned by the client (`trainer_id is null`), instead
--     of one row per recipient. Audience is derived AT READ TIME from the
--     relationships that exist right now.
--   * A CURRENT coach reads the full history — including everything logged
--     before they became the coach, which is exactly the "base work" case.
--   * An EX-coach reads nothing. Access follows the live relationship, which the
--     old per-recipient rows got backwards: they let a former coach keep reading
--     forever while hiding the same history from the next one.
--   * FRIENDS read a rolling 30-day window. Same rows, narrower view — a friend
--     seeing less is a policy, not a deletion.
--
-- Legacy per-recipient rows (trainer_id set) keep working untouched.

-- ---------------------------------------------------------------------------
-- 1. Visibility on leaderboard entries
-- ---------------------------------------------------------------------------
-- Per ROW, not per user: someone can put their steps on a global board while
-- keeping their deadlift among friends. Defaults to 'friends', so an older
-- client that doesn't know this column exists keeps publishing privately —
-- silence must never widen exposure.
alter table public.leaderboard_entries
    add column if not exists visibility text not null default 'friends'
    check (visibility in ('friends', 'global'));

-- THE index that makes a global board cheap. PARTIAL, so it carries only rows
-- someone chose to publish globally — a fraction of the table, and it cannot be
-- used to enumerate private rows.
--
-- Measured at 2.2M rows: global top-100 goes from 4,173 ms (bitmap scan + top-N
-- heapsort over 200k rows) to 6 ms (index scan, 100 rows); the "20 nearest my
-- value" bracket query is 2.5 ms. Without it a global board is a table scan per
-- open; with it, an ordered read.
create index if not exists leaderboard_global_rank
    on public.leaderboard_entries (board_key, period_start, value desc)
    where visibility = 'global';

drop policy if exists leaderboard_read_connected on public.leaderboard_entries;
create policy leaderboard_read_connected
    on public.leaderboard_entries for select
    to authenticated
    using (
        user_id = auth.uid()
        or visibility = 'global'
        or public.are_connected(user_id)
    );

-- ---------------------------------------------------------------------------
-- 2. Relationship helpers
-- ---------------------------------------------------------------------------
-- Is the CALLER currently the coach of `client`? The trainer edge is
-- requester = client, addressee = coach (0001's convention).
--
-- SECURITY DEFINER because the caller cannot read someone else's edges, `stable`
-- so the planner can hoist it, and a pinned search_path.
create or replace function public.is_coach_of(client uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from public.friendships f
        where f.status = 'accepted' and f.role = 'trainer'
          and f.requester_id = client
          and f.addressee_id = auth.uid()
    );
$$;

revoke all on function public.is_coach_of(uuid) from public;
grant execute on function public.is_coach_of(uuid) to authenticated;

-- Mutual friends as a COUNT, never a list. "3 mutual friends" is the social
-- proof that makes a stranger's request legible; naming them would let anyone
-- standing on a global board enumerate a stranger's social graph, which is a
-- different and much worse feature.
create or replace function public.mutual_friend_count(other uuid)
returns int language sql stable security definer set search_path = public as $$
    with mine as (
        select case when f.requester_id = auth.uid() then f.addressee_id
                    else f.requester_id end as id
        from public.friendships f
        where f.status = 'accepted'
          and auth.uid() in (f.requester_id, f.addressee_id)
    ),
    theirs as (
        select case when f.requester_id = other then f.addressee_id
                    else f.requester_id end as id
        from public.friendships f
        where f.status = 'accepted'
          and other in (f.requester_id, f.addressee_id)
    )
    select count(*)::int
    from mine join theirs using (id)
    -- Neither party is their own mutual.
    where mine.id not in (auth.uid(), other);
$$;

revoke all on function public.mutual_friend_count(uuid) from public;
grant execute on function public.mutual_friend_count(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Client-owned activity + audience at read time
-- ---------------------------------------------------------------------------
-- `trainer_id` becomes nullable so a workout can be stored ONCE, owned by the
-- client, rather than copied per recipient. Widening a NOT NULL is additive:
-- every existing row still satisfies it.
alter table public.live_workouts alter column trainer_id drop not null;

-- Serves the friends' 30-day window without scanning a client's whole history.
create index if not exists live_workouts_client_recent
    on public.live_workouts (client_id, started_at desc);

-- The audience rule, in one policy.
drop policy if exists live_workouts_read_parties on public.live_workouts;
create policy live_workouts_read_parties
    on public.live_workouts for select
    to authenticated
    using (
        -- Always your own.
        client_id = auth.uid()
        -- Legacy per-recipient rows: the named recipient still reads them.
        or trainer_id = auth.uid()
        -- Client-owned rows: audience derived from live relationships.
        or (trainer_id is null and (
                -- A CURRENT coach sees everything, including work logged before
                -- they arrived. This is the "start from the base work" case, and
                -- it's the whole reason retention isn't deletion.
                public.is_coach_of(client_id)
                -- A friend sees a rolling 30-day window. Narrower view of the
                -- same rows — no data is destroyed to achieve it.
                or (public.are_connected(client_id)
                    and started_at >= now() - interval '30 days')
           ))
    );

-- Client-owned inserts: `trainer_id` may be null now, so the old
-- `are_connected(trainer_id)` check has to tolerate that. Still client-only.
drop policy if exists live_workouts_insert_client on public.live_workouts;
create policy live_workouts_insert_client
    on public.live_workouts for insert
    to authenticated
    with check (
        client_id = auth.uid()
        and (trainer_id is null or public.are_connected(trainer_id))
    );

-- A user may withdraw their OWN share. The owner, never the recipient: a coach
-- must not be able to erase a client's history. This capability did not exist
-- before — `live_workouts` had no delete policy at all, so nothing shared could
-- ever be taken back.
--
-- Deliberately NOT wired to any automatic pruning. Retention is the read window
-- above; this is for a person choosing to remove something.
drop policy if exists live_workouts_delete_client on public.live_workouts;
create policy live_workouts_delete_client
    on public.live_workouts for delete
    to authenticated using (client_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 4. Public activity — what a stranger sees on a profile
-- ---------------------------------------------------------------------------
-- Workout NAME and DATE only. No sets, no weights, no duration: enough to tell
-- whether someone trains the way you do, which is the whole job of a profile
-- reached from a leaderboard. Everything else waits until you're connected.
--
-- GATED ON THE OWNER HAVING OPTED INTO A GLOBAL BOARD. Someone who never chose
-- to be discoverable this way has no public activity, whatever anyone knows
-- about their id — that gate is why this is safe to expose at all. Also window
-- limited: a stranger sees the last 30 days, not a training career.
create or replace function public.public_activity(other uuid, max_rows int default 10)
returns table (name text, workout_date date) language sql stable
security definer set search_path = public as $$
    -- `template_name`, not `name` — the column is what the session was called
    -- when it started, which is the honest label for a stranger's feed.
    select coalesce(w.template_name, 'Workout'), w.started_at::date
    from public.live_workouts w
    where w.client_id = other
      and w.started_at >= now() - interval '30 days'
      and exists (
          select 1 from public.leaderboard_entries e
          where e.user_id = other and e.visibility = 'global'
      )
    order by w.started_at desc
    limit least(greatest(max_rows, 1), 25)
$$;

revoke all on function public.public_activity(uuid, int) from public;
grant execute on function public.public_activity(uuid, int) to authenticated;

comment on column public.leaderboard_entries.visibility is
    'friends | global. Per ROW so steps can be global while a lift stays private. Defaults to friends: an older client that never sets it keeps publishing privately.';
comment on column public.live_workouts.trainer_id is
    'NULL = client-owned row, audience derived at read time (current coach: full history; friend: rolling 30 days). Non-null = legacy per-recipient row from before 0012. Nothing is pruned — a client''s history must survive changing coaches so the next one can start from the base work.';
