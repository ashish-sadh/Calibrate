-- 0017 — make "share with friends, NOT my coach" actually hold.
--
-- Additive: widens a CHECK constraint (every existing row already satisfies it)
-- and rewrites one policy. Re-runnable. No row is read, moved, rewritten or
-- deleted.
--
-- THE DEFECT. The completion sheet has two independent switches. 0014 stored the
-- audience precisely so a purely derived one couldn't silently override them —
-- and then the mapping collapsed the exact case the operator asked for:
--
--     from(friends: true, coaches: false) -> .all
--
-- `.all` gives a current coach the row back to the granted history floor. So
-- turning the coach switch OFF while friends stayed ON did nothing, and the
-- completion sheet's summary said "Shared with 3 friends" while the coach could
-- read it. 0014's own header argues "a toggle that doesn't hold is worse than no
-- toggle"; this was that. Found by adversarial review, 2026-07-30 — and a Tier-0
-- test had locked the wrong behaviour in, which is why nothing caught it.
--
-- The four audiences now match the four states of two switches:
--
--   audience     friends (30d)   current coach (to history floor)
--   'all'             yes                    yes
--   'coaches'         no                     yes
--   'friends'         yes                    NO      <- added here
--   'private'         no                     no

alter table public.live_workouts drop constraint if exists live_workouts_audience_check;
alter table public.live_workouts
    add constraint live_workouts_audience_check
    check (audience in ('all', 'coaches', 'friends', 'private'));

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
                -- A CURRENT coach, back to the floor the client granted — but
                -- NOT when the client withheld this session from coaches.
                (audience in ('all', 'coaches')
                 and public.is_coach_of(client_id)
                 and (public.coach_history_floor(client_id) is null
                      or started_at >= public.coach_history_floor(client_id)))
                -- Friends: rolling 30 days, when shared with friends.
                or (audience in ('all', 'friends')
                    and public.are_connected(client_id)
                    and started_at >= now() - interval '30 days')
           ))
    );

comment on column public.live_workouts.audience is
    'all | coaches | friends | private — the audience the USER chose from the two completion-sheet switches, intersected at read time with current relationships. ''friends'' exists because friends-yes/coach-no is a real state the two switches can express and 0014 collapsed into ''all'' (0017).';

-- ---------------------------------------------------------------------------
-- CORRECTION, same session: the first version of the policy above did NOT hold.
--
-- `are_connected()` is role-blind — it returns true for ANY accepted edge,
-- including the trainer edge. So a coach satisfied the FRIENDS branch as well,
-- and `audience = 'friends'` reached them anyway. Verified before believing it:
-- the coach read "all + coaches + friends" when it should have been
-- "all + coaches".
--
-- The friends branch needs a FRIEND edge specifically, not merely a connection.
-- Two people can hold both a friend edge and a trainer edge (that's what
-- promoting a friend to coach does), and in that case they legitimately see both
-- branches — which is correct: they really are both.
create or replace function public.is_friend_of(other uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from public.friendships f
        where f.status = 'accepted' and f.role = 'friend'
          and ( (f.requester_id = auth.uid() and f.addressee_id = other)
             or (f.addressee_id = auth.uid() and f.requester_id = other) )
    );
$$;

revoke all on function public.is_friend_of(uuid) from public;
grant execute on function public.is_friend_of(uuid) to authenticated;

drop policy if exists live_workouts_read_parties on public.live_workouts;
create policy live_workouts_read_parties
    on public.live_workouts for select
    to authenticated
    using (
        client_id = auth.uid()
        or trainer_id = auth.uid()
        or (trainer_id is null and audience <> 'private' and (
                (audience in ('all', 'coaches')
                 and public.is_coach_of(client_id)
                 and (public.coach_history_floor(client_id) is null
                      or started_at >= public.coach_history_floor(client_id)))
                -- `is_friend_of`, NOT `are_connected`: the latter is role-blind
                -- and let a coach through the friends branch.
                or (audience in ('all', 'friends')
                    and public.is_friend_of(client_id)
                    and started_at >= now() - interval '30 days')
           ))
    );
