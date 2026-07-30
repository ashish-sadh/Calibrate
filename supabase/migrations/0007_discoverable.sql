-- ---------------------------------------------------------------------------
-- 0007 — the "public profile" switch (#1162 discovery).
--
-- Search already matches username AND display_name, so finding someone was
-- never the hard part — you had to already KNOW their handle. The fix is invite
-- links; this column is the other half: whether you may be found by search at
-- all, or only by a link you chose to send.
--
-- Default TRUE, deliberately: a @username is something you picked to be found
-- by, and every account created before this column existed was already
-- searchable — flipping them to hidden would silently break friend-finding for
-- people who are mid-conversation about connecting. Opting OUT is the explicit
-- act, and it's one toggle away.
--
-- Additive and re-runnable: one nullable-with-default column, no backfill, no
-- rewrite of existing rows.
-- ---------------------------------------------------------------------------
alter table public.profiles
    add column if not exists discoverable boolean not null default true;

-- The directory search filters on this, so it's part of the hot path.
create index if not exists profiles_discoverable_idx
    on public.profiles (discoverable)
    where discoverable = true;

-- ---------------------------------------------------------------------------
-- RLS note: `profiles` is readable by any authenticated user by design — that
-- IS the username directory, and it holds only handle + display name + avatar
-- (never health data). `discoverable` is therefore enforced in the QUERY rather
-- than by a policy: a hidden profile must still be readable by id, or a person
-- who connects to you via a link could never see your name. Hiding means
-- "don't surface me in search", not "become invisible to people I've connected
-- with".
-- ---------------------------------------------------------------------------
