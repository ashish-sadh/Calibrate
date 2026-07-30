-- 0014 — record the AUDIENCE on a client-owned workout.
--
-- Additive: one column with a safe default, one policy rewrite. Re-runnable.
-- Nothing is read, moved, rewritten or deleted.
--
-- WHY. 0012 made a workout storable ONCE, client-owned, with the audience derived
-- from live relationships — which is what lets a new coach see the base work. But
-- derived-from-relationships is all-or-nothing per class, and the completion
-- sheet has two independent switches ("share with friends" / "share with my
-- coach", operator 2026-07-29). A purely derived audience cannot express
-- "coaches but not friends": the row would leak to friends inside the 30-day
-- window, silently overriding a switch the user had turned off. A toggle that
-- doesn't hold is worse than no toggle.
--
-- So the audience the user chose is STORED, and the policy intersects it with the
-- relationships that exist now:
--
--   audience    friends see (30d)   current coach sees (all history)
--   'all'              yes                       yes
--   'coaches'          no                        yes
--   'private'          no                        no
--
-- Defaults to 'all', which is what the pre-0014 rows meant — they were shared
-- deliberately, per recipient, so treating them as broadly visible preserves
-- what those users chose rather than quietly narrowing it.

alter table public.live_workouts
    add column if not exists audience text not null default 'all'
    check (audience in ('all', 'coaches', 'private'));

-- Rewritten to intersect stored audience with live relationship.
drop policy if exists live_workouts_read_parties on public.live_workouts;
create policy live_workouts_read_parties
    on public.live_workouts for select
    to authenticated
    using (
        -- Always your own, whatever the audience says.
        client_id = auth.uid()
        -- Legacy per-recipient rows: the named recipient still reads them.
        or trainer_id = auth.uid()
        -- Client-owned rows: stored audience AND current relationship.
        or (trainer_id is null and audience <> 'private' and (
                -- A CURRENT coach sees everything, including work logged before
                -- they arrived. The "start from the base work" case, and the
                -- reason retention is a read window rather than a delete.
                public.is_coach_of(client_id)
                -- Friends only when the user shared with friends, and only
                -- inside the rolling window.
                or (audience = 'all'
                    and public.are_connected(client_id)
                    and started_at >= now() - interval '30 days')
           ))
    );

comment on column public.live_workouts.audience is
    'all | coaches | private — the audience the USER chose at save time, intersected at read time with the relationships that exist now (see 0014). Defaults to all, which is what pre-0014 per-recipient rows meant.';
