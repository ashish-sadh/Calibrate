-- 0004 — the client briefing a human coach inherits.
--
-- Coach Me builds a written history of a client locally (CoachNotes: intake
-- answers, pain ratings, things mentioned in passing, what was recommended and
-- when). This table is how a slice of that reaches a HUMAN coach the client
-- chose, so the coach starts with context instead of re-running the intake
-- over WhatsApp.
--
-- Deliberate constraints, matching the sharing adjudication in Docs/decisions.md:
--
-- 1. OPT-IN PER COACH. A row exists only because the client pushed it to that
--    specific coach. There is no "share with everyone" state — the primary key
--    is (client_id, coach_id), so consent is per relationship.
-- 2. SUMMARY, NOT DIARY. `summary` and `notes` carry the coach briefing — the
--    training-relevant history. `metrics` carries AVERAGES (sleep hours,
--    protein, calories) not meal or sleep rows. A coach needs the trend; the
--    diary is nobody else's business, and averages keep the payload tiny.
-- 3. RLS BOTH WAYS. The client may write only their own row and only to a coach
--    they are actually connected to; the coach may only read. A coach cannot
--    edit their client's history, and nobody outside the pair sees it at all.
-- 4. REVOCABLE. Delete is client-only, and deleting the row is a complete
--    withdrawal — nothing is retained coach-side.
--
-- This is health data (injuries, pain levels, nutrition). Treat every widening
-- of it as a new decision, not a schema tweak.

create table if not exists public.client_briefings (
    client_id   uuid not null references auth.users(id) on delete cascade,
    coach_id    uuid not null references auth.users(id) on delete cascade,
    -- One-line intake summary: days/week, goal, session length, equipment.
    summary     text not null default '',
    -- The dated note log, JSON-encoded (CoachNotes.Note[]).
    notes       jsonb not null default '[]'::jsonb,
    -- Opt-in aggregates: {"avg_sleep_hours":6.4,"avg_protein_g":118,...}.
    -- Absent keys mean "not shared", which is different from zero.
    metrics     jsonb not null default '{}'::jsonb,
    updated_at  timestamptz not null default now(),
    primary key (client_id, coach_id)
);

create index if not exists client_briefings_coach_idx
    on public.client_briefings (coach_id, updated_at desc);

alter table public.client_briefings enable row level security;

-- Either party reads; only the pair, never a third account.
create policy client_briefings_read_parties
    on public.client_briefings for select
    to authenticated
    using (client_id = auth.uid() or coach_id = auth.uid());

-- Only the client writes, and only to a coach they are connected to. The
-- are_connected() check is what stops someone pushing their history at a
-- stranger's account.
create policy client_briefings_insert_client
    on public.client_briefings for insert
    to authenticated
    with check (client_id = auth.uid() and public.are_connected(coach_id));

create policy client_briefings_update_client
    on public.client_briefings for update
    to authenticated
    using (client_id = auth.uid())
    with check (client_id = auth.uid());

-- Revocation. Client-only on purpose: a coach cannot delete the evidence of
-- what they were told.
create policy client_briefings_delete_client
    on public.client_briefings for delete
    to authenticated
    using (client_id = auth.uid());
