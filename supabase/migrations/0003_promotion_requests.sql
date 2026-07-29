-- ---------------------------------------------------------------------------
-- 0003 — friend→coach promotion becomes a REQUEST (operator decision
-- 2026-07-29: coaching is a relationship the other person accepts, never an
-- imposed role). A promotion creates a PENDING trainer edge while the
-- accepted friend edge stays untouched — which requires both edges to
-- coexist in the SAME direction, so edge uniqueness widens from
-- (requester, addressee) to (requester, addressee, role).
--
-- Additive and re-runnable: no rows move, nothing is deleted, both steps
-- are guarded. Existing single-edge pairs are untouched.
-- ---------------------------------------------------------------------------
do $$
begin
    if exists (select 1 from pg_constraint
               where conname = 'friendships_requester_id_addressee_id_key') then
        alter table public.friendships
            drop constraint friendships_requester_id_addressee_id_key;
    end if;
    if not exists (select 1 from pg_constraint
                   where conname = 'friendships_edge_role_unique') then
        alter table public.friendships
            add constraint friendships_edge_role_unique
            unique (requester_id, addressee_id, role);
    end if;
end $$;
