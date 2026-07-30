-- 0010 — server-side read state for chat.
--
-- Additive: one table + one view. No existing row is read, moved or rewritten;
-- re-runnable.
--
-- THE BUG THIS CLOSES. Read state lived only on the device
-- (`SeenMarks` → key-value store), so an unread count could only be computed
-- from messages the client had already pulled — and `recentInbox` pulls the
-- newest 100 across ALL correspondents. Past roughly thirty active
-- conversations, someone whose newest message fell outside that window reported
-- ZERO unread, and the UI told you you were up to date while you had unanswered
-- messages. A wrong number that looks confident, which is the worst kind.
--
-- A WATERMARK, NOT A ROW PER MESSAGE. `read_through` is a timestamp per
-- conversation: one row per (reader, peer), bounded by your connection count
-- (≤150), not by how much you've said. Per-message read receipts would add a
-- row for every message every participant opens — the fastest-growing table in
-- the product, to answer a question a single timestamp answers. It also means
-- marking a thread read is ONE upsert regardless of how far behind you were.
--
-- No per-message "seen by" ticks, deliberately: that's a different feature with
-- a different privacy question, and this table can't accidentally grow into it.

create table if not exists public.message_reads (
    reader_id    uuid not null references public.profiles(id) on delete cascade,
    peer_id      uuid not null references public.profiles(id) on delete cascade,
    -- Everything this reader received from this peer at or before this instant
    -- is read. Monotonic in practice; the client never moves it backwards.
    read_through timestamptz not null,
    updated_at   timestamptz not null default now(),
    primary key (reader_id, peer_id)
);

alter table public.message_reads enable row level security;

-- Strictly your own. Your read state is not your correspondent's business —
-- exposing it would be a read-receipt feature nobody opted into.
drop policy if exists message_reads_own on public.message_reads;
create policy message_reads_own
    on public.message_reads for select
    to authenticated using (reader_id = auth.uid());

drop policy if exists message_reads_insert_own on public.message_reads;
create policy message_reads_insert_own
    on public.message_reads for insert
    to authenticated with check (reader_id = auth.uid());

drop policy if exists message_reads_update_own on public.message_reads;
create policy message_reads_update_own
    on public.message_reads for update
    to authenticated using (reader_id = auth.uid()) with check (reader_id = auth.uid());

drop policy if exists message_reads_delete_own on public.message_reads;
create policy message_reads_delete_own
    on public.message_reads for delete
    to authenticated using (reader_id = auth.uid());

-- ---------------------------------------------------------------------------
-- unread_counts — exact per-correspondent unread, in ONE request.
--
-- Replaces "pull 100 messages and count them client-side". The client asks
-- `unread_counts?reader_id=eq.<me>` and gets a row per peer who has said
-- something newer than the watermark. No window, so no silent zeroes.
--
-- `security_invoker = true` (PG15+) so the view runs with the CALLER's rights
-- and the messages / message_reads policies still apply. Without it a view is
-- owned by the definer and would expose every conversation in the product.
--
-- `m.recipient_id = auth.uid()` is EQUALLY load-bearing, and RLS alone does not
-- give it to you. `messages_read_parties` lets you read rows where you are the
-- SENDER too — correctly, they're your messages — so without this predicate the
-- view also emitted rows keyed to the OTHER person's reader_id, computed from
-- messages you sent. Verified before the fix: as one user, 3 of 4 rows returned
-- belonged to other readers. That is a read-receipt side channel — you'd learn
-- whether a friend had read you — i.e. precisely the feature this migration says
-- it is not building. Found by querying the view under
-- `set local role authenticated`, not by reading it.
--
-- Cost is proportional to the CALLER's own received messages (index scan on
-- messages_recipient), not to the size of the table. It grows with how much
-- one person is sent, and stays flat as the user base grows.
-- ---------------------------------------------------------------------------
create or replace view public.unread_counts with (security_invoker = true) as
select
    m.recipient_id             as reader_id,
    m.sender_id                as peer_id,
    count(*)::int              as unread,
    max(m.created_at)          as latest_at
from public.messages m
left join public.message_reads r
       on r.reader_id = m.recipient_id
      and r.peer_id   = m.sender_id
where m.recipient_id = auth.uid()
  and (r.read_through is null or m.created_at > r.read_through)
group by m.recipient_id, m.sender_id;

comment on view public.unread_counts is
    'Exact unread count per correspondent for the calling user. security_invoker=true — do NOT remove, it is what keeps RLS applied.';
