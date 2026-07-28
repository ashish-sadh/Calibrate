-- Drift Friends & Trainer Sharing — core schema + Row-Level Security.
-- Phase 1: @username directory, friend/trainer edges, template sharing/assign,
-- trainer-visible live + completed workouts. Everything is opt-in; a row only
-- exists because a user explicitly shared it.
--
-- Apply to a fresh Supabase project (SQL editor, or `supabase db push`).
-- Auth: email OTP (Supabase Auth, enabled by default). auth.uid() = the caller.

-- Trigram search on usernames needs pg_trgm; create it before any index uses it.
create extension if not exists pg_trgm;

-- ---------------------------------------------------------------------------
-- profiles — the public @username directory. One row per auth user.
-- ONLY username/display_name/avatar are ever exposed to other users. No email
-- or PII lives here (email stays in auth.users, never selectable by others).
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
    id           uuid primary key references auth.users(id) on delete cascade,
    username     text not null unique
                   check (username ~ '^[a-z0-9_]{3,20}$'),
    display_name text check (char_length(display_name) <= 40),
    avatar_url   text,
    created_at   timestamptz not null default now(),
    updated_at   timestamptz not null default now()
);
-- Case-insensitive prefix search on username / display_name.
create index if not exists profiles_username_trgm
    on public.profiles using gin (username gin_trgm_ops);

alter table public.profiles enable row level security;

-- Anyone authenticated may READ profiles (needed to search usernames + render
-- friend cards). Rows contain no PII, so this is safe.
create policy profiles_read_authenticated
    on public.profiles for select
    to authenticated using (true);

-- You may only insert/update YOUR OWN profile.
create policy profiles_insert_self
    on public.profiles for insert
    to authenticated with check (id = auth.uid());
create policy profiles_update_self
    on public.profiles for update
    to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- You may delete your own profile (sign out / switch username frees the handle;
-- cascades remove your friendships + shared rows).
create policy profiles_delete_self
    on public.profiles for delete
    to authenticated using (id = auth.uid());

-- ---------------------------------------------------------------------------
-- friendships — one row per directed edge. requester initiates; addressee
-- accepts/declines. role = how requester relates to addressee:
--   'friend'  → symmetric peer
--   'trainer' → requester is addressee's trainer (may assign workouts, watch)
-- (A trainer relationship is one edge with role='trainer'; the client is the
--  addressee who accepted.)
-- ---------------------------------------------------------------------------
create table if not exists public.friendships (
    id           uuid primary key default gen_random_uuid(),
    requester_id uuid not null references public.profiles(id) on delete cascade,
    addressee_id uuid not null references public.profiles(id) on delete cascade,
    status       text not null default 'pending'
                   check (status in ('pending','accepted','blocked')),
    role         text not null default 'friend'
                   check (role in ('friend','trainer')),
    created_at   timestamptz not null default now(),
    updated_at   timestamptz not null default now(),
    check (requester_id <> addressee_id),
    unique (requester_id, addressee_id)
);
create index if not exists friendships_addressee on public.friendships(addressee_id);
create index if not exists friendships_requester on public.friendships(requester_id);

alter table public.friendships enable row level security;

-- Only the two parties can see/act on their edge.
create policy friendships_read_parties
    on public.friendships for select
    to authenticated using (auth.uid() in (requester_id, addressee_id));

-- You may create a request only AS the requester.
create policy friendships_insert_requester
    on public.friendships for insert
    to authenticated with check (requester_id = auth.uid());

-- Either party may update (accept/decline/block); the app restricts which
-- transitions each side makes.
create policy friendships_update_parties
    on public.friendships for update
    to authenticated using (auth.uid() in (requester_id, addressee_id));

create policy friendships_delete_parties
    on public.friendships for delete
    to authenticated using (auth.uid() in (requester_id, addressee_id));

-- Helper: is there an ACCEPTED edge (either direction) between me and X?
create or replace function public.are_connected(other uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from public.friendships f
        where f.status = 'accepted'
          and ( (f.requester_id = auth.uid() and f.addressee_id = other)
             or (f.addressee_id = auth.uid() and f.requester_id = other) )
    );
$$;

-- ---------------------------------------------------------------------------
-- shared_templates — a workout template handed to a friend/client.
-- exercises_json is Drift's [TemplateExercise] wire shape, verbatim.
-- ---------------------------------------------------------------------------
create table if not exists public.shared_templates (
    id             uuid primary key default gen_random_uuid(),
    owner_id       uuid not null references public.profiles(id) on delete cascade,
    recipient_id   uuid not null references public.profiles(id) on delete cascade,
    name           text not null,
    exercises_json text not null,           -- JSON-encoded [TemplateExercise]
    note           text,
    status         text not null default 'sent'
                     check (status in ('sent','accepted','declined')),
    created_at     timestamptz not null default now(),
    updated_at     timestamptz not null default now()
);
create index if not exists shared_templates_recipient on public.shared_templates(recipient_id);

