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

### How it's delivered — LOCAL notifications, no new infrastructure

Operator correction 2026-07-29, and it was the right one: *"these are just app
alerts like timer etc, why need more infra?"* An earlier draft of this doc
claimed APNs/FCM were required. They are not, and the app already owns both
halves of the cheaper path:

- `Drift/Services/NotificationService.swift` — local notifications, already
  shipping (rest timers, reminders).
- `Drift/BackupScheduler.swift` — `BGTaskScheduler` already registered and used
  for the nightly iCloud backup.

The one real distinction: a rest timer's trigger is LOCAL and known in advance,
while "your client finished a workout" happens on someone else's phone. So the
device has to find out somehow. Two transports:

1. **Poll + local notification (chosen).** When the app gets to run —
   foreground, or a background refresh — it asks Supabase what's new since the
   last check and raises a LOCAL notification for anything matching the policy
   matrix. Zero credentials, zero server code, reuses what exists. iOS uses the
   same `BGTaskScheduler` pattern as the backup; Android uses a periodic
   WorkManager job (15-minute minimum, and more reliable than iOS here).
2. **Real push (APNs/FCM)** — instant and reliable, but needs an APNs key (the
   App Store Connect key is not one), an FCM project, a `device_tokens` table
   and a server-side trigger. Deferred.

**The honest trade-off is TIMELINESS, not capability:**

| | Poll + local | Real push |
|---|---|---|
| Android | ~15 min granularity, reliable | instant |
| iOS | discretionary — minutes to hours, and never if the user force-quit (`BackupScheduler` already documents iOS skipping its slot) | instant |

For a coach checking in on clients, "within 15 minutes" is fine. For chat it
will feel slower than WhatsApp, and that is the thing to watch in real use.
Crucially, the POLICY and the UI are identical either way — if latency turns
out to matter, APNs/FCM drops in later as a pure transport upgrade with no
redesign.

**Also independent of transport:** the Today-screen signals (unread messages,
pending requests) are instant whenever the app is open, and need none of this.

## Platform parity — the seams this needs (both iOS AND Android, always)

Standing rule (`feedback_android_full_parity`, CLAUDE.md): iOS is the source of
truth and nothing ships one-sided. Most of this design is free on Android
because it lives in SharedUI/DriftCore — the policy matrix, the Today-screen
signals, the unread counting, the broadcast model and the coach's
workout-history view are all shared code.

Three pieces are NOT, and each needs a seam rather than an `#if os(Android)`
hole. Audited 2026-07-29:

1. **Local notifications — no Android path exists.**
   `Drift/Services/NotificationService.swift` lives in the iOS app target and
   imports `UserNotifications`. `DriftPlatform` has seams for health, widget,
   nutrition, secure store, key-value and HTTP — but none for notifying.
   → Add `DriftPlatform.notifier: LocalNotifier?` (schedule / cancel /
   authorization), iOS wrapping `UNUserNotificationCenter`, Android wrapping
   `NotificationManager` + a channel, with the API 33+ `POST_NOTIFICATIONS`
   runtime permission. Mind #1096: a lazy permission ask relaunches
   MainActivity and looks like a crash.

2. **Background poll trigger differs per platform.**
   iOS already has `BGTaskScheduler` registered (`BackupScheduler`, nightly
   backup) — the pattern is proven, add a second task identifier. Android needs
   a periodic **WorkManager** job (15-minute floor). Both call the SAME shared
   poll routine in DriftCore; only the scheduling is platform code.

3. **QR generation — nothing exists on either platform, and SkipUI has no
   CoreImage.** Rather than `CIQRCodeGenerator` on iOS plus a ZXing Kotlin
   facade on Android (two implementations, two failure modes), write the QR
   encoder in **pure Swift in DriftCore** and render the modules as a grid of
   rects. One implementation, both platforms, no dependency, works offline, and
   the encoder is Tier-0 testable against known-good fixtures — which a
   platform QR library never is.

4. **Deep links** (`drift://add/<username>`) are configuration on both sides:
   iOS URL types + `onOpenURL`; Android an `intent-filter` in the manifest.
   Small, but genuinely two places.

Sequencing note: seam 1 is the gate for the whole notification matrix, so it
comes first and gets its own verification on a real Android device (the
emulator's notification behaviour is not evidence).

## Decided

1. **Friends auto-share default: ASK ONCE, then remember** (operator
   2026-07-29). The first completed workout after upgrade asks "share your
   workouts with friends automatically?" — one decision, then silent forever.
   It honours the privacy-first requirement that a cloud touchpoint surfaces
   explicitly, without becoming a per-workout chore. Coaches stay automatic:
   that is what the relationship already means.
2. **Notifications ship as poll + local**, per the correction above. Real push
   stays available as a later transport upgrade.

## Risks

- Auto-broadcast is a widening of default data flow; it must be disclosed
  where it happens (the completion sheet should say where the workout went),
  not only in a settings screen.
- A push pipeline that mis-applies the matrix would notify friends about
  workouts — the exact thing the operator ruled out. The policy belongs in one
  server-side place with tests, not duplicated per client.
