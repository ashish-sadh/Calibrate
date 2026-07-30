# Design: Discovery, silent workout broadcast, and a notification policy that respects the relationship

> References: Issue #1162
> Operator 2026-07-29: "how to make discovery easy for public profiles… enable
> notification for chat… instead of showing individual folks should send workout
> updates to everyone as silent workout update but for the coach it's more than
> friend activity it's more like workout history… coach getting notification is
> fine but friends shouldn't. They should only get notification when someone
> added them… fine if friends get notification on today screen about pending
> messages under friends. Phone app notification only coach should get."

Three related changes. The unifying idea: **a coach relationship and a
friendship are not the same contract**, and the app should stop treating them
identically — in what flows, and in what interrupts you.

## 1. Discovery

**Already works:** `searchUsers` matches BOTH `username` and `display_name`
(ilike, limit 25). So matching is not the gap.

**The real gap:** you must already know the handle. Nobody discovers anyone.

Proposed, in value order:

1. **Invite link** — `drift://add/<username>` (plus an https fallback for
   sharing outside the app). Tap → opens Drift with the request pre-filled.
   This is how people actually connect: they send a link, they don't search a
   directory.
2. **QR code** — the coach case. A trainer signs up a client standing in front
   of them; a QR on the coach's profile is the shortest path that exists.
3. **`profiles.discoverable`** (boolean, default true) — the "public profile"
   switch. True = findable by username/display-name search. False = link/QR
   only. Additive column, no backfill needed.

**Deliberately NOT building: friends-of-friends suggestions.** It requires
reading one user's social graph to serve another, which is exactly the
mechanism a privacy-first app shouldn't have. If it's ever wanted it needs its
own opt-in and its own decisions.md entry.

## 2. Silent workout broadcast (replacing per-recipient picking)

**Today:** finishing a workout opens a recipient picker; you tap people
individually (or "Share with all N"). Every share is an explicit act.

**Proposed:** a completed workout flows to your connections automatically,
with NO notification to friends. Friends see it as activity; a coach sees it as
**workout history** — an ongoing training log, not a feed item.

This is a genuine change to default data flow, so it splits by relationship:

- **Coaches: automatic.** This is already the contract — the original design
  states "you Add as Coach; the coach monitors *your* workouts." Auto-flow is
  what the relationship means.
- **Friends: one global switch** instead of a per-workout chore. The chore is
  the thing the operator wants gone; the *decision* should survive as a single
  setting rather than vanish. Default is an open question (below).

The recipient picker stays for **templates** (assigning a specific workout to a
specific person is inherently deliberate) and remains available for a one-off
"send this to just X".

**Coach-side framing.** `clientSessions()` already returns the coach's clients'
sessions. The change is presentational and semantic: rename the coach's view
from "FRIEND ACTIVITY" to **workout history** per client, grouped by date,
persistent — the coach's page becomes a training record they scroll, not a
feed that scrolls away.

## 3. Notification policy

The operator's matrix, captured exactly:

| Event | Friend | Coach |
|---|---|---|
| Chat message received | Today-screen signal only | **Phone push** + Today signal |
| Workout completed / shared | **Silent** (history/feed only) | **Phone push** + history |
| Someone added you / requested you | **Phone push** | **Phone push** |

The principle: **a friend's training is not an interruption; a client's is a
coach's job.** Friends get exactly one push — the one that needs an answer
(a connection request). Everything else for friends lives on the Today screen.

### What this needs, honestly

Drift has **no push infrastructure whatsoever**: no APNs key, no FCM project,
no device tokens, no server-side trigger. Nothing pushes today, because
privacy-first has meant no server watching a user's activity. Delivering the
matrix above requires, in order:

1. **APNs** auth key (the App Store Connect key is not an APNs key) and an
   **FCM** project + `google-services.json`; on Android the FCM SDK is
   coroutine-based, so it likely needs a blocking Kotlin facade like
   `HttpFacade` (#1136).
2. **`device_tokens`** table (user_id, token, platform, updated_at) with RLS —
   own-row write only.
3. Permission prompts + token registration on both platforms. On Android,
   remember the permission-ask relaunch trap (#1096).
4. **A server-side trigger**: Supabase Edge Function invoked on insert into
   `messages` / `live_workouts` / `friendships`, which applies the policy
   matrix — the relationship kind decides whether to push, so the policy has to
   live server-side where the `friendships.role` is.
5. A decisions.md entry, because this is the first time Drift's backend reaches
   out to a device unprompted. That is a real change in posture and should be
   argued, not slipped in.

**Deliverable without any of that (ship first):**
- Today-screen signals for friends AND coaches: unread message count and
  pending requests surfaced under the Friends card (the card already shows
  pending requests; unread chat count is the addition).
- The silent-broadcast model and the coach's workout-history framing.
- Discovery: invite link, QR, `discoverable` flag.

Slicing that way means the visible behaviour lands now and push arrives as one
focused infrastructure piece rather than being half-wired into three features.

## Open decisions

1. **Default for auto-sharing completed workouts to FRIENDS** — on, off, or
   ask once at the first completed workout after upgrade.
2. **Build push now** (multi-day: credentials, tokens, edge function, both
   platforms) **or ship the in-app signals first** and treat push as its own
   tracked piece.

## Risks

- Auto-broadcast is a widening of default data flow; it must be disclosed
  where it happens (the completion sheet should say where the workout went),
  not only in a settings screen.
- A push pipeline that mis-applies the matrix would notify friends about
  workouts — the exact thing the operator ruled out. The policy belongs in one
  server-side place with tests, not duplicated per client.
