# Design: Social — Friends, Coaches & Chat (server-backed)

> Living design doc. Drift's first (and only) server-backed feature. Read this
> before touching anything under `DriftCore/Sources/DriftCore/Sharing/`,
> `SharedUI/SharingView.swift`, `SharedUI/ChatView.swift`,
> `SharedUI/ShareTemplateSheet.swift`, or `supabase/`.
> Shipped: iOS build 365 / Android 60 (2026-07-28), then iterated.

## 1. What it is

An **opt-in social layer** on an otherwise 100%-local app. Three relationship
kinds, all built on the same primitives:

- **Friends** — symmetric. Both share workout templates and completed workouts;
  both see each other's activity feed; both can chat.
- **Coaches** — asymmetric. You "Add as Coach"; the coach monitors *your*
  workouts, can assign you templates, and chat. Your view of them is "your
  coach"; their view of you is "your client". (A coach's own workouts are NOT
  pushed to the client — only client→coach visibility, plus chat both ways.)
- **Chat** — 1:1 direct messages between any two connected users.

Everything is username-only (no email/PII shared) and strictly opt-in: nothing
touches the network until the user claims a @username.

## 2. Backend — Supabase (project `ldyapxvnhlyqqfefqijj`, us-west-2)

Managed Postgres + Auth + Row-Level Security + Realtime. **RLS is the access
logic** — the client talks straight to PostgREST; there is no server code. The
publishable/anon key + base URL are hardcoded in `AppConfig` (public-safe; RLS
gates everything). Schema + policies: `supabase/migrations/0001_sharing_core.sql`.

**Auth = anonymous sign-in** (`POST /auth/v1/signup` with `{}`). No email, no
password — the app mints a throwaway account when the user claims a username.
Requires "Allow anonymous sign-ins" ON (Auth → Sign In / Providers). An earlier
email-OTP flow was removed: Supabase's confirm-email link builds from the
default Site URL `localhost:3000`, a dead end on device.

