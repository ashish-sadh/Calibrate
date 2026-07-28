# Design: Friends & Trainer Workout Sharing (server-backed)

> References: branch `feat/friends-sharing`. First server-backed feature in Drift.

## Problem

Drift is fully local — no account, no cloud, no way for two people to interact.
Users want to (1) share workout templates with friends, and (2) let a trainer
assign them workouts and watch/receive their sessions. This is impossible
without a server that mints stable cross-device identity and mediates access.

The hard tension: the product's **privacy tenet** (`Docs/tenets.md`) reads
"Everything on-device, no cloud, no accounts, no analytics." A sharing feature
is, by definition, a cloud account. This doc adjudicates that tension.

## Proposal

A **strictly opt-in** social layer on **Supabase** (managed Postgres + Auth +
Row-Level Security + Realtime). Nothing contacts the server until the user opens
**More → Friends**, signs in with an email code, and claims a public `@username`.

In scope (phase 1, both platforms):
- Pick a unique `@username`; search usernames; send/accept friend requests.
- Share a workout template to a friend; they accept it into their local library.
- A friend/trainer can **assign** a template the same way (accept-to-add).
- A client can send a **completed workout** to a trainer, who sees it in-app.
- **Live-watch** (trainer sees sets land in realtime) — iOS first; Android
  client-push works day one, Android trainer *live view* is a fast-follow
  (needs a Kotlin websocket facade; Skip Fuse has no async socket stream).

Explicitly out (later): weight/sleep sharing, per-friend detail levels,
leaderboards, group classes, a formal coach role.

## Tenet adjudication (account vs "no accounts")

The tenet stands for **local-first with no silent cloud**, not "cloud is
forbidden." Precedent already exists: BYOK photo logging and the Nebius Coach
both leave the device — the rule enforced is that any cloud touchpoint is
**explicit and user-initiated**. Sharing follows the same contract:

- **Off by default.** Zero network calls until the user signs in. The local app
  is unchanged for anyone who never opens Friends.
- **Minimum disclosure.** Only `@username`, optional display name, and the
  specific workouts you choose to share ever leave the device. Email is used
  only for sign-in/recovery and is never in a shared table (it lives in
  `auth.users`, unreadable by other users). No weight/food/health data crosses
  the boundary in phase 1.
- **Enforced server-side.** Row-Level Security means a row is visible only to
  the parties involved — the client can't over-share even by accident.
- **Surfaced.** The Friends screen states in-line exactly what leaves the
  device; the on-device promise copy becomes conditional when sharing is on.

Decision: sharing is compatible with the tenet **because** it is opt-in,
minimal, and explicit. Logged in `Docs/decisions.md`.

## Identity: username-only (anonymous account)

There is **no email and no password.** Claiming a @username silently creates a
Supabase **anonymous** account (`POST /auth/v1/signup`) — a real `auth.users`
row + JWT, so RLS's `auth.uid()` still enforces per-friend access, but the user
never sees an auth step. The account is device-bound (session persists in SQLite
+ Keychain). Trade-off: no cross-device recovery yet (a "link email later" is a
clean phase-2 add). Requires **"Allow anonymous sign-ins"** enabled on the
project (Authentication → Sign In / Providers).

The earlier email-code flow was removed: Supabase's confirmation email builds its
link from the project **Site URL** (default `localhost:3000`), so the link was a
dead end on a phone — email was the wrong mechanism for this feature.

## UX Flow

1. **More → Friends.** "Pick a username" card → type a @username → Claim
   (`^[a-z0-9_]{3,20}$`). The anonymous account is created on claim. Now findable.
3. **Add friends:** search a username → "Add" → request sent. The other person
   sees it under "Friend requests" → accept/decline.
4. **Share a template:** any template's preview → "Send to a friend" → pick a
   friend (+ optional note) → sent. Recipient sees it under "Shared with you" →
   "Add to my workouts" materializes a real local `WorkoutTemplate`.
5. **Trainer watch (iOS):** starting a workout offers "Let @trainer watch"; each
   finished set is pushed; the trainer opens the live session and sees sets
   land. On finish it becomes a completed report in the trainer's client list.

## Technical Approach

**Server** (`supabase/migrations/0001_sharing_core.sql`): `profiles`,
`friendships`, `shared_templates`, `live_workouts` + `live_workout_sets`. Every
table has RLS; a `are_connected()` SECURITY DEFINER helper gates shares/sessions
to accepted edges. Realtime publication on the trainer-visible tables.

**Client** (all in DriftCore, cross-platform):
- `SyncClient` — buffered HTTPS over the shared `HTTPDataSession` seam (reused
  from `RemoteLLMBackend`), so one code path serves iOS + Android. PostgREST
  CRUD + GoTrue auth; categorized `SharingError`.
- `SharingService` (`@MainActor`) — the user stories as typed calls; owns the
  durable session + token refresh.
- Durable state in **SQLite** (migration v47: `sync_session`, `sync_map`) — NOT
  UserDefaults (Android drops those, #1108). iOS additionally shadows the token
  into Keychain via the `SecureTokenStore` seam (`DriftPlatform.secureStore`);
  the SQLite row is the floor, Keychain the upgrade.
- Templates are self-contained (`exercises_json` = Drift's `[TemplateExercise]`
  verbatim), so accept = decode → `WorkoutService.saveTemplate`. `sync_map`
  bridges local `Int64` ↔ server `uuid`.

**UI** — `SharingView` + `ShareTemplateSheet` live in **SharedUI** (single
source; one file renders on both apps). Entry points in both MoreTabs.

Dual-model architecture is untouched — sharing is orthogonal to the AI pipeline.

## Edge Cases

- **Username taken** → `409` → `SharingError.conflict` → "That username is taken."
- **Expired token** → auto-refresh via the refresh token; hard-expired → prompt
  re-sign-in.
- **Offline / airplane mode** → categorized `.network` error, surfaced; no crash;
  local app fully functional.
- **Unknown exercise in a shared template** → resolved through the existing
  unknown-exercise path on accept (exercises are by name).
- **Sharing off** → no network calls at all (bootstrap short-circuits).

## Open Questions

- Trainer role directionality: phase 1 treats `role` as a label and lets any
  accepted pair share/assign/watch (`are_connected` is symmetric). A formal,
  asymmetric coach role is deferred (operator: "figure the role of coach later").
- Android trainer live-view websocket facade — scheduled fast-follow.

---

*To approve: add `approved` label to the PR. To request changes: comment on the PR.*