alter table public.shared_templates enable row level security;

create policy shared_templates_read_parties
    on public.shared_templates for select
    to authenticated using (auth.uid() in (owner_id, recipient_id));

-- Only send AS the owner, and only to someone you're connected to.
create policy shared_templates_insert_owner
    on public.shared_templates for insert
    to authenticated
    with check (owner_id = auth.uid() and public.are_connected(recipient_id));

-- Recipient may update status (accept/decline); owner may retract.
create policy shared_templates_update_parties
    on public.shared_templates for update
    to authenticated using (auth.uid() in (owner_id, recipient_id));

-- ---------------------------------------------------------------------------
-- live_workouts + live_workout_sets — a client's session made visible to a
-- specific trainer. Same rows serve the live-watch (Realtime subscription
-- while status='live') and the completed report (status='completed').
-- ---------------------------------------------------------------------------
create table if not exists public.live_workouts (
    id            uuid primary key default gen_random_uuid(),
    client_id     uuid not null references public.profiles(id) on delete cascade,
    trainer_id    uuid not null references public.profiles(id) on delete cascade,
    template_name text,
    notes         text,
    started_at    timestamptz not null default now(),
    ended_at      timestamptz,
    status        text not null default 'live'
                    check (status in ('live','completed','abandoned'))
);
create index if not exists live_workouts_trainer on public.live_workouts(trainer_id, status);

create table if not exists public.live_workout_sets (
    id               uuid primary key default gen_random_uuid(),
    live_workout_id  uuid not null references public.live_workouts(id) on delete cascade,
    exercise_name    text not null,
    exercise_order   int  not null default 0,
    set_order        int  not null,
    weight_lbs       double precision,
    reps             int,
    is_warmup        boolean not null default false,
    done             boolean not null default false,
    logged_at        timestamptz not null default now()
);
create index if not exists live_workout_sets_parent on public.live_workout_sets(live_workout_id);

alter table public.live_workouts enable row level security;
alter table public.live_workout_sets enable row level security;

-- Client + the specific trainer can read the session.
create policy live_workouts_read_parties
    on public.live_workouts for select
    to authenticated using (auth.uid() in (client_id, trainer_id));

-- Client creates/updates their own session, only for a trainer they have an
-- accepted edge with.
create policy live_workouts_insert_client
    on public.live_workouts for insert
    to authenticated
    with check (client_id = auth.uid() and public.are_connected(trainer_id));
create policy live_workouts_update_client
    on public.live_workouts for update
    to authenticated using (client_id = auth.uid());

-- Sets: readable by both parties (via parent), writable only by the client.
create policy live_sets_read_parties
    on public.live_workout_sets for select
    to authenticated using (
        exists (select 1 from public.live_workouts w
                where w.id = live_workout_id
                  and auth.uid() in (w.client_id, w.trainer_id)));
create policy live_sets_insert_client
    on public.live_workout_sets for insert
    to authenticated with check (
        exists (select 1 from public.live_workouts w
                where w.id = live_workout_id and w.client_id = auth.uid()));
create policy live_sets_update_client
    on public.live_workout_sets for update
    to authenticated using (
        exists (select 1 from public.live_workouts w
                where w.id = live_workout_id and w.client_id = auth.uid()));

-- ---------------------------------------------------------------------------
-- messages — direct chat between two connected users (friend, or coach⇄client).
-- ---------------------------------------------------------------------------
create table if not exists public.messages (
    id           uuid primary key default gen_random_uuid(),
    sender_id    uuid not null references public.profiles(id) on delete cascade,
    recipient_id uuid not null references public.profiles(id) on delete cascade,
    body         text not null check (char_length(body) between 1 and 2000),
    created_at   timestamptz not null default now()
);
create index if not exists messages_pair on public.messages(sender_id, recipient_id, created_at);
create index if not exists messages_recipient on public.messages(recipient_id, created_at);

alter table public.messages enable row level security;

create policy messages_read_parties on public.messages for select
    to authenticated using (auth.uid() in (sender_id, recipient_id));
-- Send only as yourself, only to someone you have an accepted edge with.
create policy messages_insert_sender on public.messages for insert
    to authenticated
    with check (sender_id = auth.uid() and public.are_connected(recipient_id));

-- Realtime: publish the trainer-visible tables so a trainer's live view gets
-- Postgres-change events (RLS still applies to the subscription).
alter publication supabase_realtime add table public.live_workouts;
alter publication supabase_realtime add table public.live_workout_sets;
alter publication supabase_realtime add table public.shared_templates;
alter publication supabase_realtime add table public.friendships;
alter publication supabase_realtime add table public.messages;
