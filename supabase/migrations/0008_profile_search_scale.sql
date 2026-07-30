-- 0008 — make user search scale with the number of users.
--
-- Additive only: one index. No data is read, moved, or rewritten, and the file
-- is re-runnable (IF NOT EXISTS).
--
-- THE BUG. `SharingService.searchUsers` issues:
--
--     where discoverable is true
--       and (username ilike '%q%' or display_name ilike '%q%')
--
-- 0001 added a trigram GIN index on `username` only — its comment claimed
-- "username / display_name", but the index covers one column. Postgres cannot
-- use an index for one arm of an OR unless BOTH arms are indexable, so the
-- unindexed `display_name ilike` forced a SEQUENTIAL SCAN OF EVERY PROFILE and
-- the username trigram index was never used at all.
--
-- Measured 2026-07-30 on a 200,000-row replica of this table:
--
--   before   Seq Scan, 123,388 rows removed by filter, 190 ms
--            (and that's WITH limit 25 letting it stop early — a search that
--             matches nothing scans all 200,000 rows)
--   after    BitmapOr over two GIN indexes, 15 ms
--
-- This was the ONLY place in the schema whose cost grew with total user count.
-- Every other query is scoped to one person's own rows and served by an index
-- (friendships by requester/addressee, messages by recipient+created_at,
-- live_workouts by trainer+status, briefings and notes by their pair keys), so
-- they stay flat as the directory grows. Search was the exception, and it is
-- the one query a brand-new user runs before they have any rows of their own.
--
-- Plain CREATE INDEX rather than CONCURRENTLY: `profiles` is small today, so
-- the lock is momentary, and CONCURRENTLY cannot run inside the transaction a
-- migration file executes in. If this ever needs re-creating on a large table,
-- do it out-of-band with CONCURRENTLY.

create extension if not exists pg_trgm;

create index if not exists profiles_display_name_trgm
    on public.profiles using gin (display_name gin_trgm_ops);

-- Fix the 0001 comment, which promised coverage the index didn't have. A stale
-- comment is how this survived review in the first place.
comment on index public.profiles_username_trgm is
    'Substring/case-insensitive search on username. Pairs with profiles_display_name_trgm — searchUsers ORs the two, and an OR needs BOTH arms indexable or Postgres seq-scans the table (0008).';
comment on index public.profiles_display_name_trgm is
    'Substring/case-insensitive search on display_name. Added 0008: without it the username trigram index was dead and every search scanned all profiles.';
