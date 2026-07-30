-- 0019 — an optional one-line tagline on a profile.
--
-- Additive: one nullable column. Re-runnable. Nothing is read, moved, rewritten
-- or deleted, and an older client that never sets it is unaffected.
--
-- WHY. Search returns @handles, which tell you nothing about whether someone is
-- worth connecting to. The operator wants what Instagram's bio does: "enthusiastic
-- about pole, deadlift", "looking for a gym buddy" — enough for a stranger to
-- decide, visible in search results and on the profile page.
--
-- 80 characters on purpose. Long enough for a real sentence, short enough that a
-- search row stays one line and nobody writes a life story into a directory
-- entry. Capped server-side so the limit holds whatever the client does.
--
-- NOT covered by the `discoverable` switch: a tagline is only ever shown
-- alongside a profile someone already reached, and a hidden profile is still
-- reachable by invite link. Someone who doesn't want to be described simply
-- leaves it null, which is the default.
alter table public.profiles
    add column if not exists tagline text
    check (tagline is null or char_length(tagline) <= 80);

comment on column public.profiles.tagline is
    'Optional one-line bio, <=80 chars, shown in search results and on the public profile. Null by default — describing yourself is opt-in.';
