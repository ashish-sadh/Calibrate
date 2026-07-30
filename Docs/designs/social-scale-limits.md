# Social features at scale — what holds, what breaks, what we're limiting

**Status:** reference · **Written:** 2026-07-30 · **Trigger:** operator asked
"architecturally look now how this will scale for many users. Let's limit some
features if you think we can't scale."

The honest summary: the sharing backend scales fine on *number of users*. It
breaks on *connections per user*, and the breakages are correctness bugs, not
slowness — which is why they'd have shipped unnoticed.

## The shape of the system

Everything social is Supabase + PostgREST + RLS. There is no server-side
application code: the client composes REST queries and RLS decides what rows it
may see. That's the right call for privacy (no service can read what the policies
forbid) and it means **cost scales with clients, not with a fleet we run**. Adding
100× the users adds 100× the requests against Postgres, which is a
vertical-scaling problem with a long runway, and none of it requires us to
operate anything new.

What it also means: **any aggregate has to be computed client-side**, from rows
the client pulled. That's the root of every real limit below.

## What breaks, in order of how quietly it does so

### 1. Unread counts go wrong before they go slow — WORST

`recentInbox` pulls the newest 100 messages addressed to you. `Inbox.entries`
then groups them per correspondent and asks `SeenMarks` (a LOCAL key-value read)
how many are unread.

Read state is local by design — the server never learns what you've read. So a
per-peer unread count can only be derived from messages the client actually
fetched. With one coach and five friends, 100 messages covers everyone. With
thirty chatty correspondents it does not, and a peer whose newest message fell
outside the window **silently reports zero unread**. The UI then tells you you're
up to date when you have unanswered messages.

**Done (2026-07-30):** `Inbox.rollup(from:me:windowLimit:)` returns a `complete`
flag that goes false the moment the window comes back full, and the pill row
refuses to claim "up to date" while it's false — it says "tap to catch up"
instead. That converts a silent lie into a vague truth.

**Real fix, when it's needed:** server-side read state (a `read_at` column, or a
`message_reads` table). Then unread is a `count()` the server answers and the
window stops mattering. That's an additive migration and roughly a day's work —
worth doing before any user has 20+ active conversations, not after.

### 2. One URL that grows with your friend count — FIXED

`profiles(ids:)` built a single `id=in.(uuid,uuid,…)` filter. At ~37 characters
per UUID, 300 connections is an 11 KB request line, past the 8 KB default of most
proxies. The failure mode is an opaque 414 on the ONE request that resolves every
friend row — the entire social surface goes blank, and it hits the heaviest users
first while looking fine for everyone else.

**Done:** chunked at 50 IDs (~1.9 KB), de-duplicated, sequential rather than
parallel — someone with 300 connections shouldn't open six sockets on every
dashboard load. Tier-0 asserts the worst-case URL stays under 8 KB.

### 3. `clientSessions` has the same window problem

100 newest live-workout rows across ALL clients. A coach with 40 active clients
loses visibility of the quieter ones, and `clientsWaiting` under-counts. Same
class as (1), same real fix (per-client queries, or a server-side aggregate).
Currently bounded by the connection ceiling rather than solved.

### 4. Four to six requests on every Today load

The Today pill row fires `incomingRequests` + `connections` + `recentInbox` +
`clientSessions` + `incomingSharedTemplates` concurrently; opening the Friends hub
fires six more, largely the same ones. Nothing is cached between screens.

This is genuinely just slowness, not wrongness, and concurrency keeps the wall
time near one round trip. Worth a short-lived in-memory cache eventually. Not
urgent, and deliberately NOT done now — a stale social cache showing a
message-count that's wrong is worse than a slightly slower correct one.

## The limit we're setting

**`SharingService.maxConnections = 150`**, enforced on both sending and accepting
a request, with a message that names the number.

Chosen because it sits below the point where the windows in (1) and (3) stop
covering a normal person (~2 messages per connection inside a 100-message
window), and because Drift is built for friends plus a coaching roster — not a
follower graph. A stated ceiling with a clear error is strictly better than
silent degradation: the app either works or tells you why it won't.

If a real coach needs more than 150 clients, that's a signal to build server-side
read state and paginated rosters, **not** to raise the constant.

## Features we are NOT building, for scale reasons

- **A global/community leaderboard over per-user rows.** Ranking every user
  against every user needs a server-side aggregate; there's no server-side code.
  If this ships it must be ONE precomputed number (a median, a challenge total)
  and never a materialised global ranking.
