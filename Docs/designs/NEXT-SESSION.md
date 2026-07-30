# Next session — handoff from 2026-07-30

Ordered by what breaks or costs most if left. Copy any block into a new session.

---

## 0. FIRST: the platforms are out of sync

**iOS is on 375 (TestFlight). Android is on 75 (Play internal).** The Android
publish failed at the release export — `skip-export` reported 3 errors with
**zero `.swift error:` lines** and a missing plugin-output file, which is the
stale-build-plan signature, not a code problem.

```
rm -rf drift-android/.build
cd drift-android && ANDROID_HOME=/opt/homebrew/share/android-commandlinetools skip app launch --android
./scripts/android-publish.sh
```

Unpublished on **both** since 375: leaderboards visible-to-everyone by default,
unread badges on the people strip, and the food-streak fix. Bump iOS to 376 and
publish both together so they're back in step.

---

## 1. Food calorie/macro inconsistency — a real data bug, reported by the operator

Barcode scan of **aloo bhujia** returned `130 kcal · 8P 41C 47F per 100g`.
Atwater says 8×4 + 41×4 + 47×9 = **619 kcal**. The macros are right for a fried
snack; the energy figure is wrong by ~5×.

**Likely cause: mixed bases** — 130 kcal is plausibly the per-SERVING value
(~25g) while the macros came from the per-100g column, then labelled "per 100g".

**Fix the class, not the record.** An Atwater consistency guard at parse time:
compute 4/4/9 from macros, compare to stated energy, and when they disagree by
more than ~25% either prefer the computed value or reject the record loudly.
Applies to barcode, label OCR and USDA import alike. Tier-0 fixture is right
there: `(130, 8, 41, 47) → inconsistent`.

Then check whether serving-size parsing mixes columns generally — the dangerous
cases are the ones where the two columns are *close*, so it's silently wrong
instead of obviously wrong.

---

## 2. Workout-history backfill — makes "transfer history" real

Today a session only reaches the server at the moment it's finished
(`WorkoutBroadcast.send`, once, from the completion sheet). Everything logged
before sharing existed, or with the switches off, is local-only. So
`coach_history_grants` grants access to rows that may not exist: a coach sees the
briefing but not the sessions.

Build `WorkoutHistoryBackfill`: walk the local store, publish anything not yet on
the server as a client-owned row **with its original `started_at`**, push its
sets, mark completed. Explicit trigger on the coach sharing card, with a count.

**IT MUST NOT NOTIFY — two problems, not one:**
1. Alerts: route through `NotifiableEvent.clientWorkoutImported` (already returns
   false from `alertsPhone`) — verify `SocialAlertPoll`, don't assume.
2. **The unseen badge, which is the one that bites.** "N new sessions" comes from
   `SeenMarks.unseenSessionCount`, computed on the COACH's device. The
   backfilling client can't touch it, so 200 sessions become "200 new" with no
   notification involved. Needs a server-side `backfilled boolean default false`
   on `live_workouts`, excluded from the alert poll AND the unseen count.

Also: idempotence via a published-ID set (a duplicated year is not hand-fixable),
batching that leaves whole sessions never half of one, and a bound on depth.

Full notes in `Docs/designs/social-system-2026-07.md` §7.

---

## 3. Two-account simulator walkthrough — never run end to end

The single highest-value QA action. It found the invisible Today row, the frozen
counts, and the sharing that reached nobody — all of which passed every test.

`scripts/social-qa-seed.sh` seeds four personas and tears down by prefix.
**Blocker found:** writing a session into the sim's SQLite isn't enough — iOS
also shadows the token into the Keychain, so the app still reads as signed out.
Sign in through the UI instead, then seed.

Drive: claim username → seed → verify coach sees full history, friend sees 30
days, stranger sees neither → leaderboard renders → profile sheet → teardown and
confirm zero residue.

---

## 4. From the adversarial review — still open

- **The per-board "Make private" switch disappears** if a board drops below 2
  participants, while `friendsOnlyBoardKeys` keeps publishing globally. The off
  switch must live somewhere unconditional.
- `unreadCounts()` (migration 0010) and `ageInDays` are **built with no callers**.
  The UI still counts from a 100-message window and ships a user-visible apology
  ("Tap to catch up") for exactly the imprecision 0010 removed.
- `markThreadRead` watermarks from **the device clock**. A phone 10 minutes fast
  marks future arrivals as read. Inert while unwired; wrong the moment it isn't.

---

## 5. Android visual parity — do it globally, not per component

Operator: "Android boxes are weirdly bigger and not smooth." I patched the
components I'd added (`#if os(Android)` tighter padding + pinned minHeights) and
**could not see a difference in the emulator**. Comparing screenshots, the
chunkiness is **app-wide** — the Snap/Describe/Search/Recent chips, meals card
and stat tiles are all taller than iOS.

So it wants a deliberate `Theme` metrics pass against iOS, screen by screen, not
more per-component shaving. Material's touch-target floor and font scaling are
the likely culprits.

---

## 6. Bigger pieces, proposals written

- **Person page** — one adaptive screen replacing `PublicProfileSheet` /
  `ChatView` / `CoachPageView`. Header, activity, mutuals, shared-board standing,
  recent conversation with inline reply, relationship actions. Adapts by
  relationship, same principle that makes "coaches are just profiles" work. Makes
  the people-strip circles meaningful (tap a person → the person).
- **Shareable cards** → `Docs/designs/shareable-cards.md`. Privacy decision comes
  first (anonymise everyone but the poster). Not blocked on #1109 — that's the
  import seam; `ACTION_SEND` needs no Activity result.
- **Realtime chat** — `supabase_realtime` already publishes `messages`. iOS easy;
  Android needs an OkHttp WebSocket facade (URLSession parks under Skip).
- **HealthKit background delivery** — the only way auto-detected workouts reach a
  coach without the app being opened. Workouts `.immediate`, steps hourly. No
  server, no credentials.
- **Real push** — a local notification can't fire for a server event while the app
  is closed, so coach alerts are *eventually*, not promptly. Blocker is
  credentials, not infrastructure: trigger → `pg_net` → FCM/APNs.

---

## 7. Known-red, don't be alarmed

- **#1050 — LLM eval is red: 69 of 231.** Pre-existing, mostly `IntentRoutingEval`
  and `AmbiguityEval` drifting toward `log_food` as a catch-all. Not from the
  social work (`ExerciseDatabase.match` has no caller on the classification
  path). Deserves its own session. Note `'log lunch'` still creates a food entry
  named "lunch".
- **#1160 flake** — `concurrentAddCustomExercise` / `FlagOff` fail ~50% under
  parallel from shared static caches. Re-run before investigating.
- **Telemetry** — 5,600+ events from 24 installs, now pruned daily by pg_cron
  (0013). `quick_add` is 59% of all events, and both `quick_add` and
  `action.quick_add` exist — likely double-firing plus a naming split.

---

## Safety notes

- DB backup: `~/drift-db-backups/drift-public-20260730T125627Z.sql`, verified
  row-for-row. Contains real health data — mode 700, outside the repo.
- **Backward compatibility now matters**: 375/75 are live. Additive migrations
  only; no new NOT NULL without a default. Proven by simulating a build-371
  client's writes under RLS.
- Migrations 0001–0019 all applied to production and each re-run to prove
  idempotence.
