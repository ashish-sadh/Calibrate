-- 0015 — history is FOREVER, and the client chooses how much of it a coach gets.
--
-- Additive: one table, one policy rewrite. Re-runnable. Nothing is read, moved,
-- rewritten or deleted — and nothing in this file can ever delete a workout.
--
-- TWO THINGS THE OPERATOR SEPARATED (2026-07-30): "Forever history, and client
-- gets option to transfer forever history."
--
-- 1. FOREVER. There is no cap and no pruning on a client's own training history.
--    The 90-day figure in the 0012 verification was a test FIXTURE's age, not a
--    limit. A coach reading "full history" reads all of it, back to the first
--    session ever logged. Friends' 30-day window is a narrower VIEW of those
--    same rows; it has never meant deletion.
--
-- 2. BUT NOT AUTOMATICALLY. A coach you connected to today seeing your entire
--    training past the moment they accept is a lot to hand over silently, and it
--    is not what "add a coach" reads like. So the default is "from when we
--    started", and handing over the rest is a deliberate act — the transfer the
--    operator asked for.
--
-- THE RULE, in one place:
--
--   no row for (client, coach)   → from `friendships.created_at`, i.e. from when
--                                  they became your coach. The safe default,
--                                  and it needs no write when a coach connects.
--   row, history_from IS NULL    → FOREVER. The explicit transfer.
--   row, history_from = a date   → from that date. Lets a client hand over "this
--                                  year" without handing over everything.
--
-- Only the CLIENT may write these rows. A coach cannot grant themselves more of
-- someone's past.

create table if not exists public.coach_history_grants (
    client_id    uuid not null references public.profiles(id) on delete cascade,
    coach_id     uuid not null references public.profiles(id) on delete cascade,
    -- NULL means forever. A date means "on or after this day".
    history_from date,
    updated_at   timestamptz not null default now(),
    primary key (client_id, coach_id)
);

alter table public.coach_history_grants enable row level security;

-- Both parties READ it: a coach must be able to see how far back they can look,
-- or the absence of old sessions is indistinguishable from a client who never
-- trained. Only the client WRITES it.
drop policy if exists coach_history_grants_read on public.coach_history_grants;
create policy coach_history_grants_read
    on public.coach_history_grants for select
    to authenticated using (auth.uid() in (client_id, coach_id));

drop policy if exists coach_history_grants_write_client on public.coach_history_grants;
create policy coach_history_grants_write_client
    on public.coach_history_grants for insert
    to authenticated with check (client_id = auth.uid());

drop policy if exists coach_history_grants_update_client on public.coach_history_grants;
create policy coach_history_grants_update_client
    on public.coach_history_grants for update
    to authenticated using (client_id = auth.uid()) with check (client_id = auth.uid());

drop policy if exists coach_history_grants_delete_client on public.coach_history_grants;
create policy coach_history_grants_delete_client
    on public.coach_history_grants for delete
    to authenticated using (client_id = auth.uid());

-- ---------------------------------------------------------------------------
-- How far back the CALLER may look at `client`'s history.
--
-- Returns the earliest visible instant, or NULL for forever. Kept as a function
-- so the rule lives in exactly one place and the read policy stays legible.
-- ---------------------------------------------------------------------------
create or replace function public.coach_history_floor(client uuid)
returns timestamptz language sql stable security definer set search_path = public as $$
    select case
        -- An explicit grant wins. NULL history_from = forever, so the floor is
        -- NULL and the caller sees everything.
        when exists (select 1 from public.coach_history_grants g
                     where g.client_id = client and g.coach_id = auth.uid())
        then (select g.history_from::timestamptz
              from public.coach_history_grants g
              where g.client_id = client and g.coach_id = auth.uid())
        -- No grant: from when the coaching relationship started.
        else (select f.created_at
              from public.friendships f
              where f.status = 'accepted' and f.role = 'trainer'
                and f.requester_id = client and f.addressee_id = auth.uid()
              order by f.created_at asc
              limit 1)
    end;
$$;

revoke all on function public.coach_history_floor(uuid) from public;
grant execute on function public.coach_history_floor(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Read policy: same shape as 0014, with the coach branch now honouring the floor.
-- ---------------------------------------------------------------------------
drop policy if exists live_workouts_read_parties on public.live_workouts;
create policy live_workouts_read_parties
    on public.live_workouts for select
    to authenticated
    using (
        -- Always your own, whatever anything else says.
        client_id = auth.uid()
        -- Legacy per-recipient rows: the named recipient still reads them.
        or trainer_id = auth.uid()
        or (trainer_id is null and audience <> 'private' and (
                -- A CURRENT coach, back to the floor the client granted. A NULL
                -- floor means forever — the transfer.
                (public.is_coach_of(client_id)
                 and (public.coach_history_floor(client_id) is null
                      or started_at >= public.coach_history_floor(client_id)))
                -- Friends: rolling 30 days, and only when shared with friends.
                or (audience = 'all'
                    and public.are_connected(client_id)
                    and started_at >= now() - interval '30 days')
           ))
    );

comment on table public.coach_history_grants is
    'How far back a coach may read a client''s history. No row = from friendships.created_at; history_from NULL = FOREVER (the explicit transfer); a date = from that day. Client-write only — a coach cannot grant themselves more of someone''s past. Nothing here deletes history; it is a view, and history is kept forever.';
