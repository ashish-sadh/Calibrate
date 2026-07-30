-- 0016 — close a privacy leak in `public_activity`, and let a client actually
-- un-publish a board.
--
-- Additive / replace-in-place on two functions. Re-runnable. No row is read,
-- moved, rewritten or deleted.
--
-- ===========================================================================
-- 1. THE LEAK (found by adversarial review, 2026-07-30 — not by me)
-- ===========================================================================
-- `public_activity` is `security definer`, so RLS does not apply to it. When it
-- was written in 0012 that was fine: the only audience rule then was the read
-- policy it deliberately bypassed, and it had its own gate (the owner must have
-- opted into a global board).
--
-- Then 0014 added `live_workouts.audience` and rewrote the RLS POLICY. Then 0015
-- rewrote the policy again. Nobody updated this function. So it kept selecting
-- every row for that client regardless of audience:
--
--   * `audience = 'coaches'` — a workout the user explicitly withheld from
--     friends ("share with friends" OFF, "share with my coach" ON) was readable
--     by ANY authenticated stranger through the profile sheet. The realistic
--     case is exactly the sensitive one: "Rehab — Left Shoulder".
--   * legacy per-recipient rows — a session sent to ONE named person.
--   * in-progress rows (`status = 'live'`), i.e. what someone is doing RIGHT NOW.
--
-- The lesson worth writing down: a `security definer` function is a SECOND copy
-- of an authorisation rule. Changing the policy did not change it, and nothing
-- pointed the two at each other. Both now name the same three conditions.

create or replace function public.public_activity(other uuid, max_rows int default 10)
returns table (name text, workout_date date) language sql stable
security definer set search_path = public as $$
    select coalesce(w.template_name, 'Workout'), w.started_at::date
    from public.live_workouts w
    where w.client_id = other
      -- Client-owned rows only. A legacy per-recipient row was addressed to ONE
      -- person and is nobody else's business.
      and w.trainer_id is null
      -- Only what was shared broadly. 'coaches' means the user withheld it from
      -- friends, so a stranger is emphatically not entitled to it, and
      -- 'private' never leaves the device's own view.
      and w.audience = 'all'
      -- Finished sessions only — a stranger does not get to watch a live one.
      and w.status = 'completed'
      and w.started_at >= now() - interval '30 days'
      -- The owner must have opted into a global board. Unchanged, and still the
      -- gate that makes this function safe to expose at all.
      and exists (
          select 1 from public.leaderboard_entries e
          where e.user_id = other and e.visibility = 'global'
      )
    order by w.started_at desc
    limit least(greatest(max_rows, 1), 25)
$$;

revoke all on function public.public_activity(uuid, int) from public;
grant execute on function public.public_activity(uuid, int) to authenticated;

comment on function public.public_activity(uuid, int) is
    'Name + date of a person''s COMPLETED, client-owned, audience=all sessions in the last 30 days, and only if they opted into a global board. security definer, so these predicates duplicate the live_workouts policy ON PURPOSE — 0014/0015 changed the policy and this function was missed, which leaked coaches-only workouts to strangers (0016). Change both together.';

-- ===========================================================================
-- 2. UN-PUBLISHING A BOARD HAS TO REACH EVERY PERIOD
-- ===========================================================================
-- The client only ever restamps `visibility` on rows it is publishing RIGHT NOW,
-- i.e. the current week/month. But the read policy and the `public_activity`
-- gate are period-UNBOUNDED, so July's row stayed globally readable forever
-- after someone flipped a board back to friends-only in August — and its mere
-- existence kept their profile open to strangers.
--
-- A client-side loop over unknown historical periods can't fix that (it doesn't
-- know which periods exist). One statement, server-side, does.
create or replace function public.unpublish_board(board text)
returns int language plpgsql security definer set search_path = public as $$
declare
    changed int;
begin
    update public.leaderboard_entries
       set visibility = 'friends', updated_at = now()
     where user_id = auth.uid()
       and board_key = board
       and visibility = 'global';
    get diagnostics changed = row_count;
    return changed;
end $$;

revoke all on function public.unpublish_board(text) from public;
grant execute on function public.unpublish_board(text) to authenticated;

comment on function public.unpublish_board(text) is
    'Sets visibility=friends on ALL of the caller''s rows for one board, every period. Scoped to auth.uid() — nobody can un-publish anyone else. Turning a board private has to reach history, or the old rows stay readable and keep the profile-discovery gate open (0016).';
