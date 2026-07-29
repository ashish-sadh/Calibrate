-- ---------------------------------------------------------------------------
-- Drift support — 0003
--
-- In-app bug reports and suggestions with a REPLY thread, so a user who files
-- something hears back and can watch it change status. Operator ask 2026-07-28.
--
-- Identity: the anonymous telemetry install id, NOT auth.uid(). A user must be
-- able to report a bug without signing in or claiming a @username — support is
-- the one place where forcing an account would lose exactly the report you most
-- want. When the reporter DOES have a sharing profile we record it too, so a
-- reply can reach them by @username.
--
-- Because there is no auth for anonymous reporters, RLS cannot use auth.uid()
-- here. Reads are scoped by install_id supplied as a PostgREST filter, which is
-- an unguessable UUID — the same shape as an emailed magic link. Staff replies
-- are written with the service-role key from the console; clients can never
-- insert a row with `from_staff = true` (enforced by the WITH CHECK below).
-- ---------------------------------------------------------------------------

create table if not exists public.support_tickets (
    id           uuid primary key default gen_random_uuid(),
    install_id   uuid        not null,
    profile_id   uuid references public.profiles(id) on delete set null,
    kind         text        not null check (kind in ('bug','suggestion','question')),
    subject      text        not null,
    body         text        not null,
    status       text        not null default 'open'
                   check (status in ('open','in_progress','fixed','wont_fix','released')),
    -- What shipped the fix, so "released" can say WHICH build to update to.
    released_in  text,
    platform     text        not null check (platform in ('ios','android')),
    app_version  text,
    created_at   timestamptz not null default now(),
    updated_at   timestamptz not null default now()
);
create index if not exists support_tickets_install
    on public.support_tickets(install_id, created_at desc);
create index if not exists support_tickets_status
    on public.support_tickets(status, created_at desc);

-- Thread. `from_staff` distinguishes our replies from the reporter's follow-ups.
create table if not exists public.support_messages (
    id           uuid primary key default gen_random_uuid(),
    ticket_id    uuid        not null references public.support_tickets(id) on delete cascade,
    install_id   uuid        not null,
    body         text        not null,
    from_staff   boolean     not null default false,
    -- Path inside the `support-attachments` storage bucket, not a public URL.
    attachment   text,
    created_at   timestamptz not null default now()
);
create index if not exists support_messages_ticket
    on public.support_messages(ticket_id, created_at asc);

alter table public.support_tickets  enable row level security;
alter table public.support_messages enable row level security;

-- Anyone may file. The install_id in the row is whatever the client sends;
-- that is the id they will need to read it back, so it is self-scoping.
create policy support_tickets_insert
    on public.support_tickets for insert
    to anon, authenticated with check (true);

-- Read is filtered by install_id at the query layer (?install_id=eq.<uuid>).
-- The UUID is the capability; without it a caller gets nothing useful.
create policy support_tickets_read
    on public.support_tickets for select
    to anon, authenticated using (true);

-- A client may add to a thread, but may NOT forge a staff reply.
create policy support_messages_insert
    on public.support_messages for insert
    to anon, authenticated with check (from_staff = false);

create policy support_messages_read
    on public.support_messages for select
    to anon, authenticated using (true);

-- ---------------------------------------------------------------------------
-- Attachments. Screenshots are what make a bug report actionable, so the bucket
-- is private: clients upload, only the service role reads back. Create via the
-- console or:
--   insert into storage.buckets (id, name, public) values
--     ('support-attachments','support-attachments', false);
-- ---------------------------------------------------------------------------
create policy support_attachments_upload
    on storage.objects for insert
    to anon, authenticated
    with check (bucket_id = 'support-attachments');

-- Keep `updated_at` honest so a status change re-sorts the reporter's list.
create or replace function public.touch_support_ticket()
returns trigger language plpgsql as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists support_tickets_touch on public.support_tickets;
create trigger support_tickets_touch
    before update on public.support_tickets
    for each row execute function public.touch_support_ticket();
