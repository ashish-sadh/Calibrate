-- 0018 — a session can be shared with friends and coach WITHOUT going on your
-- public profile.
--
-- Additive: one column with a default, one function replaced. Re-runnable. No
-- row is read, moved, rewritten or deleted.
--
-- THE REMAINING GAP. 0016 stopped strangers reading `audience='coaches'`,
-- in-progress and per-recipient sessions. But a session shared normally —
-- `audience='all'` — still appeared on the public profile that a global
-- leaderboard makes reachable. The operator: "make sure a stranger doesn't see a
-- rehab session. Only a friend. And give people option to keep their rehab
-- session private. It's fine to share with coach — coach anyway has consent."
--
-- So stranger-visibility is a SEPARATE axis from audience, not another value of
-- it. "Who among the people I know" and "does this go on a profile strangers can
-- open" are different questions, and squeezing them into one column is what
-- would force someone to hide a session from their friends to hide it from
-- strangers.
--
--   audience         who among people you know (friends / coach)
--   public_visible   whether it also appears to STRANGERS on your profile
--
-- Default TRUE, and that is defensible only because the profile itself is opted
-- into: `public_activity` already requires the owner to publish a global board,
-- which is off by default and a deliberate act. Someone who never joined a
-- global board has no public profile for this to matter on. The moment they do,
-- the completion sheet offers the switch.

alter table public.live_workouts
    add column if not exists public_visible boolean not null default true;

-- Same predicates as 0016 plus the new one. This function is a SECOND COPY of an
-- authorisation rule (it is `security definer`, so RLS does not apply) — which is
-- exactly how the 0014/0015 policy rewrites left it behind and leaked
-- coaches-only sessions. Anything that changes who may read a workout must
-- change here too.
create or replace function public.public_activity(other uuid, max_rows int default 10)
returns table (name text, workout_date date) language sql stable
security definer set search_path = public as $$
    select coalesce(w.template_name, 'Workout'), w.started_at::date
    from public.live_workouts w
    where w.client_id = other
      and w.trainer_id is null
      and w.audience = 'all'
      and w.status = 'completed'
      -- The per-session opt-out. A rehab block stays with friends and coach and
      -- off the public profile.
      and w.public_visible
      and w.started_at >= now() - interval '30 days'
      and exists (
          select 1 from public.leaderboard_entries e
          where e.user_id = other and e.visibility = 'global'
      )
    order by w.started_at desc
    limit least(greatest(max_rows, 1), 25)
$$;

revoke all on function public.public_activity(uuid, int) from public;
grant execute on function public.public_activity(uuid, int) to authenticated;

comment on column public.live_workouts.public_visible is
    'Whether this session may appear to STRANGERS via public_activity. Separate axis from `audience`, which governs friends vs coaches — otherwise hiding something from strangers would mean hiding it from your friends too (0018). Retroactively settable, so a session already logged can be taken off the profile.';
