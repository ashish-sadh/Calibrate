# Friends, coaches & leaderboards — how it works and how we got here

**Status: POINT-IN-TIME SNAPSHOT, 2026-07-30.** Deliberately not maintained.

> Read this for the *reasoning*, not the current state. Live state is
> `gh issue list`, the migrations directory, and the code. Everything below was
> true at builds **iOS 374 / Android 75**, and the parts that describe screens or
> constants will go stale first. The parts worth keeping are the DECISIONS and
> the MISTAKES — those stay useful after the code has moved on, which is the
> whole reason this file exists rather than being folded into an issue.

---

## 1. The model

One table of edges, three relationships.

`friendships(requester_id, addressee_id, status, role)` where `role` is
`friend` or `trainer`. A trainer edge is **requester = client, addressee =
coach**. That single convention is load-bearing and easy to get backwards —
`is_coach_of(client)` exists so nothing has to remember it twice.

Two people can hold **both** a friend edge and a trainer edge. That's what
"promote a friend to coach" produces, and it's why edge uniqueness had to widen
to `(requester, addressee, role)` in 0005 — a pending trainer edge must coexist
with an accepted friend edge.

**Coaching is a request, never an imposed role** (operator, 2026-07-29). You ask
someone to coach you; they accept. There is no path that makes someone your
coach without their agreement.

**Coaches are not a separate product.** They're profiles, in the same list, with
the same sheets. That's what makes "make this friend my coach" feel like a
relationship changing rather than a mode switch. The trigger to split them out
is *not* client count — it's when a coach needs something a friend list can't
express: programs assigned across many clients at once, billing, or a roster they
work *through* rather than look *at*.

## 2. Consent

Consent is **bits, and every widening earns its own one.** The rule that kept
this coherent: if a change makes data visible to a wider audience than before, it
does not inherit an existing switch.

| control | default | governs |
|---|---|---|
| `BriefingSharingLevel` (6 bits) | off | what one coach sees: history, sleep, nutrition, weight, body comp, strength |
| `shareWorkoutsWithFriends` / `WithCoaches` | **on** | auto-share at workout finish |
| `shareStatsWithFriends` | **off** | publishing to leaderboards at all |
| `globalBoardKeys` (a Set) | empty | which boards go public, per board |
| `showWorkoutsOnPublicProfile` | on | whether a session reaches strangers |
| `coach_history_grants` | absent | how far back a coach reads |
| `discoverable` | true | appearing in search |

**Why the workout switches default ON and the leaderboard OFF.** Sharing a
workout sends it to people you already chose, one at a time. A leaderboard shows
all your friends each other's numbers at once — wider than connecting to someone
implies, so it's opted into.

**Audience is a 4-state, not a 3-state.** `WorkoutAudience` is
`all | coaches | friends | private`, because the completion sheet has two
independent switches and four combinations. This started as three, collapsing
friends-only into `all`, which silently handed the coach a session the user had
explicitly withheld — see §5.

**Stranger-visibility is a separate axis from audience** (`public_visible`).
Bundling them would have forced someone to hide a rehab session from their
friends in order to hide it from strangers.

## 3. History, and what "forever" means

A client's training history is **the client's**, kept forever. Nothing prunes it.

Retention is a **read window**, never a delete:

- a **current coach** reads back to a floor the client grants,
- a **friend** reads a rolling 30 days,
- an **ex-coach** reads nothing.

The floor (`coach_history_grants`): no row means "from when they became your
coach"; a row with `history_from = NULL` means **forever** — the explicit
transfer; a date means from that day. Client-write only; RLS refuses a coach
granting themselves more.

**The insight that fixed this:** the server row is a *projection*. The
authoritative log lives on the device. That's what makes narrowing a read window
safe and deleting unnecessary — and it's why the earlier per-recipient design was
backwards, freezing the audience at save time so an ex-coach kept access forever
while the *next* coach could see nothing.

## 4. Leaderboards

**A board is DATA, not schema.** `leaderboard_entries(user_id, board_key,
period_start) → value`. `board_key` is a string: `steps`, `calories`,
`workouts`, `food_streak`, `lift:deadlift`. **Adding a board needs no
migration.**

**Boards are discovered, not declared.** A board renders when ≥2 people among
you+friends have a value on it. Your group deadlifts → a deadlift board exists.
It doesn't → no board. Nothing to configure.

**Noise control is about what earns a CARD, not what gets shared.** Everything is
published; while nobody else has joined, only the four boards everyone has
(streak, steps, calories, workouts) take a card. Real lift boards cap at 3 by
participation. This is the fix that took twelve cards down to four without
hiding anything.

**Windows are rolling, not calendar.** Trailing 7 days, not week-to-date — see
§5 for why. Reads span the current *and* previous period key, and cross-period
dedupe prefers the most **recent** row, not the largest.

**Food streak sorts first**, because it's the metric nearly everyone has. Steps
need a phone in your pocket; a lift board needs a friend training the same lift.
Yesterday keeps a streak alive — resetting at midnight punishes people for
sleeping.

**Global boards** are podium (top 3) + your bracket (~20 nearest), never an
absolute top-100. Not for performance reasons — a top-N is a 6 ms index read —
but because **steps are trivially fakeable**, so the top of an absolute board is
noise while nobody games their way into the middle.

## 5. The mistakes — the part worth keeping

Every one of these passed tests and code review.

**A view that could never load.** `.task` doesn't fire on a view resolving to
`EmptyView()` — no layout node. So `!loaded → EmptyView` was a self-sustaining
deadlock and the entire social row was **permanently absent from Today**. Found
by driving a simulator, invisible to every build and test.
→ *Placeholders need a real node. `Color.clear.frame(height: 0)`.*