**Tables** (all RLS-enforced; `are_connected(other)` SECURITY DEFINER helper
gates writes to accepted edges):
- `profiles(id=auth.uid, username unique, display_name, avatar_url)` — the
  public directory. Authenticated users can read (search); only the owner can
  insert/update/**delete** (delete frees the username on sign-out).
- `friendships(requester_id, addressee_id, status[pending|accepted|blocked],
  role[friend|trainer])` — one directed edge. **Coach convention: a trainer
  edge has requester=client, addressee=coach.**
- `shared_templates(owner_id, recipient_id, name, exercises_json, note, status)`
  — a template handed to a friend/client; `exercises_json` is Drift's
  `[TemplateExercise]` verbatim, so accept = decode → `WorkoutService.saveTemplate`.
- `live_workouts(client_id, trainer_id, template_name, status[live|completed|
  abandoned], started_at, ended_at)` + `live_workout_sets(...)` — a session made
  visible to one recipient. Same rows serve live-watch (status=live) and the
  completed report. This is the "workouts show up to friends" path.
- `messages(sender_id, recipient_id, body, created_at)` — chat; RLS: only the
  two parties read, send requires `are_connected`.

Realtime publication includes friendships / shared_templates / live_workouts(+
sets) / messages (RLS still applies to subscriptions). **Not yet consumed** —
the client currently POLLS (see §4); Realtime is the planned upgrade.

## 3. Client architecture (all cross-platform)

- **`SyncClient`** (`Sharing/SyncClient.swift`) — thin HTTPS transport over the
  shared `HTTPDataSession` seam (reused from `RemoteLLMBackend`, so one path for
  iOS + Android). PostgREST get/insert/update/delete + GoTrue auth POST.
  Categorized `SharingError` (network / http / conflict / forbidden / decoding /
  notSignedIn / notConfigured). `makeURL` percent-encodes as a fallback so a
  PostgREST query with `()*,` never crashes/force-unwraps.
- **`SharingService`** (`Sharing/SharingService.swift`, `@MainActor`) — the
  domain API + session lifecycle. `signInAnonymously`, `startSharing(username:)`,
  `claimUsername`, `searchUsers`, `sendRequest(to:role:)`, `addCoach`,
  `connections()` (classifies edges → friend/coach/client), request accept/
  decline, template share/assign/accept, `shareCompletedWorkout`, live-session
  APIs, `sendMessage`/`fetchMessages`, and `signOut` (deletes profile → frees
  username). **Session recovery**: `validToken()` clears a session whose refresh
  is auth-rejected; `validateSession()` also confirms the profile still exists
  (catches a wiped/deleted account) — the UI calls it on load and drops to the
  username picker instead of looping on a credential error.
- **Durable state** — SQLite (migration **v47** `sync_session` + `sync_map`),
  NOT UserDefaults (#1108). iOS shadows the access token into Keychain via
  `SecureTokenStore`/`DriftPlatform.secureStore`; Android uses the SQLite floor.
- **UI** (single-source SharedUI): `SharingView` (the hub — claim username,
  search + Add friend/Coach, requests, Coaches/Clients/Friends sections,
  activity feed, incoming templates), `ChatView` (bubbles + send + 3s poll),
  `ShareTemplateSheet` (friend picker for a template). Entry points: iOS
  `MoreTabView` + Android `MoreTab` "Friends" row; `TemplatePreviewSheet` and
  the finish-workout completion sheet ("Send to a friend" / "Share with all").

## 4. Known constraints & deliberate choices

- **Polling, not Realtime (yet).** Chat polls every 3s while open; the activity
  feed / requests refresh on view load. Realtime tables are published; wiring a
  websocket consumer is a fast-follow (Android needs a Kotlin OkHttp facade —
  Skip Fuse has no async socket stream).
- **Device-bound identity.** Anonymous accounts have no cross-device recovery.
  Phase-2: optional "link email/passkey later" to make an account portable.
- **Privacy tenet.** Off by default; only @username + display name + explicitly
  shared workouts leave the device. Adjudication in `Docs/decisions.md`
  (2026-07-28 entry): a cloud touchpoint is tenet-compatible only if opt-in +
  off-by-default + minimal + RLS-enforced + surfaced.

## 5. Skip / Android gotchas (hard-won — do not regress)

- SwiftUI `Text + Text` concatenation is **unavailable** on Skip Fuse (iOS
  only) — use one interpolated `Text`.
- A **direct cross-actor `await`** in a Button/onChange closure fails to compile
  on Skip ("async call in a function that does not support concurrency") — wrap
  as `Task { @MainActor in ... }`, or call a plain View method.
- `person.2`/`group`/`people` glyphs are **unmapped** in skip-ui (ship the ⚠️
  triangle) — `sym()` maps them to `person.crop.circle.fill`.
- `SharedUICopy` is a stale `cp` — run `scripts/android-sync-core-resources.sh`
  before `skip app launch`, or edits don't reach the Android build.
- **Tab switch vs pushed NavigationStack**: tapping the pill tab bar while on a
  pushed sub-screen did nothing (the pushed Compose NavHost stayed composed) —
  `ContentView.tabContent` now keys `.id(selectedTab)` so the outgoing tab + its
  nav stack tear down on switch.
- Chat input must clear the app's floating tab bar (global overlay on pushed
  screens) — `ChatView` adds bottom padding.

## 6. Testing

- **Tier-0** (`DriftCoreTests/SharingServiceTests` + `SharingFoundationTests`):
  request-building, session store, ID map, DTO wire mapping, token refresh,
  credential-recovery, share-completed sequence. `cd DriftCore && swift test`.
- **Live real-API scripts** (session scratchpad, re-run any time with `psql`
  from the pooler — see [[project-sharing-backend]]): anon signup → claim →
  friend/coach → share workout → chat, plus negative RLS (stranger can't read/
  send). All pass.
- **Two-simulator** (iOS ⟷ Android): claim usernames, live cross-device search,
  request→accept, chat, activity feed. Verified 2026-07-28.

## 7. Roadmap / next

- Realtime consumer (live-watch a client's sets landing; instant chat).
- Auto-recovery polish, unread badges on chat, push notifications.
- Per-friend detail levels (weight/sleep sharing with RLS per level).
- Coach dashboard (client roster, per-client history + assign flow).
- Leaderboards / group classes / formal coach role (later).
- Optional account portability (link email/passkey).

---

*To approve: add `approved` label to the PR. To request changes: comment on the PR.*
