-- ---------------------------------------------------------------------------
-- Drift telemetry — 0002
--
-- WRITE-ONLY from the client. Unlike the sharing tables (0001), telemetry rows
-- are never read back by the app: the `anon` role gets INSERT and nothing else,
-- so a leaked publishable key cannot enumerate anyone's usage or AI content.
-- Analysis happens with the service-role key from psql / the Supabase console.
--
-- Identity is an anonymous INSTALL id (a UUID minted on first launch and kept
-- in the local SQLite KV store). It is deliberately NOT auth.uid() and NOT the
-- sharing profile id: telemetry must work for users who never sign in, and must
-- not be joinable to a @username.
--
-- Operator decision 2026-07-28 (see Docs/decisions.md): usage counts are ON by
-- default with an opt-out; AI content capture is a SEPARATE opt-in, off by
-- default, because queries/responses carry health data.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- telemetry_events — one row per user-visible action ("described a meal",
-- "opened weight tab"). No free text: `name` is a closed vocabulary from the
-- client and `props` holds small enum-ish values only.
-- ---------------------------------------------------------------------------
create table if not exists public.telemetry_events (
    id           uuid primary key default gen_random_uuid(),
    install_id   uuid        not null,
    name         text        not null,
    props        jsonb       not null default '{}'::jsonb,
    platform     text        not null check (platform in ('ios','android')),
    app_version  text,
    occurred_at  timestamptz not null,          -- client clock (may skew)
    received_at  timestamptz not null default now()  -- server clock (authoritative)
);
create index if not exists telemetry_events_name_time
    on public.telemetry_events(name, received_at desc);
create index if not exists telemetry_events_install
    on public.telemetry_events(install_id, received_at desc);

-- ---------------------------------------------------------------------------
-- ai_turns — one row per AI turn, INCLUDING the raw query and response.
-- Only written when the separate AI-capture opt-in is on. `surface` says which
-- entry point produced it (coach_chat / describe_meal / exercise_text / …) so
-- routing failures can be sliced per surface.
-- ---------------------------------------------------------------------------
create table if not exists public.ai_turns (
    id           uuid primary key default gen_random_uuid(),
    install_id   uuid        not null,
    surface      text        not null,
    query        text,
    response     text,
    intent       text,
    tool         text,
    model        text,
    outcome      text,                            -- success / fallback / error
    latency_ms   integer,
    platform     text        not null check (platform in ('ios','android')),
    app_version  text,
    occurred_at  timestamptz not null,
    received_at  timestamptz not null default now()
);
create index if not exists ai_turns_surface_time
    on public.ai_turns(surface, received_at desc);
create index if not exists ai_turns_outcome
    on public.ai_turns(outcome, received_at desc);

alter table public.telemetry_events enable row level security;
alter table public.ai_turns          enable row level security;

-- INSERT-only for the publishable key. No select/update/delete policy exists,
-- so PostgREST returns 401/403 for every read attempt — telemetry is a
-- one-way street from the device.
create policy telemetry_events_insert_anon
    on public.telemetry_events for insert
    to anon, authenticated with check (true);

create policy ai_turns_insert_anon
    on public.ai_turns for insert
    to anon, authenticated with check (true);

-- ---------------------------------------------------------------------------
-- Retention. AI turns carry health content, so they expire; plain counts are
-- cheap and kept longer. Run from the scheduler (pg_cron) or manually:
--   select public.prune_telemetry();
-- ---------------------------------------------------------------------------
create or replace function public.prune_telemetry()
returns void language sql security definer set search_path = public as $$
    delete from public.ai_turns          where received_at < now() - interval '90 days';
    delete from public.telemetry_events  where received_at < now() - interval '365 days';
$$;