**A latch that froze the UI.** `load()` opened with `guard !loaded else
{ return }`, so counts never refreshed for the whole app session. Marks cleared
correctly; the pill never re-read them. Presented as "dots don't clear", was
actually "nothing reloads".
→ *Guard against overlap (`!loading`), not against running twice.*

**A `security definer` function is a SECOND COPY of an authorisation rule.**
`public_activity` bypassed RLS by design. Then 0014 added `audience` and rewrote
the *policy*; 0015 rewrote it again. Nobody updated the *function* — so
coaches-only sessions (the realistic case: "Rehab — Left Shoulder"), sessions
sent to one named person, and sessions **in progress right now** were readable by
any authenticated stranger.
→ *Changing a policy does not change a definer function. Grep for both.*

**A test that defended a bug.** `from(friends: true, coaches: false)` returned
`.all`, so turning the coach switch off did nothing — and a Tier-0 test asserted
exactly that. It wasn't failing to catch the bug; it was protecting it.
→ *When a test encodes a behaviour, ask whether the behaviour is right.*

**And the first fix for it didn't work either.** `are_connected()` is role-blind,
so a coach satisfied the *friends* branch too. Caught only by querying as four
separate identities under `set local role authenticated` before believing it.
→ *Query a new policy or view as a real user. Reading the SQL is not enough.*

**Writes with no reader.** `publishCompletedWorkout` wrote `trainer_id IS NULL`;
every consumer queried `trainer_id = me`. Finishing a workout reached **nobody**
while the sheet said "Shared with 3 friends and your coach".
→ *A new write shape needs its readers changed in the same commit.*

**`row["k"] = value as Any?` REMOVES the key** rather than sending JSON null. With
`merge-duplicates` upserts, "clear this" silently does nothing. I wrote it,
reviewed a finding about it, then wrote it again in the same session.
→ *`NSNull()`. Fix it in code, not in a comment.*

**A cold start that could never start.** An opt-in board needing 2 participants
is empty for everyone until two people independently opt in — and because it's
empty, nobody keeps it on. It told a user who had just published eleven entries
that nothing was shared.
→ *Any threshold + opt-in combination needs a bootstrap path.*

**Calendar windows empty on the boundary.** Week-to-date meant everyone read ~0
at 00:01 Monday. And the read only covered the current period key, so a friend
who hadn't opened the app since vanished, dropping the board below 2 and deleting
it for everyone.
→ *Rolling windows, and read the previous period too.*

**An invite link to a domain we don't own.** `https://drift.app/add/<handle>`
returned a TLS error for every recipient. The code even carried a comment calling
it "a stable container for the handle" — self-deception next to a share sheet
whose entire contract is that the link is tapped.
→ *Reassuring comments are where bad decisions hide.*

**Two things I asserted as constraints and were wrong about:**
- *"There is no server-side code."* Postgres functions ARE server-side code and
  we already shipped five; `pg_cron` was available all along; Realtime was
  **already publishing `messages`** the whole time I was optimising a poll.
- *"A global leaderboard needs an aggregate we can't run."* A top-N is an
  ordered index read: 4,173 ms → 6 ms with one partial index.
→ *Check the platform's capabilities before reasoning from their absence.*

## 6. Scale

Cost grows with **connections per user**, not with total users. Measured, not
assumed:

| query | plan | time |
|---|---|---|
| user search, `display_name` unindexed | Seq Scan, 123k rows filtered | 190 ms |
| same, after 0008's trigram index | BitmapOr, 2 GIN indexes | **15 ms** |
| leaderboard, 50 friends, explicit id list | Index Scan on PK | **6.5 ms** |
| same, letting RLS filter (anti-pattern) | Seq Scan, 1.6M rows removed | 1,199 ms |
| global top-100, no index | bitmap + top-N heapsort | 4,173 ms |
| same, partial index on `visibility='global'` | Index Scan | **6 ms** |

**The rule that falls out:** always pass an explicit `user_id=in.(…)` list.
Letting RLS do the filtering is elegant and evaluates `are_connected()` once per
row in the table. Chunk at 50 IDs — `id=in.(…)` grows ~37 chars per UUID and a
414 blanks the entire social surface for your heaviest users first.

`SharingService.maxConnections = 150`, enforced both directions. A stated ceiling
beats silent degradation.

## 7. Still open

- The per-board "Make private" switch disappears if a board drops below 2
  participants, while publishing continues.
- `unreadCounts()` and `ageInDays` are built with no callers; the UI still counts
  from a 100-message window and apologises for it.
- `read_through` is written from the device clock.
- Realtime for chat — the server half already exists; Android needs an OkHttp
  WebSocket facade.
- Real push. A local notification cannot fire for a server event while the app is
  closed, so coach alerts are *eventually*, not promptly. The blocker is
  credentials, never the absence of a server.
- HealthKit background delivery — the only mechanism that makes auto-detected
  workouts reach a coach without the app being opened.
- A two-account simulator walkthrough of the full coach↔client journey. It found
  the two worst bugs above; it has never been run end to end.

## 8. Migrations

`0001` core (profiles, friendships, shared_templates, live_workouts, messages) ·
`0002` telemetry + `prune_telemetry()` · `0003` support · `0004` client_briefings
· `0005` edge uniqueness incl. role · `0006` coach_notes · `0007` discoverable ·
`0008` display_name trigram · `0009` weekly_stats *(superseded)* · `0010`
message_reads + unread_counts · `0011` leaderboard_entries *(drops 0009,
guarded)* · `0012` global visibility, mutual_friend_count, public_activity,
client-owned workouts · `0013` pg_cron schedule · `0014` workout audience ·
`0015` coach_history_grants · `0016` public_activity leak + unpublish_board ·
`0017` `friends` audience + `is_friend_of` · `0018` public_visible · `0019`
profile tagline.
