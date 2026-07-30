#!/usr/bin/env bash
# Seed / tear down throwaway social accounts for driving the friends + coach +
# leaderboard flows on a simulator.
#
# Every row it creates is named with the QA_PREFIX below, and `teardown` removes
# exactly those and nothing else. That prefix is the whole safety story: no
# unscoped DELETE, no "delete where created_at > x", no guessing.
#
#   ./scripts/social-qa-seed.sh seed <my-username>   # link the sim account in
#   ./scripts/social-qa-seed.sh status
#   ./scripts/social-qa-seed.sh teardown
#
# Needs the pooler URI in $DRIFT_DB_URI (see the sharing-backend memory note for
# how to recover it). Never echoes it.
set -euo pipefail

QA_PREFIX="qa9_"
PSQL="${PSQL:-/opt/homebrew/opt/libpq/bin/psql}"
: "${DRIFT_DB_URI:?set DRIFT_DB_URI to the session-pooler connection string}"

# The four personas the flows need: someone who coaches you, someone you coach,
# and two peers to make a leaderboard a leaderboard (a board needs >= 2 people).
PERSONAS=(coach client coop rival)

sql() { "$PSQL" "$DRIFT_DB_URI" -v ON_ERROR_STOP=1 "$@"; }

seed() {
  local me="${1:?usage: seed <your-username>}"
  echo "seeding ${QA_PREFIX}* and linking them to @${me}"
  sql <<SQL
do \$\$
declare
    me uuid;
    uid uuid;
    persona text;
    week date := date_trunc('week', now())::date;
    mon date := date_trunc('month', now())::date;
begin
    select id into me from public.profiles where username = '${me}';
    if me is null then
        raise exception 'no profile @${me} — claim a username in the app first';
    end if;

    foreach persona in array array['coach','client','coop','rival'] loop
        uid := gen_random_uuid();
        insert into auth.users (id, instance_id, aud, role, email)
        values (uid, '00000000-0000-0000-0000-000000000000', 'authenticated',
                'authenticated', '${QA_PREFIX}'||persona||'@example.invalid');
        insert into public.profiles (id, username, display_name, discoverable)
        values (uid, '${QA_PREFIX}'||persona, initcap(persona)||' (QA)', true);

        -- Relationship. Trainer edge is requester=client, addressee=coach.
        if persona = 'coach' then
            insert into public.friendships (requester_id, addressee_id, status, role)
            values (me, uid, 'accepted', 'trainer');
        elsif persona = 'client' then
            insert into public.friendships (requester_id, addressee_id, status, role)
            values (uid, me, 'accepted', 'trainer');
        else
            insert into public.friendships (requester_id, addressee_id, status, role)
            values (uid, me, 'accepted', 'friend');
        end if;

        -- Boards. Steps GLOBAL so the podium/bracket has something in it; the
        -- deadlift stays friends-only so both visibility paths get exercised.
        insert into public.leaderboard_entries
            (user_id, board_key, period_start, value, unit, visibility)
        values
            (uid, 'steps',  week, 30000 + (random()*90000)::int, '',    'global'),
            (uid, 'workouts', week, 2 + (random()*5)::int,       '',    'friends'),
            (uid, 'lift:deadlift', mon, 200 + (random()*250)::int, 'lbs', 'friends');

        -- Activity: one recent session and one 90 days old, so the coach's
        -- "base work survives" rule and the friends' 30-day window are both
        -- visible on a real screen rather than only in a test.
        insert into public.live_workouts
            (client_id, trainer_id, template_name, started_at, status, audience)
        values
            (uid, null, 'QA Recent Session', now() - interval '2 days', 'completed', 'all'),
            (uid, null, 'QA Base Work',      now() - interval '90 days', 'completed', 'all');

        -- A message each way so the inbox, unread counts and the Today pill all
        -- have something real to render.
        insert into public.messages (sender_id, recipient_id, body)
        values (uid, me, 'QA hello from '||persona);
    end loop;
end \$\$;
SQL
  status
}

status() {
  sql -tAc "
    select 'profiles: '||count(*) from public.profiles where username like '${QA_PREFIX}%';
    select 'leaderboard_entries: '||count(*) from public.leaderboard_entries e
      join public.profiles p on p.id = e.user_id where p.username like '${QA_PREFIX}%';
    select 'live_workouts: '||count(*) from public.live_workouts w
      join public.profiles p on p.id = w.client_id where p.username like '${QA_PREFIX}%';
    select 'messages: '||count(*) from public.messages m
      join public.profiles p on p.id = m.sender_id where p.username like '${QA_PREFIX}%';
    select 'friendships: '||count(*) from public.friendships f
      join public.profiles p on p.id in (f.requester_id, f.addressee_id)
      where p.username like '${QA_PREFIX}%';"
}

teardown() {
  echo "removing ${QA_PREFIX}* — scoped to that prefix only"
  # Deleting auth.users cascades to profiles, and profiles cascade to
  # friendships / messages / live_workouts / leaderboard_entries. One scoped
  # statement rather than five, so there is no order to get wrong.
  sql -c "delete from auth.users where email like '${QA_PREFIX}%@example.invalid';"
  status
}

case "${1:-}" in
  seed)     shift; seed "$@" ;;
  status)   status ;;
  teardown) teardown ;;
  *) echo "usage: $0 {seed <your-username>|status|teardown}" >&2; exit 2 ;;
esac