- **A friends activity feed with fan-out on write.** Every social read today is
  fan-out-on-read against the reader's own edges, which RLS makes safe and
  simple. A feed table would need write fan-out per follower and is the first
  thing here that genuinely doesn't scale in Postgres-with-no-backend.

## What we checked and found fine

- **No N+1 per connection.** `ClientDetailView` fetches per-client data only when
  you open that client. The roster itself is two queries regardless of size.
- **RLS cost.** Policies are indexed-column predicates on `auth.uid()`; they
  don't degrade with total user count.
- **Storage.** Messages and briefings are small text rows. Nothing here grows
  per-user in a way that matters at this stage.

---

## 2026-07-30 addendum — boards are data, and the chat poll was the real cost

Two follow-ups after the first pass, both from the operator: "can we build
leaderboard for steps of friends, make sure it's scalable" and "even make sure
chat is scalable", then "highest deadlift in the last month… figure out how it
can be multiple of this".

### Leaderboards: one table, arbitrarily many boards

Migration 0011 `leaderboard_entries (user_id, board_key, period_start) → value`.
A board is a STRING, not a column: `steps`, `calories`, `workouts`,
`lift:deadlift`. Adding a board needs no migration, and a board only *renders*
when ≥2 people among you+friends have a value on it — so a group that deadlifts
gets a deadlift board and one that walks doesn't, with nothing to configure.

This replaced 0009's `weekly_stats`, which hardcoded four columns. The drop was
guarded on `count(*) = 0` and the guard was tested by simulating a non-empty
table (it raised and refused). Safe only because that table was created after
builds 371/72 shipped, so no released client could have written it.

Measured at **2.2M rows** (200k users × 11 boards, the ceiling the publish cap
allows):

| query | plan | time |
|---|---|---|
| 50 friends, both periods (shipped) | Index Scan on PK | **6.5 ms** |
| `period_start = X`, RLS filters (anti-pattern) | Seq Scan, 1.6M rows removed | **1,199 ms** |

184× apart, and only the second grows with total users — *before* counting the
`are_connected()` call RLS would make per row. The `user_id=in.(…)` list is not
redundant with RLS; it is the difference between the two rows of that table.

Two bounds keep it there: `LeaderboardPublisher.maxLiftBoards = 8` (someone with
300 exercises would otherwise publish 300 rows/month, and the fan-in would be
150 × 300), and `LeaderboardBoard.liftKey` collapsing case/punctuation so
"Bench Press" / "bench press" / "Bench-Press" are one board rather than three
near-empty ones.

### Chat: the DB was fine, the client was not

EXPLAIN'd at 200k messages / 2k users — every chat query is index-served and
scales with per-user data, flat in table size:

| query | plan | time |
|---|---|---|
| thread with one peer, newest 200 | BitmapOr on `messages_pair` | 1.7 ms |
| incremental poll (`created_at > cursor`) | Index Scan Backward on `messages_recipient` | 2.3 ms |
| `unread_counts` view, all peers | Bitmap Index Scan → GroupAggregate | 4.2 ms |

The actual cost was **the 3-second poll re-requesting the entire 200-message
thread and diffing it client-side** — 20 requests a minute per open chat, up to
200 rows each, essentially none of them new. Now incremental: it asks only for
messages newer than the newest it holds, so the steady state is an empty
response. Cursor is the server timestamp, not a local clock (a device a minute
fast would skip a minute of messages forever).

Migration 0010 adds server-side read state — a `read_through` WATERMARK per
(reader, peer), one row per conversation rather than a receipt per message —
plus an `unread_counts` view for exact per-peer counts in one request. That
closes the "silently reports zero unread" hole the first pass could only
paper over.

**A security bug the test caught, not the review.** The view is
`security_invoker = true`, which was necessary but not sufficient:
`messages_read_parties` also lets you read rows where you are the SENDER, so the
view emitted rows keyed to the OTHER person's `reader_id`, computed from messages
you sent. Verified under `set local role authenticated`: 3 of 4 rows returned
belonged to other readers — a read-receipt side channel telling you whether a
friend had read you, i.e. exactly the feature the migration header says it isn't
building. Fixed with `where m.recipient_id = auth.uid()`; re-verified 1 row, 0
leaking. **Query a new view as a real user before believing it.**

### Still open

`fetchMessages(with:before:)` exists for scrolling back past the newest 200, but
no UI calls it yet — the history is reachable, the gesture isn't built.
