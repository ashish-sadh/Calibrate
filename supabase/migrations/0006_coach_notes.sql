-- ---------------------------------------------------------------------------
-- 0006 — notes a HUMAN coach writes for their client.
--
-- Until now every note in the system was written BY the app (Coach Me intake
-- answers, AI-distilled chat moments) and flowed client → coach through
-- `client_briefings`. A coach had no way to write anything down, and the
-- AI-authored notes read as if the coach had written them (operator
-- 2026-07-29). This table is the other direction, and it is deliberately a
-- SEPARATE table rather than a column on client_briefings:
--
-- 1. OPPOSITE AUTHOR, OPPOSITE RLS. `client_briefings` is client-write /
--    coach-read, precisely so a coach cannot edit their client's history.
--    Coach notes invert that: coach writes, client reads. Two directions of
--    trust do not belong in one row.
-- 2. THE CLIENT ALWAYS SEES THEM. There is no private-to-coach mode. A note
--    about someone that they cannot read is a file kept on a person, which is
--    not what Drift is. The composer says so before you type.
-- 3. DATED AND ATTRIBUTED. Every note carries its own created_at, so a client
--    reads a timeline ("2026-07-29 — from Cindy"), not an undated verdict.
-- 4. EITHER PARTY CAN DELETE. The coach can retract; the client can remove a
--    note about themselves. Neither can edit the other's words.
-- ---------------------------------------------------------------------------

create table if not exists public.coach_notes (
    id         uuid primary key default gen_random_uuid(),
    coach_id   uuid not null references auth.users(id) on delete cascade,
    client_id  uuid not null references auth.users(id) on delete cascade,
    text       text not null,
    created_at timestamptz not null default now()
);

create index if not exists coach_notes_pair_idx
    on public.coach_notes (client_id, coach_id, created_at desc);

alter table public.coach_notes enable row level security;

-- Policies are dropped first so this file is RE-RUNNABLE: CREATE POLICY has no
-- IF NOT EXISTS, and a migration that cannot be run twice safely is not
-- finished. Dropping a policy destroys no rows — only the declaration.

-- Both parties read; nobody else, ever.
drop policy if exists coach_notes_read_parties on public.coach_notes;
create policy coach_notes_read_parties
    on public.coach_notes for select
    to authenticated
    using (coach_id = auth.uid() or client_id = auth.uid());

-- Only the coach writes, and only about someone they are actually connected
-- to — are_connected() is what stops writing notes onto a stranger.
drop policy if exists coach_notes_insert_coach on public.coach_notes;
create policy coach_notes_insert_coach
    on public.coach_notes for insert
    to authenticated
    with check (coach_id = auth.uid() and public.are_connected(client_id));

-- Retraction (coach) and removal (client): either party may delete, neither
-- may rewrite the other's words — there is no UPDATE policy on purpose.
drop policy if exists coach_notes_delete_parties on public.coach_notes;
create policy coach_notes_delete_parties
    on public.coach_notes for delete
    to authenticated
    using (coach_id = auth.uid() or client_id = auth.uid());
