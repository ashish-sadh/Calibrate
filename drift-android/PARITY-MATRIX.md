# Android Parity Matrix

Owned by the **parity scout** (Opus 5 lane per directive 0-MODELS-PLAN-FABLE-EXECUTE-OPUS).
One row per screen/sub-surface.
Status ∈ `ok` / `deviation` / `missing` / `broken` / `ios-only-by-design` / `unknown`.
`unknown` = enumerated from iOS source, not yet verified on the emulator.
Issue column: the GitHub issue tracking the gap (blank when ok/unknown).
Structural ground truth: Android hosts SharedUI single-source files for
**Workout** (WorkoutTab → WorkoutView) and **Food** (FoodTab → FoodTabView);
**Today / Body / More** are still Android-only re-creations (TodayTab.swift,
WeightTab.swift, MoreTab.swift) — though Today now hosts two SharedUI
single-source components inside its re-creation (`MealTimelineSection`,
`V6CoachingNudge`). Capture + health sub-screens are not ported at all.
*(Corrected scout #23, 2026-08-17: this header also said **Coach** was "not
ported at all" — it is. `AIChatView` is SharedUI single-source, reached from
the floating `ChatIconButton`, and scouts #19 and #21 both drove it on device.)* **Sharing / Social** hosts ~4.6k ln of SharedUI single-source
and ships in the APK. *(Corrected scout #18, 2026-08-04: this header previously
said Sharing was "100% non-functional — sign-in parks on the URLSession bridge
(#1194, P0)". **#1194 is CLOSED** — `SyncClient.swift:40` now defaults to
`DriftPlatform.httpSession`, and `rg "URLSession.shared" DriftCore/Sources` hits
only the seam's own default. Scout #16's parking verdict was overturned
on-device. Sharing rows are `unknown` = **untested**, not unreachable; #1197
is the verification pass.)*

**App-shell fact added scout #24 (2026-08-17):** Drift is a **light-only app by
design** — `Drift/DriftApp.swift:53` pins `.preferredColorScheme(.light)` and every
`Theme` colour is a hardcoded hex, not an adaptive/semantic colour. The Android app
has **no equivalent** and ships `Theme.AppCompat.DayNight.NoActionBar`, so under
system dark mode it half-themes: light cards, Material-white text. Any future row
that reads "invisible text on Android" should check #1228 before being filed as new.

## Session notes (append-only)

- **2026-08-17 (scout #28, Opus 5):** **WORKOUT (#1064)** — taken over scout #27's suggested "Sharing once more". Sharing had just had **two consecutive sessions**, while Workout's last *device* sweep was **scout #12 on 2026-07-28** — three weeks and ~50 builds stale, in the area the operator has pinned hardest (0-FOCUS, 0-SCREEN-BY-SCREEN-WORKOUT, directive 5 "workout lookup + tracking ARE the acceptance test"). It also absorbed #27's named residual, `CoachMeView` at `WorkoutView:510`, without needing the sharing fixture. **The headline, #1252, is a glyph class that the glyph issue landing the same hour cannot catch.** `sym()` ships three names as a *real, confident Material icon of the wrong object*: `brain.head.profile`→**AccountCircle**, so the **AI Coach** button wears the account avatar; `clock.arrow.circlepath`→**Refresh**, so **four** "what already happened" affordances (Log Past Workout, the History header, Today's Recent chip, Weight history) read as *reload*; `number`→**List**. #1233 (`3e439102`, committed by the executor mid-session) is scoped to **triangles**, and its new invariant — *no case may rewrite a non-triangle name into a triangle* — does not constrain these; I re-read `git show HEAD:SharedUI/Symbols.swift` and all three survive it. A triangle-hunt structurally cannot find them **because nothing looks broken**. I made the issue actionable rather than just true: I enumerated the pinned skip-ui's Material set and it is **43 icons**, with no brain, psychology, history or restore among them — so no remap can fix these, and the repo's own answer is the drawn `#if os(Android)` shape (DumbbellShape, FlameShape, ClockFaceShape, BarChartShape, and #1233's new CameraShape/ChatBubbleShape/SendUpShape). `ClockGlyph.swift` already draws a clock face, so the history glyph is that plus an arc. **What I refused to file is the more useful half.** (1) Android's picker flattens iOS's six distinct body-part/equipment glyphs onto one person — but `Symbols.swift:132-136` collapses the whole `figure.*` family **deliberately and with a written justification**, and with 43 icons there is no alternative that keeps the category; unlike Refresh-for-history it does not change the meaning. (2) The completion card's indigo "Send to someone specific" looks like a goal-aware-colour violation — it is `Theme.chartTrend` in shared code, identical on iOS. (3) `"1 exercises"` is real but is `"\(count) exercises"` in **shared** code, so iOS says it too — a polish bug, not a parity gap. (4) I predicted the Android in-content X/Finish chrome would strand users by scrolling away; it does scroll away, but the scroll's tail carries a full-width Finish **and** Cancel Workout, so the prediction was **wrong** and I dropped it. (5) I predicted the two-TextField "Edit Workout" alert would silently drop Notes, since the codebase's own comment at `WorkoutDetailView:324` says Fuse binds only the first field per scope — so I typed `legday`, saved, and **queried the database**: `notes='legday'` was written. Refuted. Believing the screen there would have produced a confident, wrong P1. **New ground.** `CoachMeView` is device-driven for the first time and is a **match** — same chrome, same opening turn, same chips, same input bar. The full directive-5b loop ran on 104: 5 templates loaded → empty workout → picker multi-select → batch add → set-done → rest timer → Finish → options sheet → completion card → History → `WorkoutDetailView` → Edit Set → ⋮ → Edit Name & Notes (DB-verified) → Delete Workout (DB-verified, 4→3 rows). That last one is a **narrowing datapoint for #1219**: `dismiss()` from an `.alert` action works fine, so that bug is specific to `.confirmationDialog` — posted, with the suggestion that swapping the close-confirm is a candidate fix with a working precedent one file away. I also drove the templates card **state-matched** (the same 5-template fixture on both devices) and it is a pixel match apart from ⋯-in-a-ring vs ⋮. **Provenance, on a contested day.** Both devices were shared with a live executor lane the whole session: it typed into fields I was using, navigated the iPhone sim out from under me twice, and reinstalled the APK at 22:26:02 and again at 22:32:42. I discarded every ambiguous capture rather than reporting it — including my `CoachMeView` "3 days" turn, which is why that row is `unknown` and not a verdict. Critically, the emulator was running the executor's **uncommitted WIP** for part of the session, `Symbols.swift` among it, so I diffed the working tree before trusting a single glyph reading and re-confirmed every finding against `HEAD` after they committed. All workout captures (`and-11`…`and-31`) are on the **post-#1233** build, which is what makes #1252 strong rather than stale. `logcat -b crash` **empty** for `com.drift.health` across the entire session (one cold launch at 3455 ms — posted to #1226, where the running series is now 3.4–4.3 s and the 5.8 s title is stale). Rows changed: **17** (4 rewritten off `unknown`, 12 added, 1 enriched). Issues filed: **1** (#1252 P1); device evidence posted to **#1219**, **#1234** (whose "blank list on open" and "no Done pill" claims did **not** reproduce — recommended re-scope to the styling residue) and **#1226**. Test data: I logged one workout and deleted it, DB-verified; the 5 Drift Package I templates are **left in place on purpose** so the next session inherits a fixture that matches the iPhone. **Residuals, named honestly:** `ActiveWorkoutView` row → `ExerciseDetailView` is still undriven; the CoachMe conversation past the first chip is undriven; Share and Save-as-Template from the detail ⋮ were not fired; and the disabled-send-button dimming needs one screenshot on the committed build. Rotation next: **Food** — it carries 52 `missing` and 4 `unknown` rows, is the second-most-used surface in the app, and was last device-swept by scout #20 on 08-11.

- **2026-08-17 (scout #27, Opus 5):** **SHARING / SOCIAL — THE COACH COHORT (#1197)**, taken per scout #26's rotation call. #26 left the cohort as its named residual because its graph was `role=friend` only; this session built the trainer edge and drove the whole thing, so **`ClientsView`, `ClientDetailView` and `CoachBriefingView` are device-verified on Android for the first time**, along with the Android **incoming** requests card that #26 could not reach. **The direction is the thing worth writing down:** `sendRequest(role:.trainer)` writes `requester_id = client, addressee_id = coach`, so the **iPhone** taps "Ask to coach me" to put **Android in the coach seat** — get that backwards and you test the coach screens on the wrong device. Both edges coexist; the client then enabled two share levels, which pushed a real populated `client_briefings` row, and **the matrix's standing worry about `BriefingTrendChart`'s 5 GeometryReaders did not bite** — both Path charts (Weight -4.8 lb over 2w, Sleep over 9w) painted with the rest of the screen. **The headline is #1251, and it re-frames three scouts' worth of "this block is flaky":** the hub **intermittently loses every profile-derived field at once** — a real accepted friend renders as "No friends yet" *and* the incoming request renders as `@someone` with a `?` avatar, together, in **3 of 4 valid cold starts on builds 102 AND 103**, while iOS with the identical two edges never reproduces. I replayed the app's exact PostgREST URLs **with the device's own JWT** and the server returns correct rows every time, and `logcat` shows the facade logging **HTTP 200 for every call** — so the failure is a *silent empty body*, which is precisely why `SharingView:803-810`'s deliberate guard ("A failed load and an empty list must never look the same") never fires: it only catches `connections()` **throwing**. I gave the planner the concurrency hypothesis (refreshHub's six `async let` fan-out, #1180 family) **labelled as a hypothesis** — I did not instrument the facade. **What I refused to file matters as much as what I filed.** (1) Android showing only a "Your client" pill, with Friends *and* leaderboard gone, looks like two missing pills — it is correct shared behaviour: `friendCount` counts only `.friend` rows and `connections()` dedupes a two-edge person to the coach/client kind, and **iOS did the mirror-image thing** ("Your coach" alone). (2) The briefing's indigo charts and delta labels look like a goal-aware-colour violation — `:558` strokes `Theme.chartTrend` **by design**, identical on iOS. (3) The client's "See what your coach sees" mirror and the coach's real view **disagree on Sleep** (iOS "-0.7 h, 6.9→6.2" vs Android "+0.1 h, 6.4→6.5" in the same minute) — **Android is faithful**, the stored row really is 6.4→6.5, so the client is previewing a locally-recomputed series; but that is one confounded sample and an iOS/shared issue, not a parity gap, so it is a recorded row and a note on #1197, **not** an issue. **The trap that bit me, recorded because it will bite the next scout:** there are **two simulators named "iPhone 17 Pro"**, and the booted one is signed out — the `@driftscout26` identity lives on the *shutdown* `A8E90B07…` (iOS 26.5). For ten minutes the sharing block looked like it had regressed to the claim screen; the fix is to read `sync_session` out of each device's `drift.sqlite` rather than trusting the name. mobile-mcp taps also went to the wrong twin at least once, so every tap this session was verified by screenshotting the intended device. **Provenance.** Emulator `versionCode=102` at start; the **executor lane reinstalled 103 at 20:16:22 mid-drive and was concurrently driving the device** — it typed `ashish` into the friend-search field I was using and later opened Photo Log during a repetition, which I discarded rather than reporting. 103 = 102 + `f2103151` (#1196), whose entire `SharingView` diff is **four deleted `#if !os(Android)` lines** around autocapitalization, so it cannot explain #1251 — and every finding was reproduced on 103 anyway. `logcat -b crash` empty for `com.drift.health` across ~8 cold launches, a request/accept round-trip and the full cohort drive. Rows changed: **15** (9 rewritten off `unknown`, 6 added, plus the section preamble extended). Issues filed: **1** (#1251 P1); device evidence posted to **#1197** (full cohort verdict), **#1233** (both Today pills device-proven, with the `"missing icon"` a11y label as a regression assertion) and **#1226** (cold start 4022 ms / 4261 ms — the ~3.5 s of scout #25 has drifted back up). Also re-reproduced #1216 and #1204 verbatim on the search field. No code touched (matrix only). **Residuals, named honestly:** `LeaderboardView` is now *harder* to reach, not easier — the promotion consumed the only friend-kind connection, so it needs a demote or a third account; `CoachMeView` (`WorkoutView:510`) needs no graph at all and is still the cheapest undriven screen in the app; `CoachPageView`/`CoachSharingCard` on **Android** need the reverse trainer edge; `ClientSessionDetailView`, `incomingTemplatesCard`, `ShareTemplateSheet` and `FriendSharePicker` all need an assignment or a shared workout, which the coach/client pair now makes reachable in one step. I did not fire note-add, template-assign, or either two-tap remove confirm — the removes would destroy the fixture the next session inherits. Rotation next: **Sharing once more** — the coach/client pair is durable and server-side, so an assignment round-trip (`ASSIGN A WORKOUT` → `incomingTemplatesCard` → accept) plus `CoachMeView` would close most of what is left of this block in one session.

- **2026-08-17 (scout #26, Opus 5):** **SHARING / SOCIAL (#1197)** — I took this over scout #25's suggested "Coach again, seeded". Sharing carried **22 `unknown` rows, the largest dark block in the matrix**, it was scout #24's own named residual ("I did not reach Friends & Coaches from More"), and unlike More's 45 `missing` rows it is *reachable* — you cannot drive a screen that doesn't exist, but you can drive this one. **The decisive fact was on the disk, not in the queue: the iPhone 17 Pro simulator had Drift 382 installed — equal to HEAD — and its `sync_session` was EMPTY.** That single check turned a blocked session into the block's first real two-device pass: I claimed a throwaway `@driftscout26` on the sim and built the social graph **through the request/accept UI**, which is what the #1197 plan actually prefers over seeding, because constructing the graph *is* half the verification. **Scout #21's two-INSERT SQL recipe was never run and is still unused; the operator's `@ashish` account was never touched.** It also discharges #21's standing residual — every iOS claim in this block was source-derived until today; all of them are now genuine side-by-sides. **The headline is #1243, and it explains three scouts' worth of confusion: the Friends hub loads connections ONCE per process and never refetches.** iOS accepted the request and immediately showed "1 connection", the LEADERBOARDS card and the friend row; Android — *after fully leaving the hub and re-entering* — still read "No friends yet", no LEADERBOARDS card, and an "Add friend" button that would now 409. `am force-stop` + relaunch, same screen, correct. The mechanism is nailed by an accident I nearly missed: **the typed search text and its result row survived the nav round-trip**, which proves the view instance persisted, which proves `.task { await bootstrap() }` (`SharingView:97`, the only load trigger — no `onAppear`, no `scenePhase`) never re-fired. I deliberately did **not** extend this to "refreshHub is broken": that path fired at a moment when the server genuinely had no accepted row yet, so it is untested, not proven broken, and I said so on the issue. **This is why the block looked unreachable — the natural verification loop silently shows stale data, so any future session here must cold-restart after every graph change or it will file false "screen is empty" bugs.** **#1244** is the one a user would notice first: `person.badge.plus` has no `sym()` case and no skip-fuse-ui entry, so **"Send friend request" — the primary CTA of the entire social feature — renders a ⚠️ HAZARD TRIANGLE**. It is explicitly *not* #1233 (that issue fixes two wrong `exclamationmark.*` cases; this is the *unmapped* names falling through `default:`), and fixing #1233 would not touch it. The same screen also flattens `person.2.fill` and `figure.strengthtraining.traditional` onto one generic person — so "Friends" and "Ask to coach me" are indistinguishable at a glance — and maps `message.fill` to a paper plane, i.e. *send* where the action is *open a conversation*. I raised, but did not decide, the design question underneath: `Symbols.swift` **deliberately** leaves names unmapped so a new caller "gets a visible warning triangle rather than a silent wrong glyph" — a sound developer tripwire that fires in production, at users, which is exactly how a hazard symbol reached the primary social CTA. **#1245** root-causes the `0-SHARING-DONE` deferred residual ("Android chat opens scrolled-to-top") that has sat unowned since 07-28: it is not a scroll *position*, it is the *anchor* — `.defaultScrollAnchor(.bottom)` (`ChatView:39`) has **zero implementation hits in skip-fuse-ui/Sources** while its neighbours `scrollDisabled`/`scrollIndicators` are implemented in the same file, i.e. a silent shim. I labelled the no-op **strongly-indicated, not proven** (I did not instrument the runtime) and pointed at the working `AIChatView:98-102` sentinel precedent. **Verified-clean and recorded rather than filed, which I think is the more useful half:** (1) the chat composer's white band with a gap above the tab bar looked like a broken layout — **iOS shows the identical gap**, so it is shared design; I nearly filed it. (2) The "Findable by search" toggle flipped ON→OFF across two visits with no interaction, which looks like a privacy control being written behind the user's back — the server row has been `discoverable=false` since **04 Aug**, 13 days before this session, so it is a display-only mis-paint and **nothing was written**; I posted that to #1217 specifically to *refute* the scarier hypothesis and stop a session hunting a phantom write path. (3) #1216's framing needed correcting: **iOS lifts the tab bar over the IME too** — the Android-specific part is that content renders *underneath* the bar instead of being inset, which changes the fix from "pin the bar" to "add bottom safe-area inset". **What works, said plainly, because a lot of this block was assumed broken:** `.sheet(item:)` presents with the right payload (plan item 3 ✓), the pushed profile variant has correct chrome (item 4 ✓), the sheet-hosted `NavigationStack` push to ChatView works, and **1:1 chat send + cross-device delivery genuinely work** — typed on Android, received on iOS. **Provenance, and the trap that bit #23 and #25 bit me too — the countermeasure worked again.** `versionCode=100` at start (`lastUpdateTime 17:25:17`) and the More footer printed "Drift for Android · build 100" mid-drive; at the end an executor had installed **101 at 18:22:27**, *after* my last capture (18:16), and `git diff 23f685e3..e4ad2924` touches only AppDatabase/Persistence/CoreResourcesBootstrap/DriftAndroidApp — **none of SharingView/ChatView/Symbols/PublicProfileSheet** — so no finding can be a build artifact. One self-correction worth recording: an early Android jump to Progress Photos looked like the executor hijacking the emulator; it was **my own tap landing on a popped-back More screen**, confirmed when the identical thing happened on iOS, and I stopped tapping by remembered coordinates and used the element tree instead. `logcat -d -b crash` **empty** for `com.drift.health` across the whole session (two cold launches, every sheet, a full request/accept round-trip, a chat send). Rows changed: **19** (4 rewritten off `unknown`, 11 added, plus the section preamble rewritten — it still declared the block fixture-blocked and pointed at an unrun SQL recipe). Issues filed: **3** (#1243 P1, #1244 P1, #1245 P2); device evidence posted to **#1197** (full surface-by-surface verdict), **#1217**, **#1216** and **#1200**. **Residuals, named honestly:** `CoachPageView`, `ClientsView`/`ClientDetailView`, `LeaderboardView`, `CoachBriefingView`, `CoachMeView`, `CoachSharingCard` and `BriefingSnapshot` are still undriven — my graph is `role=friend` only and the trainer edge needs a second round-trip, which with #1243 in the way costs a cold restart per step. Plan items 1 (CoachMe autoscroll), 5 (async-load recomposition), 6 (two-tap confirms) and 7 (briefing speed) are untouched; I did **not** arm the Unfriend confirm, because it would have destroyed the graph the next session inherits. Android's *incoming* requestsCard is also still unverified — I only ever sent outbound. No code touched (matrix only). Rotation next: **Sharing again** — the graph is durable and persists on the server, so the next session starts from a populated board instead of rebuilding it; add the trainer edge and the whole coach cohort opens in one pass.

- **2026-08-17 (scout #25, Opus 5):** **COACH / AI CHAT (#1066)** — I took this over scout #24's suggested "More again". #24's own rotation note said More's remaining
  45 rows are Settings/Profile/Weight-Goal/Algorithm, and every one of them is `missing` with an owner already (#1114/#1116/#1117/#1118/#1146). You cannot *drive* a screen
  that does not exist on the device, so a second More sweep could only re-read iOS source that two scouts have already read. Coach, by contrast, was due (last swept 08-10),
  is the operator's declared showstopper under PRODUCT FOCUS and directive 0-AI-FOCUS, and — decisively — **build 96, carrying the #1174 Coach photo-attach work committed
  hours earlier, was sitting installed on the emulator**. Newest code, highest operator value, a week stale in the rotation. **The headline is that this section was aiming
  three lanes at a version of the app that no longer exists: ~10 rows read `broken` against four issues that are all CLOSED** — **#1209** (the P0 "Drift Coach executes NO
  tools"), **#1180**, **#1137**, **#1135**. I drove them. `what is my current weight` returns *"You're making steady progress this week. Your current weight is 180.1lbs, down
  0.5lbs in the last 7 days"* — the device's own stored value, with a `via Nebius` badge and a `Checking your data…` tool-status string, and `registerAll()` is wired at
  `DriftAndroidApp.swift:68`. The send button reads `enabled="true"` with the keyboard up and text in the field, which is the exact state #1137 said was broken. **Drift Coach
  executes real tools against real user data on Android**, and the matrix said the opposite in ten places. **Two new issues, both P1, both side-by-side-proven rather than
  source-derived. #1232 is the one that matters:** `how much protein did I eat today` renders the sparkle avatar and the `via Nebius` badge and **nothing else** — no bubble,
  no text, no card. iOS, same query, same Nebius backend, same empty diary, answers *"No food logged yet. Log meals to track protein."* This is not #1125 (port the 13 cards)
  and would survive every card shipping: the tool's text is real and ungated (`ToolRegistration.swift:256`, zero platform gates in that file) and **every** path that sets
  `remoteProvider` sets `text` in the same whole-array reassignment (`MessageHandling.swift:1602/:1611/:1824`), while `applyOutput` *removes* the message when the text is
  genuinely empty — so a rendered badge proves the text was non-empty. Data right, paint wrong, at the `if !msg.text.isEmpty` conditional (`ChatBubble.swift:164`); I gave the
  planner the #1180-family conditional-insert hypothesis **labelled as a hypothesis**, because I did not prove it. It also falsifies a load-bearing comment sitting in the
  source at `ChatBubble.swift:200-203` — *"Every card-emitting turn also carries a text summary, so a card-less bubble still informs"* — which is the assumption that let 12
  missing cards be filed as P2. **#1233** is a clean directive-0a violation: `Symbols.swift:65` maps iOS's `exclamationmark.bubble` **onto `exclamationmark.triangle`**, and
  `:60` does the same for `exclamationmark.circle.fill`, so three everyday *"we couldn't read that, try again"* states (`DescribeMealSheet:208`, `SnapMealSheet:324`,
  `ExerciseVoiceLogSheet:239`) greet the user with a **hazard triangle** where iOS shows a speech bubble. Material's `error_outline` is the same-meaning glyph, so it is not
  blocked on anything. **Two leads were run down and recorded CLEAN rather than filed, which I think is the more useful half of this session.** (1) Android showed 2 suggestion
  pills where the code predicts 3 — `Calories left` missing. That is **data, not parity**: the DB holds an orphan `meal_log` (`id 9018, lunch, 19:06:05Z`) with **zero**
  `food_entry` rows, so `loggedMeals` contains "lunch" while `eaten == 0`, collapsing the pill branch; iOS showed 3 only because it was opened from the Exercise screen. I
  verified this by querying the tables rather than trusting the reasoning. (2) The Coach→food handoff *looked* like a dead end — a warning triangle over "Couldn't work that
  out" with only Cancel and Try again — and I nearly filed it as unrecoverable. **Try again returns to an editable "Describe your meal" field**, so it is recoverable; the real
  and much smaller finding is that iOS lands you on an editable search hub with live results in one step where Android auto-parses, fails, and needs two. Filing the stronger
  claim would have been wrong. **Provenance, and the same trap that bit scout #23 — it bit me too, and the countermeasure worked.** I checked `versionCode` before driving (96,
  `lastUpdateTime` 12:45:17) and again at the end, and an executor had installed **build 97 at 13:25:40, mid-drive**. Because #23 turned that into a standing rule I re-checked
  at the *end* rather than only the start, so I caught it in the same session instead of publishing contaminated claims: screenshots `and-01`…`and-10` are build 96,
  everything after is 97, and **#1232 was deliberately re-driven on 97 from a fresh cold-launched chat** — it reproduces 2/2 across both builds. 97 = 96 + the #1228 theme pin,
  which touches only `Main.kt` and none of the chat files, so neither finding can be a build artifact. (A **third** install landed at 13:39:33 while I was writing this note —
  still `versionCode=97`, i.e. the same code, and after every screenshot above; recorded because "the timestamp moved" is not the same fact as "the code moved", and the next
  scout should check the version, not just the clock.) `logcat -b crash` stayed empty for `com.drift.health` across the whole
  session (two cold launches, every sheet, a system file picker round-trip). Rows changed: **17** (11 re-pointed off closed tickets, 6 added). Issues filed: **2**; device
  evidence posted to **#1226** (cold start 3622 ms on 96 / 3479 ms on 97 — down ~35% from the 4.2–5.8 s in that issue's title, still 1.4× the 2.5 s criterion, so the issue
  stands but its title is stale) and **#1231** (the `via Nebius` cloud glyph is confirmed present on iOS and absent on Android; I flagged that #1232 should land first or the
  badge's layout gets judged against an empty turn). **Residuals, named honestly.** I did not tap a suggestion pill, so #1180's closure is **unverified** on that surface and I
  left the row `unknown` rather than inheriting either verdict — a closed issue is not evidence. I drove no write tools (log food, log weight, delete) **by choice**: this
  emulator is shared with two other lanes and [[harness_shared_emulator_test_writes_poison_state]] is exactly how the phantom `34.64 kg` reached a sibling's screenshots; those
  rows are `unknown`, not `ok`. One observation I refused to promote: cancelling the Coach's food sheet appeared to close **Drift Coach itself**, dumping the user on Today,
  where iOS's Cancel returns to the chat with history intact (that half *is* device-verified). But the Android half came from the post-"Try again" phase on a reinstalled app,
  and one confounded sample is not a parity claim — logged `unknown`, one clean run settles it. Cloud turns also classify in **5–6 s** (`Phase 2 (classify): 5031/6150ms`),
  which is slow enough to feel and is unowned — #1226 covers cold start, not turn latency; I recorded it as a deviation rather than filing, since one session's samples on
  SwiftShader are not a latency case. No code touched (matrix only). Rotation next: **Coach again, seeded** — the write tools, the suggestion pills and the nested-sheet
  dismissal are one disposable-DB session's work, and #1232 will need re-verifying against whatever fix lands.

- **2026-08-17 (scout #24, Opus 5):** **MORE / SETTINGS (#1067)** — next in rotation and the block scout #18 explicitly left as its own residual ("every ⚠ row above is
  source-verified only"). It carried **45 `missing` rows and had never once been driven**: enumerated by scout #5 on 07-27, re-read against HEAD by #18 on 08-04, both
  source-only. **This is the first device drive of the More tab in the program's history**, and it is also the block the operator named by hand in directive 0-EVERY-SCREEN
  ("there are so many screens in More on iPhone that don't work on Android"). Provenance is clean in the way scout #23's was not: `versionCode=94` /
  `lastUpdateTime=2026-08-17 10:41:32` were **identical before and after** the entire drive, the only commit between build 94 and HEAD touched Weight files (`69c69f4f`, #1143)
  so build 94 is UI-equivalent to HEAD *for this section*, iPhone 17 Pro sim had Drift **382** installed, and `logcat -b crash` stayed empty for `com.drift.health` across two
  cold launches, every sheet, and two dark/light flips. **The headline is a bug no source sweep could have found and no scout had looked for: Drift is unreadable on Android in
  dark mode.** `Drift/DriftApp.swift:53` pins `.preferredColorScheme(.light)` — Drift is a light-only app by deliberate iOS design — and the Android app has **no equivalent**
  while shipping `Theme.AppCompat.DayNight.NoActionBar` (`AndroidManifest.xml:55`). Under `cmd uimode night yes` the cards stay hardcoded light but every `Text` lacking an
  explicit `.foregroundStyle` inherits Material `onSurface` and turns **white on white**: on More that is `"Weight unit"` (`:21`), **both privacy toggle labels** (`:48`, `:60`)
  and the nav title; on Body it is the chart's headline `"81.7"` average and the `"History"` label. The tell is that the *subtitles* in the same card survive — they carry
  `.foregroundStyle(Theme.textSecondary)` explicitly. The iOS dark screenshot is **pixel-identical to its light one**, so this is a pure parity break, and the fix is the
  one-line mirror of iOS rather than colouring each `Text` (which leaves the next uncoloured one broken). Filed **#1228 (P1)**, with the honest note that a privacy toggle whose
  label cannot be read is arguably functional and the planner may want to raise it — the rubric says visual → P1, so P1 is what it got. **Today renders correctly in dark mode**
  and that is recorded as an `ok` row precisely so the fix's verification doesn't assume every tab is broken. One tempting lead resolved itself into the same issue rather than a
  second one: the pale band above the floating tab bar, present on **every** tab, **turns black in dark mode while the page stays light** — that identifies it as the Material
  *window* background showing through instead of `Theme.background`, so it folded into #1228 as a second symptom of one root cause instead of becoming a thin standalone ticket.
  **The other headline is board hygiene: 23 rows in this table pointed at CLOSED issues** — the same failure mode scout #23 found on Today, and worse here by volume. `#1115`
  (Settings port) was absorbed into #1114, `#1119` decomposed into #1146, `#1192` superseded by #1227, and `#1124` (Cycle) closed outright, discharging #18's deferred call. All
  23 re-pointed; the historical session notes were deliberately left verbatim, because they are the record of what each scout saw and not live pointers. **#1207 went from
  source-suspected to device-proven** and gained a requirement it did not have: one tap on Connect / Sync now opens `GrantPermissionsActivity` which **immediately auto-CLOSEs**
  (seven health permissions carry `USER_FIXED`), the app logs `Health Connect permissions granted: 0` — *it already knows* — then runs `syncWeight()` anyway and takes
  `SecurityException: Caller doesn't have READ_WEIGHT`, swallowed by `_ = try?`, leaving the screen **pixel-identical before and after**. Because `USER_FIXED` is terminal, a
  status string alone cannot fix this; the Done-When needs a route to Health Connect settings, and that is commented on the issue. Also driven and **recorded clean so nobody
  re-tests**: the weight-unit picker works end-to-end (kg → Body re-renders in kg → survives `am force-stop`), **preference durability is now DEVICE-verified** rather than
  #18's source-only verdict (telemetry OFF and `weight_unit=kg` both read back out of `app_pref` in `files/Drift/drift.sqlite` after a cold relaunch — [[skip_userdefaults_data_writes_dropped]]
  is genuinely closed for these keys), all three TRACKING sheets open and render, and the Health Connect permission ask does **not** spawn a duplicate `MainActivity` (task
  stayed `sz=1`), clearing #1096 on that path. Device evidence also posted to **#1200** (the More title is a large ~44sp bar that never collapses — ~230px of 2400 permanently
  vs iOS's ~100px inline — and content is clipped mid-glyph under it), **#1204** (`.pickerStyle(.segmented)` renders as a Material SegmentedButton with a pink fill and a ✓
  glyph — a control type that issue's list would otherwise miss), and **#1226** (cold start **3496 ms** on build 94, better than 92/93's 4.2–5.8s but still 1.4x the 2.5s
  criterion; recommended a median-of-5 baseline). Rows changed: **34** (23 re-pointed off closed tickets, 8 added, 3 upgraded to device-verified). Issues filed: **1** — quality
  over volume was the right call here, because everything else I found already had an owner and the valuable act was attaching device proof to it rather than growing the board.
  **Residuals, named honestly:** I did **not** reach Friends & Coaches from More (two coordinate slips sent me into Supplements twice, and by the time I had the scroll position
  right the dark-mode thread was worth more) — #1197 still owns social verification. The Support sheet's **~6s bare spinner** with no timeout or error path is real but I logged
  it `unknown`, not `deviation`, because it is the same SharedUI file iOS uses and I did not time the iOS side; one unmatched sample is not a parity claim. Pop-to-root on tab
  reselect was never tested. I restored everything I touched — telemetry back ON, unit back to `lbs`, both devices back to light — because this emulator is shared and
  [[harness_shared_emulator_test_writes_poison_state]] is how a sibling lane inherits a phantom. No code touched (matrix only). Rotation next: **More again** — Settings/Profile/
  Weight Goal/Algorithm are still 45 unreachable rows and now have clean iPhone reference shots (`ios-04-settings-top.png`) to port against; after that, Coach, last swept 08-10.

- **2026-08-17 (scout #23, Opus 5):** **TODAY TAB** — taken over the rotation's "Body/Weight again" because that section's remaining dark rows (DEXA, progress
  photos) are all `missing` with seven scoped issues already filed against them (#1185–#1191, #1166), so a sweep there would have re-confirmed known gaps rather
  than found new ones; Today was the front door carrying 19 `deviation` + 16 `missing` rows, source-enumerated 07-28 and re-verified source-only on 08-04 by a
  scout who wrote "8th consecutive scout with no device access". **The headline is not any single bug — it is that the iPhone simulator finally has a build
  installed** (`516EAAC8…`, iOS 26.4, Drift **380**, installed 2026-08-10 22:54). Four consecutive scouts recorded "no iPhone build installed" as the standing
  debt to `0-SCREENSHOT-EXACT-IS-THE-BAR`; this is the first session in the program that could satisfy that directive literally, and every iOS claim below is
  screenshot-backed rather than source-derived. The emulator was safe to take on a reusable check: `git log --since=2026-08-11 -- drift-android/ SharedUI/
  DriftCore/` returned exactly two commits, a test fix and a food-CSV export fix, so installed build 92 was UI-equivalent to HEAD for this whole section;
  `versionCode=92` and `lastUpdateTime=2026-08-11 06:30:38` were **unchanged from first screenshot to last**, so unlike scouts #20/#21 nothing was reinstalled
  underneath the drive, and `logcat -b crash` stayed empty for `com.drift.health` across 5 background/foreground cycles, 6 cold launches and every tab
  round-trip. **The board was aiming three lanes at dead tickets: four of the issues this section pointed at are CLOSED** (#1131, #1201, #1129, #1213) and two of
  them own features that visibly ship. `bdf9e48f` moved `MealTimelineSection` into `SharedUI/` and pointed both platforms at it, so the ten "Meal timeline …
  missing #1131" rows describe an Android flat-list re-creation that no longer exists — tap-to-expand, in-row Remove, the header "+" (driven: opens Add Food),
  earliest-first order and iOS's empty-state copy are all present, and the delete path is byte-equivalent to iOS's. #1130's nudge + INSIGHTS are **in flight, not shipped** — see the contamination note below. #1213's `gain 95.6 lbs` now reads `Target: eat 2340 kcal/day to lose 6.8 lbs`, correct against the device's own stored 81.1 → 78.0 kg.
  **Two new issues. #1225 (P1)** is the one a side-by-side makes obvious and source alone had missed for three sweeps: `dailyAverageCard` sits at body slot 4
  (`TodayTab.swift:282`) where iOS puts `tdeeCard` **twelfth** (`DashboardView.swift:259`, after the goal card). That single 528px card above the social pill
  pushes **all four log-method chips and the entire TODAY'S MEALS card off the first paint** — on Android you must scroll before any logging entry point is
  reachable, where iOS shows the four chips, the meals card *and* the stat trio unscrolled. The issue states its own confound honestly: the iOS sim has no weight
  goal so its hero renders the short no-goal fallback, and the claim that survives that is structural — subtract the hoisted card's 542px and Android's chips
  land at px ~1560 and its meals card at ~1960, both above the px-2170 fold. **#1226 (P1)** is an unowned miss against the operator's own number: cold start
  measured **5583 / 5777 / 4825 / 4188 / 4325 ms** (five `am force-stop` → `am start -W` runs, all `LaunchState: COLD`) against directive 0-PERF-P0's *"cold
  start < 2.5s on emulator"*, on a machine the directive itself calls faster than the Pixel 2 baseline. This is not the untrustworthy metric — 0-EMULATOR-GPU-
  CAVEAT(a) names cold start as trustworthy, unlike SwiftShader framestats — and it has had no owner since #1073/#1074 closed (#1202 covers per-reload
  redundancy, not launch). Filed as the measurement with an explicit "profile first, do not guess" Done-When. **THE LESSON OF THIS SESSION IS A METHOD FAILURE, AND IT IS WORTH MORE THAN THE FINDINGS: I checked
  `versionCode`/`lastUpdateTime` before driving (92) and again at 08:56 (still 92), and the executor installed BUILD 93 — cut from its own uncommitted #1130 work
  — at 08:59:17, between that check and the rest of the sweep.** [[harness_parity_lanes_share_one_emulator]] says to pgrep for a live executor before driving; it
  does not say the thing that actually bit me, which is that **the check has to be repeated at the END of the drive, not just the start**, because the install
  lands silently and every screenshot after it is of different code. On the strength of post-09:00 screenshots I filed a comment on #1130 saying the feature had
  shipped, that its `planned` label was dangerous, that its warning-triangle glyph was verified clean, and that the nudge was nondeterministic across launches.
  **All four claims were false and I retracted them in the same session.** The nudge and Insights do not exist at HEAD — `git show HEAD:…/TodayTab.swift` ends its
  body at `statTrio` — so the "absent" launches were simply build 92 without the feature and the "present" ones were build 93 with it; the file I cited for the
  glyph (`SharedUI/V6CoachingNudge.swift`) is uncommitted too; and the one difference that *was* within a single build ("Only 6% of days logged" at 09:00–09:01 vs
  "14-day logging streak" at 09:02–09:04) is untrustworthy because the executor was driving and plausibly seeding food rows at exactly that moment. Telling three
  lanes to close a live ticket would have been the most expensive thing this sweep could do, which is why the retraction went up immediately rather than at the end.
  The two filed issues were re-checked against `git show HEAD:` and both hold — #1225's citation was 36 lines high (`dailyAverageCard` is **:246** at HEAD, not
  :282) and got a correction comment; #1226 spans builds 92 and 93 and got a provenance table. Rows changed: **28** (14 corrected off stale/closed tickets, 10
  added, 4 flipped to `ok` on device evidence), of which **4 were then corrected again** once the build swap surfaced. **One tempting lead was run down and recorded CLEAN so the next scout doesn't spend a session on it:** the social pill's
  **single-person** icon is `Symbols.swift:89` (committed) falling `person.2.fill` to the closest mapped glyph because skip-ui maps no two-person symbol at all —
  directive-0a-correct, do not "fix". (The protein nudge's warning triangle *looks* like the same kind of cleared lead and I initially recorded it as one, but its
  justification lives in uncommitted code and is #1130's verifier's call, not the scout's — that row is back to `unknown`.) Also verified working and recorded so nobody re-tests: intake-card tap → Food tab, social pill → Friends push, Daily Average **(i)** → inline
  explainer, meals "+" → Add Food sheet, stat-trio routing, and no pull-to-refresh on Android where iOS has `.refreshable` (`DashboardView.swift:360`). No code
  touched (matrix only). **Residuals:** I did not log or delete a food entry, by choice — the meal row's expand/Remove interactions are the newest ported code and
  genuinely unverified with real rows, but writing to a DB three lanes share is exactly how #1213's phantom `34.64 kg` got into a sibling lane's screenshots
  ([[harness_shared_emulator_test_writes_poison_state]]); those rows are marked `ok` on shared-component provenance, not on a driven row. The **goal-mode**
  nutrition hero is still uncompared — iOS's sim has no weight goal so `TodayDonutView` never rendered against Android's ring re-creation, and setting one would
  mutate the reference device. And one iOS-side oddity worth an operator's eye rather than a ticket: the iPhone build opens its Food tab on **Tue Aug 11** with
  today (Mon Aug 17) not even in the visible date strip, while Android correctly opens on today. Rotation next: **Today again, once #1130 commits** — the goal-mode hero comparison and the meal-row
  interactions with real entries are one seeded session's work, and the nudge/Insights rows need re-verifying against committed code rather than a lane's WIP;
  then More/Settings, which carries 45 `missing` rows and the operator's 0-EVERY-SCREEN mandate. **Standing instruction to the next scout: capture
  `versionCode` + `lastUpdateTime` immediately before AND immediately after every drive, and treat any screenshot taken across a change in either as unusable.**
  **And a second harness trap, from the commit that carries this note: `git add <one path>` does not protect a scout's commit, because the index is shared with
  every concurrent lane.** The executor had staged its own five #1130 files while I was writing the matrix, so my `git commit` swept them onto main under a docs
  message with no verifier pass — the exact "never commit worker WIP" failure. I did not unwind it: by the time I checked, the executor had already committed
  `663b525d` on top, and `git reset` would have destroyed a sibling lane's commit to save my own commit message. The tree at HEAD is correct and complete
  (`nudgeCard` :319, `insightsSection` :321, `behaviorInsightGlyph` present); only the attribution is wrong, with the bulk of #1130 sitting in `ac299c5d` and its
  last 24 lines in `663b525d`. **Use `git commit -- <path>` (a partial commit, which ignores the rest of the index) rather than `git add <path> && git commit`,
  and check `git rev-parse HEAD` before any reset — that guard is the only reason the executor's commit survived this session.**

- **2026-08-11 (scout #22, Opus 5):** **BODY / WEIGHT** — picked over the rotation's "Sharing again" because scout #21 left that section blocked on #1197's
  fixture rows (no connections on the emulator identity, so six surfaces are unreachable until someone INSERTs them), while Body/Weight was the largest
  never-driven block on the board: **39 rows carrying a `source-verified 2026-07-28, device-verify debt` tag and not one device screenshot behind any of
  them.** The emulator was safe to take on a check worth reusing: `git diff --stat <build-90-publish> HEAD -- drift-android/ SharedUI/ DriftCore/` returned
  only Coach/ComposeKick/PhotoLogEntry files — **zero Weight files** — so installed build 90 was byte-equivalent to HEAD for everything in this section even
  though HEAD is build 91. The executor was running `xctest`, not driving. Build stayed 90 with an unchanged `lastUpdateTime` across the whole sweep, so
  unlike scouts #20 and #21 nothing was reinstalled underneath this drive, and `logcat -b crash` was **empty** for `com.drift.health` throughout.
  **The headline is a control that deletes the screen's hero element: tapping the `1W` range chip makes the weight chart vanish outright** — the chip row
  runs straight into `HISTORY`, with no empty state and no message; `1M` and `All` bring it back. I specifically ruled out the #1180 shape before believing
  it, scrolling down and back up to force a recomposition with the chart still absent, and reproduced it twice. The cause is that Android treats the chip as
  a **data filter** (`WeightTab.swift:143-149`) and then gates the chart's existence on the filtered array (`:193`), while `cutoff = now − 7d` keeps the
  current time of day (`Aug 4 05:47`) and the newest series point sits at `Aug 4 00:00` — so the only in-window point is filtered out. It is not really an
  off-by-one: **any range containing no weigh-in blanks the chart**, so a weekly weigher's `1W` is dead permanently. iOS is the mirror image and says so in
  its own words — `WeightChartView.swift:18-22`: *"`rangeStart` **no longer filters the data**; it sets the initial visible WINDOW"* — plots the full series,
  floors the window at `max(7 * 86_400, …)` (`:69-73`), and pins `.frame(height: 340)` at the mount so the chart cannot vanish. **"No longer" is the tell:
  iOS shipped this bug, fixed it by splitting plot-data from visible-window, and Android is still in the pre-fix state** — the same shape scout #20 found for
  #1212. Filed **#1220 (P1)**, which also captures the second-order loss: iOS's chip is a zoom you can pan inside, and `WeightChartAndroid` is a static Path
  with no gesture at all, so hard-filtering leaves no route to the data outside the window. Second issue **#1221 (P1)**: the history list is a flat
  `2026-08-04 · 178.8 lbs · 🗑` list where iOS is a **month-grouped log** — `MMMM yyyy` headers with the month's median, weight-primary/date-secondary rows,
  a per-row delta vs the next-older entry (arrow, goal-aware colour, ±0.05 "No Change" band, suppressed past a 90-day gap), a HealthKit heart, dividers, and
  `LazyVStack` rows that #950 made lazy deliberately. Confirmed unowned before filing — #1143 owns the history *disclosure* and the *edit* affordance, and a
  search across open+closed issues for `WeightLogListView` returns nothing that specifies row content. That issue also carries the delete finding, which is
  a **correction to this matrix**: the row said `delete a weigh-in (trash button) | ok`, and the button does work, but iOS has **no delete button at all** —
  it is a `role: .destructive` item inside a `.contextMenu`, so it costs a long-press plus a deliberate selection, where Android is one unconfirmed tap on
  every row of a scrolling list with no undo. Against the "user data is sacred" tenet that is the wrong default and strictly more dangerous than the control
  it stands in for. Issues filed: **2** (#1220, #1221). Commented **3**, each on the issue that already owns the region rather than filing a fourth ticket
  into the same function: **#1143** gains the log sheet's **missing date field** (its body describes iOS's "Weight + Date" but its Done-When omits Date, so
  every Android weigh-in is stamped today and a missed day cannot be back-filled) plus the **`Save` that silently eats the tap** on empty input where iOS
  renders it `.disabled` — with the note that scout #19's #1137 finding (SkipUI *does* honour `.disabled`; it was the binding that went stale) may invalidate
  the #1091 workaround this behaviour rests on. **#1205** gets device confirmation of its CURRENT-card defect plus **one correction**: it recorded the chips
  as "7d -0.2 / 30d -2.8", but today there is **no 7d chip at all** and 30d reads **-1.7** — `change()` returns nil when the newest entry *is* the window
  edge, so the same card prints "7-day change: -0.5lbs" beside a missing 7d chip. It also inherits the composition delta nobody owned: Android adds a
  full-width red button mid-screen that iOS does not have anywhere (iOS's is a toolbar `+`), drops iOS's toolbar back chevron, and renders a LARGE nav title
  where iOS pins `.inline`. **#1204** gains a second confirmed surface — the weight field's stroke turns accent-pink on focus, worse here than on Friends
  because this sheet's Save really does reject empty input silently, so the pink outline reads as the field being at fault; two surfaces now argue for fixing
  it at the shared `NumericField` layer. Rows changed: **26** (11 repointed off the CLOSED #1142/#1144/#1145 — the board had been aiming the executor at dead
  tickets for a week — 12 added, 3 flipped from `ok` on device evidence). Deliberately did **not** file the most tempting visual lead: the chart's green Trend
  line runs consistently *above* every grey scale point, but Android builds it from the full 365-day history before windowing (`:86-88`), so it is a lagging
  EMA over a declining series and **not** the windowed-EMA-reseed bug iOS documents fixing — recorded as a verified-clean row so the next scout doesn't chase
  it. Also verified working and recorded so nobody re-tests: 1M/3M/6M/1Y/All windowing (1M → `Jul 13…Aug 4`, average and difference both recompute), the
  decimal keypad on the weight field, typing commit, and comma-decimal handling. No code touched (matrix only). **Residuals:** I did not drive **delete** or
  **save** a weigh-in, by choice — both write to a DB three lanes share, and [[harness_shared_emulator_test_writes_poison_state]] is exactly how #1213's
  phantom `34.64 kg` got into a sibling lane's screenshots; the empty-input Save no-op was safe to test because source proves it cannot write. The **empty
  state** row therefore stays source-derived (reaching it means deleting every weigh-in). And the iPhone simulator **still has no Drift build installed** —
  now four sessions running — so every iOS claim here is source-derived, including #1220's and #1221's; that side-by-side remains the standing debt to
  `0-SCREENSHOT-EXACT-IS-THE-BAR`, and it is worth an operator-facing note that the scout lane has never once been able to satisfy that directive literally.
  Rotation next: **Body/Weight again** — the DEXA (8 rows, all `missing`, no Android route) and progress-photo blocks are still scout-#14 vintage, and
  `More → Progress Photos` is one tap away; then Sharing if #1197's fixture rows have landed.

- **2026-08-11 (scout #21, Opus 5):** **SHARING / SOCIAL** — taken over the rotation's "finish Food" because the executor's uncommitted WIP was
  entirely Food (`DescribeMealSheet`, `FoodLogViewModel`, `PhotoLogResponse`, `PhotoLogEntry`→DriftCore), so a Food sweep would have been graded
  against code about to change under it. Sharing was also the board's largest dark block: **24 `unknown` + 4 `broken` rows, and not one of them
  had ever been driven.** The emulator was free at the start (planner 19s old, executor idle, no Gradle/Kotlin daemon above 0.1% CPU, installed
  build 89). **The headline is that this entire section was resting on a premise that is false, and one `sqlite3` read settled it in a minute:
  `sync_session` holds a real row — `driftoffline`, valid unexpired GoTrue JWT.** Scout #16 read that same table as empty on build 80 and
  concluded "no Android device can ever obtain a sharing identity, every signed-in surface is *unreachable*"; scout #18 corrected the header but
  left all 27 rows pointing at the closed #1194. So the board has been telling three lanes for a week that a working subsystem was dead. Driving
  it confirmed the opposite end to end: the hub renders (identity card, avatar, invite link, privacy footnote), **live debounced friend search
  works** — typing `neha` returned `@neha` with working Add-friend/Coach capsules — and `connections()` *succeeded*, which is provable rather than
  assumed because that one call is deliberately not `try?` (`SharingView:811`), so a failure would have rendered `couldNotLoadCard` instead of the
  empty state. Writes land too: `telemetry_events` holds **2,412 `platform='android'` rows, latest 11:02 UTC today**, which independently kills
  the `Telemetry | broken` row *and* the App-shell row claiming the OkHttp facade is "wired into ONE consumer / POST-only" (`rg URLSession.shared
  DriftCore/Sources` = 3 hits, all in `DriftPlatform.swift`: two doc comments and the seam's own iOS default). Two real defects found. **#1216
  (P1)** is a shell bug the Friends screen merely exposes: Android's IME lifts the floating `PillTabBar` **on top of the keyboard**, so between the
  search field and the lifted bar there is ~28dp where a result row needs ~60 — you type a handle and see nothing until you dismiss the keyboard,
  which defeats the debounce that exists precisely so you don't have to press return (`ContentView.swift:11,50-64`; iOS's `floatingTabBarClearance()`
  is UIKit `additionalSafeAreaInsets` and its keyboard *overlays* the bar). It costs every typing surface in the tab shell ~110dp, not just this one.
  **#1217 (P1)** is a fail-open privacy control: *Findable by search* paints **ON** with "People can find you by @username" for an account whose
  server row is `discoverable = false`, because `@State discoverable = true` (`:53`) is a guess rendered before `discoverable = (await listed) ?? true`
  (`:823`) resolves — and it corrected only after an unrelated keystroke, the #1180 no-repaint-without-a-poke shape. Severity stated honestly in the
  issue: the error points in the *conservative* direction and tapping it still writes what the user meant, so it is a state-correctness bug on a
  settings control, not a leak. Issues filed: **2** (#1216, #1217). Commented **2**: #1204 gains the Friends search field (Material `OutlinedTextField`
  stroke *inside* the `Theme.pillBackground` pill, 56dp floor, stroke turns accent-pink on focus so it reads as a validation error) as another
  instance of its themed fix rather than a duplicate issue; **#1197** gets the thing that was actually blocking it — the 6 never-verified surfaces
  aren't unreachable, **the emulator's identity simply has zero connections**, and every coach/client/friend surface is gated behind having one
  (`SocialPillRow:69`), so "open Friends and look" can never get there. That comment carries a two-row additive INSERT recipe attaching `driftoffline`
  to the existing `driftprobe81` probe account (with its scoped undo, row counts to check, and an explicit "do NOT test against `@ashish`" — the
  operator's real account, 14 friends / 3 trainer edges), which makes the whole block drivable in one session. Rows changed: **41** (27 repointed off
  the closed #1194, 8 flipped `unknown`/`broken`→`ok` with device evidence, 4 added, 2 stale rows outside this section corrected). Deliberately did
  **not** file the most tempting lead: the `Add friend` capsule renders black and `Coach` renders Material-looking indigo, but those are
  `Theme.ink` `#0A0A0A` and `Theme.chartTrend` `#5856D6` set explicitly under `.buttonStyle(.plain)` (`:662-671`) — they match iOS, and it is
  recorded as a verified-clean "do not fix" row so the next scout doesn't chase it. Also did not drive **Sign out**, by choice: it deletes the
  server profile. No code touched (matrix only). **Residuals:** the executor took the emulator mid-sweep (Drift Coach, "log 2 eggs", ~03:54) so the
  #1217 timed-repaint capture and the "does it scroll with the IME up" check for #1216 are both unfinished — each issue says so in its own body
  rather than pretending. And the iPhone simulator **still has no Drift build installed** (now 3 sessions running), so every iOS-side claim here
  remains source-derived; that side-by-side is the standing debt to `0-SCREENSHOT-EXACT-IS-THE-BAR`. Rotation next: **Sharing again** once #1197's
  fixture rows exist (the 6 surfaces are one session's work with them, indefinitely blocked without), then finish Food (edit sheet + search).

- **2026-08-11 (scout #20, Opus 5):** **FOOD TAB** — next in rotation per scout #19, and driven on the device as that note asked. The
  emulator was genuinely free at the start despite both sibling lanes being live (executor PID 43626, planner PID 86908): the launcher was
  foreground, no Gradle/Kotlin daemon was above 0.1% CPU, and — the check that actually decided it — `git diff --stat 2910cead HEAD --
  drift-android/ SharedUI/ DriftCore/` was **empty**, so installed build 87 was byte-identical to HEAD for every file in this section, and
  the executor's only uncommitted work (`ToolRegistry+Execute.swift`, `ToolRegistrationTests.swift`, `DriftAndroidApp.swift` — its #1209 fix)
  touched no Food code. Six sweeps of device-verify debt cleared in about fifteen minutes of driving. **The headline is not a Food bug.**
  Driving the Food tab surfaced a wrong number on the Today card — `Target: eat 2349 kcal/day to **gain 95.6 lbs**` — and pulling the device's
  own storage showed the goal is a *losing* one: `weight_entry` latest **81.1 kg**, `app_pref/drift_weight_goal` = `{target 78.0, start 82.5}`,
  which gives **lose 6.8 lbs, 31% done**. Drift Coach's `weight_info` printed the identical `gain 95.6 lbs … 100% done`, in the same bubble as
  `Rate: -0.2lbs/week (losing)`. Two independent surfaces — one an Android-only file, one shared DriftCore — producing the *same* wrong number
  means a shared bad input, and solving the three outputs backwards pins it exactly: `|78.0 − cw| = 43.36 kg` plus a "gain" direction forces
  **`cw ≈ 34.64 kg`**, and `(34.64−82.5)/(78−82.5) = 10.6 ≥ 1` is precisely why `progress()` returns 100% (`WeightGoal.swift:277`). 34.64 kg
  matches **no row** in the table (range 80.94–82.56), so it is not a row-ordering pick. Filed **#1213 (P0)** evidence-first with the root cause
  *left open* and a device-diagnostic as step one, rather than guessing — the honest state is that source reading could not explain 34.64.
  Hunting it did, however, turn up a defect that IS fully provable without the device, and it is the **#1209 pattern again**: `DriftAndroidApp`
  never calls `WeightTrendService.shared.refresh()` or `TDEEEstimator.shared.refresh()`, both of which iOS runs at launch (`DriftApp.swift:228`,
  `:233`). The clincher is iOS's own comment there — *"Was previously initialized lazily by Dashboard's onAppear — non-Dashboard launch paths got
  stale values"* — **iOS had this exact bug and fixed it by hoisting the refresh to launch; Android is still in the pre-fix state**, its only
  refresh being a side effect of `TodayTab.swift:103`, the Dashboard equivalent. `TDEEEstimator.refresh()` is called *nowhere* on the platform,
  and three consumers read `TDEEEstimator.shared.current?.tdee ?? 2000` (`FoodService:374`, `:794`, `AIRuleEngine:182`), so any launch that does
  not pass through Today computes food targets and AI reasoning on a flat 2000 kcal. `cachedOrSync()` is not a rescue — `:293` reads the same
  unrefreshed `latestWeightKg`. A prior session already hit this and patched it *locally in one screen* (`TodayTab.swift:96-102` carries the
  post-mortem comment), which is why it survived. Filed **#1212 (P0)**, one file, iOS-risk-free. Issues filed: **2** (#1212, #1213, cross-linked
  so the planner can merge if #1212's fix resolves #1213). Rows changed: **17** (9 added, 5 unknown→verified, 1 stale row corrected, 2
  false-positive guards). Also commented **#1129**, whose premise is stale: the matrix and the issue both said the Daily Average card was
  *missing*, and it **ships** (`TodayTab.swift:455-480`) — screenshotted rendering eating/deficit/burning; an executor would have re-ported a
  card that already exists. Deliberately did **not** file three tempting leads that source disproved, all recorded as verified-clean rows so the
  next scout doesn't re-chase them: the "Seed sample data" button in the empty diary is `#if DEBUG` (`:1205-1213`) and correctly absent from
  release; the dot under today with an empty diary is the today-marker, not a false logged-dot (`dayDotColor` `:545-547`); and the fractional
  "3.8/30 plants" with "+6 new today" exceeding it is intentional shared formatting (`:625` selects `%.1f`; the two figures are a weighted score
  and a species count). One real Food finding to correct the record: the matrix called the quick-log confirmation a "toast **undo**" — there is no
  Undo action in it on either platform, just a 2s capsule. Verified working, along with the chip write path, the macro card, the meal timeline,
  the date strip and the consistency heatmap. Its **paint latency** is the #1180 mechanism again: at +0s after the tap there was no toast, no row
  and no macro change; all three appeared together by +1s, i.e. the synchronous `@State` write schedules no recomposition and the repaint rides
  the async `reload()`. No code touched (matrix only). **Residuals:** the executor took the emulator mid-sweep (Health Connect permission grants
  at 00:28, its #1207 work), so **#1120's edit-sheet override fields and the search stand-in (#1193) were not driven** — they stay the top of the
  next Food sweep, along with the Select Date sheet and the sort-chip row. And the iPhone simulator still has **no Drift build installed**, so
  #1213's iOS scope is unresolved; that side-by-side is now blocking a P0, not just owed. Rotation next: **finish Food** (edit sheet + search),
  then Body/Weight.

- **2026-08-10 (scout #19, Opus 5):** **COACH / AI CHAT (#1066)** — next in rotation, last swept 07-28, and the **first device-driven sweep in ten
  sessions**. The device debt broke on a technicality worth recording: both sibling lanes were live (executor PID 53813, planner PID 54136) so
  [[harness_parity_lanes_share_one_emulator]] would normally mean hands-off — but they had started **60 seconds earlier** (22:15) and
  `git diff --stat e3a952b6 HEAD` showed the entire build-85→HEAD Android delta to be `SnapMealSheet`/`TodayTab`/`Symbols`/`Skip.env`, i.e. **zero
  Coach files**. The installed APK was therefore byte-equivalent to HEAD for everything in this section, and the executor was still reading, not
  installing. Nine prior sweeps deferred on a rule that, checked rather than assumed, didn't bind. **The headline is a P0 that source-reading alone
  had missed for three months and that device-driving found in four turns: Drift Coach on Android cannot execute a single tool.** Every query —
  typed text, and the app's *own* "Weekly summary" suggestion pill, twice — returns the identical canned string *"I'm here. Ask me about your food,
  weight, sleep, or workouts…"*. That string is `AIToolAgent.swift:809-812`, reachable **only** when `ToolRegistry` reports `unknown tool`, and it
  returns `didFail: false` so nothing anywhere flags it — it reads as the Coach choosing to be vague. Cause: `ToolRegistration.registerAll()` has
  exactly three call sites — `Drift/DriftApp.swift:38` (iOS), `DriftChatSim/Entry.swift:32` (CLI), and **nothing in `drift-android/Sources/`**
  (`rg` returns zero hits), while `DriftAndroidApp.swift` wires five `DriftPlatform` seams (`:41-55`) and `LocalAIService.swift:81` documents the
  contract it skipped. Confirmed non-lazy before filing: `ToolRegistry.shared` is `private init() {}` over an empty dict (`ToolSchema.swift:128-136`).
  **One missing line has disabled the showstopper surface on the whole platform** — filed **#1209 (P0)**. It also **reorders the board**: #1135 blames
  the `#if DRIFT_IOS_APP` review sheets for food-logging degradation, but that gate is downstream — the tool never runs, so wiring the review path
  first would change nothing observable. **Two `planned` issues were knocked back to `needs-plan` because their specs would have shipped no-ops.**
  **#1137** (send button) says "dead tap target … add `.contentShape(Rectangle())`"; the a11y tree with *"protein" visibly in the field* reports
  `clickable="true" enabled="false"` — the click modifier IS registered and SkipUI is honoring `.disabled(!canSend)` (`InputBar:166`) because
  `canSend` (`:159`) never re-evaluates while the keyboard is up. One back-press, **same field text**, flips it to `enabled="true"` and the tap sends.
  A contentShape on a disabled control is a no-op; the button is disabled precisely when a user would reach for it, and IME `.onSubmit` works only
  because it carries no `.disabled` guard. **#1180** describes an indefinite hang on "Looking that up…" via a MainActor-continuation theory; that
  symptom is **gone** (replies in ~2s, `via Nebius`, logcat `⏱ classify: 1481–3002ms` ×4) and the residue is narrower *and* broader than the plan
  says — the **user's own bubble** doesn't paint either. Two pill taps looked stone dead at +4s (no bubble, no dots, no reply); typing something
  unrelated then painted **both** queued turns at once. Since `AIChatView.swift:475-477` writes `vm.inputText` and calls `sendMessage()`
  synchronously, the un-painted user bubble proves the miss happens **before any await** — a plain `@Observable` write from a `Button` action fails
  to recompose, no actor hop involved — which is a ~1s repro instead of a 36s one. IME submit only *looks* fine because dismissing the keyboard is
  itself a free recomposition poke; every entry point that keeps the keyboard up (pills, send button) looks dead. That single mechanism unifies
  #1137 + #1180 + the "Suggestions row | ok" row, which device evidence flips to `broken`. Third issue **#1210** (P2): the send glyph is a **paper
  plane** where iOS is a filled `arrow.up.circle.fill` (`Symbols.swift:110`; device `content-desc="paperplane.fill"`) — a *different object*, which
  is the substitution that same file's own comments reject for `dumbbell`/`flame`/`sparkles`/`timer`, each given a `Shape` instead. Issues filed:
  **3** (#1209 P0, #1210 P2, plus 2 corrected back to `needs-plan`). Rows changed: **16** (7 corrected from source-true/device-false, 5 added, 2
  status flips, 2 verified-clean). Deliberately **did not** file two tempting leads: the greeting appearing as both hero and first bubble is
  *shared* by design (`AIChatView.swift:412-414` — "appended as a message in onAppear"), and the chat re-opening scrolled to the **top** is almost
  certainly shared too — the scroll block (`:97-112`) fires only `.onChange(of: messages.count)` on **both** platforms with no `onAppear`
  scroll-to-bottom, so it needs an iOS side-by-side before anyone calls it Android-only; recorded as an `unknown` row rather than a fabricated
  deviation. No code touched (matrix only). **Residual:** the iPhone simulator has **no Drift build installed** (`simctl listapps` shows none) and
  installing one means an `xcodebuild` that would race the executor's ([[harness_android_build_oom_kill_daemons_first]]), so every iOS-side claim
  here is source-derived — a genuine screenshot-exact side-by-side of the Coach input bar still owes the operator a run. Rotation next: **Food tab**
  (#1138/#1139/#1140/#1193) — and it should be device-driven, now that the ten-sweep source-only streak is broken.

- **2026-08-04 (scout #18, Opus 5):** **MORE / SETTINGS (#1067)** — next in rotation and the largest untouched block (44 `missing` rows),
  last enumerated by scout #5 on **2026-07-27**. Both sibling lanes live (executor PID 89218, planner PID 74139) and a zero-interference
  `screencap` showed the executor holding the app on the **Body/Weight** tab mid-drive, so per [[harness_parity_lanes_share_one_emulator]]
  the emulator was left alone — **9th consecutive source-only sweep**, and the device debt is now the board's biggest structural weakness.
  **The headline: the two issues that gate this entire 44-row block, #1114 and #1115, were both sitting in `planned` with specs that would
  have made an executor ship regressions.** `MoreTabView.swift` moved 6× in the 8 days since enumeration (1116 ln now, not the ~1025 the
  rows assume), and every delta landed inside those specs. #1114 told the executor to build **(a)** a `Cycle → CycleView` row iOS *deleted*
  2026-07-28 (`b8b14696`, `:29-32` "keep the first impression light for new users"), **(b)** a footer "Report a bug" **external Link** that
  iOS replaced 2026-08-02 with an in-app `SupportView` precisely *because* the external link was the bug ("`support_tickets` had zero rows
  from either platform, which is what a feedback path nobody can complete looks like") — and Android already has the correct in-app form —
  and **(c)** a HEALTH/APP-only section list that omits the **SOCIAL** section iOS added 2026-07-30, which Android *already ships*, so a
  literal port would have deleted working code. #1115 was worse in kind: it points at **`UsageInsightsView`** twice, including an exact
  line range to "fold in here", and that struct **does not exist anywhere in the repo** — deleted 2026-07-28 for `TelemetrySettingsView`,
  whose own doc comment explains the counters "never answered what real users reach for". An executor would have reconstructed a deleted
  screen from the issue text. Both knocked back to **`needs-plan`** with corrected scope commented. The sharpest consequence found:
  #1114's "90-line stub … retires when this lands" is now false (**194 ln**) and retiring it as written **deletes the only opt-out for a
  live cloud telemetry pipeline** (`MoreTab.swift:46-68`; telemetry really is running — `DriftAndroidApp.swift:66-67,93,98`), because iOS
  homes those toggles behind a Settings screen Android doesn't have yet — a privacy-tenet break disguised as cleanup. Issues filed: **2**.
  **#1207** P1 — the More tab's Health Connect button is `broken`, not merely thin: `HealthConnectFacade.kt:92-94` is a fire-and-forget
  `permissionLauncher.launch()`, so `MoreTab.swift:83`'s `syncWeight()` races the grant dialog, reads nothing, returns 0, and has both its
  result and its error discarded (`_ = try?`) — **the first tap after a fresh install can never import anything and never says so**; iOS's
  counterpart (`:272-305`) is a `do/catch` with four distinct status strings and a 3s auto-clear. Plus no `availabilityStatus()` gate
  (states 0 and 2 both render a promise the device can't keep, [[android_hide_unwired_integration_ui]]) and it uses anchor-based
  `syncWeight()` where iOS deliberately uses `fullResyncWeight()` ("the buried Full Re-sync was the only escape from a poisoned anchor").
  **#1208** P2 — **Body Rhythm / `SleepRecoveryView` (589 ln), the first row of iOS's HEALTH section, had no scoped issue at all**: #1068
  scopes only Biomarkers/Glucose/Cycle/Supplements, and the matrix mis-routed it to **#1061, the Today epic**, purely because the file
  lives in `Drift/Views/Dashboard/` — so the planner has never seen it. Filed with its two real blockers named up front (Charts absent on
  Fuse → the `Path` treatment already precedented by `BriefingTrendChart`/#1190; HRV+RHR reads absent from the facade → consume #1176,
  don't duplicate). Also commented **#1124** (Cycle) — with its entry point gone from both platforms it would ship an unreachable screen;
  left the groom call to the planner rather than closing it unilaterally. Rows changed: **17** (7 corrected/⚠-flagged, 8 added, 2
  verified-clean). Header corrected too: it claimed Sharing was **"100% non-functional — sign-in parks on the URLSession bridge (#1194,
  P0)"**, but **#1194 is CLOSED** and `SyncClient.swift:40` now defaults to `DriftPlatform.httpSession` — scout #16's parking verdict was
  overturned, so those 33 rows are *untested*, not unreachable, and #1197 is the pass that clears them. Deliberately did **not** file two
  leads that source disproved: the More toggles persist correctly (`Preferences` uses `keyValueStore`, not UserDefaults — #1108 holds) and
  all 53 `SharedUICopy/` files are byte-identical to `SharedUI/` right now; both recorded as verified-clean rows. Also checked and covered
  elsewhere: no Android-only view sets `navigationBarTitleDisplayMode` at all (0 hits), but #1200 already scopes this systemically across
  21 shared call sites — widened the matrix row instead of filing a duplicate. No code touched (matrix only). **Residual device debt:**
  every ⚠ row above is source-verified only; #1207's first-tap failure in particular wants an on-device run that also checks whether the
  permission ask still spawns the duplicate MainActivity of [[harness_skip_permission_relaunches_mainactivity]] (#1096). Rotation next:
  **Coach / AI chat** (#1066) — 39 rows, last swept 07-28, and four of its children (#1180, #1137, #1174, #1135) have moved since.

- **2026-08-04 (scout #17, Opus 5):** **TODAY (#1061)** — next in rotation (scout #16 deferred it for Sharing) and independently
  the right pick: `TodayTab.swift` (8 touches) and `DashboardView.swift` (6) are the most-churned Today-area files since the
  section was enumerated on 07-28, so the rows were 7 days behind the code. Both sibling lanes live (executor PID 33400 with two
  Gradle/Kotlin daemons up, APK reinstalled 04:54; planner PID 64574), so per [[harness_parity_lanes_share_one_emulator]] the
  emulator was left alone — **8th consecutive source-only sweep**. **The headline is that this section had rotted in a way that
  was costing the other lanes work, not just going stale.** #1131 was sitting in `planned` with a Done-When requiring the
  "dot-rail visual" — iOS **deleted** the dot-rail in the 2026-05-24 density pass (`MealTimelineSection.swift:34-42`: "the gutter
  was visual noise that didn't earn its space"), so an executor satisfying that criterion would have *built a new P1 deviation
  while closing a P2*. Commented the corrected scope, retitled, and knocked it back to `needs-plan`. Same class of rot in two
  more rows: **Log methods** was a FALSE deviation ("iOS = Snap·**Voice**·Search·Recent") — `LogMethodCard` has exactly four
  cases and none is Voice (`LogMethodCardsRow.swift:87-88`, `:12` "#935 merged the old Voice/Text pair"), so Android already
  matches and the row's pointer at #1126 was noise; and the **Body summary row** filed all three columns under **#1070
  (Health Connect adapter)**, which hid a portable-now fix behind a seam that doesn't exist — SLEEP/READINESS do need #1070,
  but WEIGHT needs nothing (`TodayTab.swift:74` *already* calls `WeightTrendService.shared.trendWeight`; `weeklyRate` is its
  sibling property). Issues filed: **3**, all P1, all Android-only files with zero iOS risk — **#1201** meal list renders the raw
  `ORDER BY fe.logged_at DESC` (`AppDatabase.swift:304`) where iOS re-sorts ascending (`MealTimelineSection.swift:370-379`), so
  breakfast sits at opposite ends of the card on the two platforms (one-line fix, deliberately NOT folded into #1131 so it isn't
  blocked behind a multi-part port); **#1202** Today has no reload throttle where iOS skips loads under 30s fresh and explicitly
  deleted its duplicate `onAppear` load for this exact reason (`DashboardView.swift:336-352`) — and each unthrottled reload
  fetches **500 workouts twice** (`workoutStreak()` is `weeklyWorkoutCounts(weeks: 52)`, both hitting `fetchWorkouts(limit: 500)`)
  plus reads and sorts the **entire weight table** to display one number (`getHistory(days: 365)` returns everything unfiltered),
  in bare uncancellable `Task`s that can overlap; **#1203** the WEIGHT stat drops both the weekly-rate line and the goal-aware
  green/red, rendering every direction in the same fixed coral — a design-tenet-#3 violation. Rows changed: **21** (3 corrected,
  2 split/rerouted, 16 added incl. the section's first-ever SPEED block). Deliberately **did not** file two plausible-looking
  leads that source disproved, rather than pad the count: Android's meal-row kcal (`Int(e.calories * e.servings)`) is *exactly*
  iOS's `totalCalories`, and the "% of goal" chip on a goal-less install is backed by a real TDEE fallback with a 1200 floor
  (`FoodService.swift:369-377`), not an invented target — both recorded as verified-clean rows so the next scout doesn't re-chase
  them. Also checked and clean: `DateFormatters.shortTime` IS zone-pinned (`:73-78`), so the [[android_foundation_utc_dateformatter]]
  class of bug is genuinely closed here, and the main `loggedAt` writer is non-fractional ISO (`FoodLogViewModel.swift:295`) so
  Android's narrower parse chain still resolves it. No code touched (matrix only). **Residual device debt:** every SPEED row
  above wants a Pixel-2 confirmation the emulator can't give ([[infra_android_emulator_swiftshader_gpu]], directive
  0-EMULATOR-GPU-CAVEAT) — judge #1202 structurally, not on framestats. Rotation next: **More / Settings** (44 `missing` rows,
  the largest untouched block on the board).

- **2026-08-04 (scout #16, Opus 5):** **SHARING / SOCIAL — an entire feature area with ZERO matrix rows.** Rotation
  said Today next, but a staleness check first (which iOS files moved since the last sweep) showed the social cluster
  was the single fastest-moving area of the week — ~100 file-touches since 07-28 — and `grep -c 'Sharing'
  PARITY-MATRIX.md` returned **0**. ~4.6k lines across 21 SharedUI files, all compiled into the Android APK, all
  reachable (`MoreTab:141` → `SharingView()`, `TodayTab:159` → `SocialPillRow()`), none ever enumerated. The cause is
  identifiable: operator directive **`0-SHARING-DONE`** ("shipped + hardened, Android 63 — DO NOT re-port/re-plan it;
  only a REAL tester-found bug") steered every lane away, so nobody looked. Both sibling lanes live (executor PID 6458
  mid-`skip app launch`, reinstalled build 80 at 03:19 and was driving the app; planner PID 33593), so per
  [[harness_parity_lanes_share_one_emulator]] **no UI driving** — 7th consecutive scout carrying device debt.
  **The headline: this is that real tester-found bug, and it is a P0.** Scout #15 left the sharing contradiction as
  the top open question and the #1194 planner plan made it "Step 0 — settle on-device, the scout couldn't run this".
  I settled it *without* the emulator, from the source chain plus read-only device state: `SyncClient:40` binds
  `URLSession.shared` and all three construction sites take the default (`SharingService:18`, `SupportService:80`,
  `TelemetryService:25`); every REST **and** GoTrue-auth call funnels through the one `send()` → `session.data(for:)`
  (`:88,119,213`); on Skip that is the swift-corelibs bridge at `RemoteLLMBackend:17-31` which
  `AndroidHTTPSession.swift`'s own shipped comment says "parks non-cancellably… its completion handler never fires".
  So `signInAnonymously()` → `authPost("signup")` parks and **no Android device can ever obtain a sharing identity** —
  no error, no timeout (a `timeoutInterval` can't rescue a handler that never fires). Device corroboration, zero
  interference, via `adb shell run-as … sqlite3 -readonly`: `sync_session`/`sync_map` exist (v47 ran) and
  `sync_session` holds **zero rows** after days of launches; `org.swift.foundation.URLCache` empty. Friends, coaches,
  chat, leaderboards, public profiles, template sharing — plus More → **Report a bug** (`SupportService:80`) and the
  telemetry opt-in the `MoreTab:61` toggle promises — have never worked on Android. **`0-SHARING-DONE` is materially
  false for Android**; directives file is operator-owned so it was NOT edited — operator call flagged here and on
  #1197 (suggest narrowing it to "don't re-port the *iOS* sharing UI"). Precision note: the failure is graceful, not a
  hang — `connections()` → `requireUserID()` throws `.notSignedIn` fast, so `SocialPillRow` correctly shows its invite
  pill and Today does not spin; only the claim-username gateway parks. **#1194 escalated P1 → P0** + the settled
  Step-0 verdict commented, including one Done-when addition the plan needs: acceptance must **start from username
  claim** (every Android install has an empty `sync_session`), because verifying a populated hub would skip the exact
  call that parks. Rows changed: **34** (new Sharing/Social section, 0 → 33 rows + section header). Issues filed:
  **2** — **#1196** P1 (three username fields lose `.textInputAutocapitalization(.never)`, `FriendSharePicker` also
  loses autocorrect-off; filed as *cosmetic* after verifying `normalizedUsername:146` lowercases and
  `searchUsers:110` lowercases + uses `ilike`, so nothing functional breaks — the honest call, not a padded P0) and
  **#1197** P1 (the 6 surfaces created 07-28→07-30, ~1,893 ln, that post-date the hardening pass and carry **no**
  `os(Android)` gates: CoachBriefingView 574, PublicProfileSheet 342, CoachPageView 189, FocusedSocialViews 136,
  CoachMeView 474, BriefingSnapshot 178 — explicitly blocked on #1194 except `CoachMeView`, drivable today via
  `WorkoutView:510`). Deliberately only 2 issues against a budget of 8: with the gateway dead, more would be
  speculation about screens no one can reach. Also verified clean and NOT worth filing — the cluster is unusually
  Skip-aware (`TextField(axis:)`/`lineLimit(4)` correctly `#if os(Android)`-gated at `CoachSharingCard:291`,
  `BriefingTrendChart:527` uses GeometryReader+`Path` not the absent `Charts`, no `contextMenu`/`swipeActions`
  anywhere, "not private — Fuse can't bridge private @State" notes throughout, `SocialPillRow`'s zero-height
  `Color.clear` load anchor). No code touched (matrix only). **Residual device debt:** every `unknown` row above —
  and the one row a scout could clear today without #1194 is `CoachMeView` via the Workout tab.

- **2026-08-04 (scout #15, Opus 5):** **FOOD (#1062)** — next in rotation and 7 days stale (last swept by scout
  #9 on 07-28). Sibling lanes BOTH live (executor `/android-parity` PID 33952 on #1180 mid-build-loop, planner PID
  7226); executor had reinstalled the APK 4 min before I started, so per [[harness_parity_lanes_share_one_emulator]]
  the emulator was left untouched — **source sweep**, 6th consecutive scout carrying device debt. Two findings that
  change what the queue is worth doing:
  **(1) #1193 P1 — Android food search runs a different, weaker code path than iPhone.** `FoodTab.swift:184` calls
  raw `AppDatabase.searchFoods` (prefix-then-ALPHABETICAL, one LIKE) where iOS calls `FoodService.searchFood`
  (spell-correct -> synonym expansion -> `searchFoodsRanked` exact/prefix/phrase tiers -> `food_usage` personal rank
  -> time-of-day boost -> `trackSearchMiss`). The synonym table it skips is `SpellCorrectService.swift:86,137,155`
  — `curd`/`dahi`/`raita`/`thayir` -> yogurt, `kozhi` -> chicken — i.e. **the Indian-food-first tenet is the exact
  thing Android drops**: typing `curd` returns nothing because no row is *named* curd. Also silently reintroduces
  the #930 "Egg Curry outranks Egg" class that iOS explicitly fixed. `SpellCorrectService` is pure `import
  Foundation` in DriftCore and already compiles for Android — the tactical fix is ONE line, and #1138's port
  subsumes it anyway (the ported file calls `FoodService.searchFood` itself), so this shouldn't wait behind a P2.
  **(2) #1194 P1 — #1136 built the OkHttp seam, wired ONE consumer, and closed.** `DriftPlatform.httpSession` is
  referenced exactly once in the codebase (`LocalAIService:329`). `SyncClient:40` (Supabase sharing + telemetry +
  support — no call site injects the seam), `OpenFoodFactsService:66,147` (online search AND barcode lookup),
  `USDAFoodService:78`, `WebSearchTool:78,120,160`, `FetchURLTool:32`, `ElevenLabsTTSClient:97` and
  `AIModelManager:150-157` all still take `URLSession.shared` -> the completion-handler bridge at
  `RemoteLLMBackend:17-31` that #1136 proved parks non-cancellably on Skip. **And the seam can't simply be pointed
  at:** `HTTPFacadeCodec.encodeRequest:17-27` drops `request.httpMethod` entirely and `HttpFacade.kt:39` hardcodes
  `.post(body)`, so every GET (OFF/USDA/web tools) and PATCH/DELETE (PostgREST) would go out as a POST. Filed with
  the sharing contradiction called out explicitly as **step 1** (0-SHARING-DONE says Android sharing shipped
  hardened, yet by source it rides the parking bridge — one of those is wrong; settle it on-device before assuming,
  and if sharing does spin this is a P0, not a P1).
  **Staleness caught:** the four Food children (#1138-#1141) and #1138's planner plan (2026-07-29) all predate
  `bab6b201` (07-30, Scan folded into the search FIELD + chips cut 4->3 to Saved/Build/Custom + every string
  standardized on "Meal"), `fdc49f9e` (07-30, `MealTimePicker` replaced the bare DatePicker in ManualFoodEntry +
  QuickAdd) and `e9b4d5cf` (07-31, LogMealSheet `Done` removed). An executor following the plan verbatim ships the
  pre-refactor layout — commented onto #1138 + #1139 rather than filing duplicates (0-PLANNER-GROOMS-THE-BOARD
  wants consolidation, not more issues). Rows changed: **51** (Food 25 -> 76: the 1021-line FoodSearchView went
  from ONE coarse row to 34, plus new #1139/#1140/residual sub-sections; +1 App-shell transport row). Issues filed:
  **2** (#1193, #1194 — both `needs-plan`). Issues commented: **2**. No code touched (matrix only). **Residual
  device debt** (unchanged, now 6 sessions): every Food `unknown` row — date strip/calendar sheet, rings, timeline,
  edit-sheet serving input, keyboard + scroll-dismiss behaviour — plus first-hand confirmation of the #1193 repro
  (`curd` returns nothing) and whether Supabase traffic actually completes on Android (#1194 step 1).

- **2026-08-03 (scout #14, Opus 5):** **BODY COMPOSITION (#1069)** — the coarsest node left on the
  board, and the one scout #12 named as remaining. It was two matrix rows standing in for ~1,750 lines
  of iOS source across 6 files (`Drift/Views/BodyComposition/**`), and — the finding that mattered most —
  **#1069 carried only the `android-parity` label, no `needs-plan`, so the planner lane could not see it
  at all.** An entire feature area was invisible to the pipeline. Now decomposed into 7 scoped children
  on the #1114–#1119 / #1142–#1145 pattern. **Cost-changing structural finding:** the whole DEXA +
  measurement-analysis data layer is *already in DriftCore and compiles for Android today*
  (`Models/DEXAScan`, `Models/DEXARegion`, `Domain/Health/DEXAService`, `BodyCompositionAnalysis`,
  `BodyMeasurementAnalysis`, and `AppDatabase.fetchProgressEntries()` public at
  `AppDatabase+Progress.swift:113`) — #1185 and #1189 are pure view ports with zero seam work; only PDF
  import (#1191) is genuinely blocked (PDFKit is iOS-only *and* it needs the #1175 file-in seam).
  **Device window opened mid-session** (executor's `xcodebuild test` finished, emulator-5554 came up) so
  the 5-session device-verify debt was partly discharged — first scout device drive since #12. Confirmed
  on build 79: the progress-photo thumbnail is a **DEAD TAP** (screen pixel-identical before/after —
  #1187, the whole viewer/compare payoff surface is unreachable), cards render **raw ISO `2026-07-30`**
  instead of `Jul 30, 2026`, no weight, no measurement line, a single lonely thumb instead of 4 pose
  slots, `lock.fill` for `lock.shield.fill`, bare `+` for `plus.circle.fill`. Zero crashes across the
  drive (0-NO-CRASH clean); emulator restored to the More tab as found. **Device-only find** the source
  sweep would have missed: the More tab's "COMING TO ANDROID" card is a hardcoded string array
  advertising **already-shipped** Coach chat and photo logging as unshipped — a floating Coach button
  sits one card below the text saying Coach is coming (#1192). Rows changed: **27** (2 coarse rows →
  25 enumerated across two new sub-sections + 1 More row + section header). Issues filed: **8** (#1185
  DEXA screen+manual entry, #1186 P1 gallery data defects, #1187 P1 dead-tap viewer, #1188 gallery
  structure, #1189 Trends sheet, #1190 DEXA charts, #1191 blocked PDF import, #1192 stale COMING card) —
  at budget, all `needs-plan`. #1069 commented as an INDEX with a suggested sequencing. No code touched
  (matrix only). **Residual device debt:** the ≥2-entry states (timeline scrubber, Compare/Trends row)
  and the metric-unit + measurement-only-entry cases in #1186 need seeded fixtures — Android has no UI
  to create them until #1166.

- **2026-08-03 (executor, Sonnet), #1111:** Shipped Snap meal photo logging shell — completed WIP inherited from an earlier watchdog-restarted executor session on this same ticket (`NebiusMealPhotoLogger.swift` + Tier-0 tests + `CameraCaptureFacade.kt` + manifest/`Main.kt` wiring were already present, uncommitted). Added: FileProvider `<provider>` block + `res/xml/file_paths.xml` (was MISSING — `CameraCaptureFacade.launch()` would have crashed with `IllegalArgumentException` on the first "Take Photo" tap, never previously exercised), `CameraCaptureService.swift` (Swift-side facade wrapper mirroring `ImagePickerService.swift`, handles the permission-request→poll→launch→poll→result state machine), `SnapMealSheet.swift` (capture/analyzing/review/error phases, mirrors `DescribeMealSheet`'s review-row style verbatim rather than extracting a shared `MealReviewList` per the plan's speculative File #6 — only 2 occurrences, CLAUDE.md's anti-premature-abstraction tenet, and LAUNCH HARDENING's "no speculative refactors" all argue against touching the already-shipped Describe sheet), `PhotoStackShape` drawn glyph (skip-ui has zero `photo.*`/gallery/album SF Symbol mappings at all — checked `composeSymbolName` directly), `TelemetrySurface.snapMeal` constant, TodayTab wiring (Snap chip now opens the real sheet; the `showingCoachInfo`/`AIChatView` placeholder it used to open is DELETED — was 100% dead after the repoint, Coach remains reachable via the floating `ChatIconButton` in `ContentView.swift`). Both capture paths device-verified working end-to-end THROUGH TO THE CLOUD CALL: camera permission prompt → grant → system camera → confirm → app resume (no crash, no duplicate-MainActivity); gallery picker → pick → app resume. 5 rapid background/foreground cycles clean, zero crashes, zero ANRs (0-NO-CRASH). Tier-0 8/8 new + 2686/2686 total green; `android-build-check.sh` green; full iOS suite 1274/1274 green (DriftCore touch is ADD-ONLY, zero iOS behavior change).
  **RESIDUAL — blocks the happy path, filed as #1177 (P1, needs-plan):** the cloud vision round-trip itself returns HTTP 200 with only the first (empty, role-announcement) SSE chunk — 4105 bytes, byte-identical size across two completely different test images — before the connection is cut, so `NebiusMealPhotoLogger.parse` always resolves to nil and the error screen fires (verified working: clean UI, Retry + Retake, no crash). Isolated via a temporary debug capture (added, verified, then fully reverted — `git diff --stat` on the two touched shared files is empty) that a control test (Describe, text-only, same buffered Android transport) succeeds end-to-end on the same build/device, so this is specific to the (slower-to-first-token) vision-call shape, not a general network/config/throttle failure — likely the buffered-path sibling of the exact "idle connection gets reaped" failure class #1133's own code comments already document for the streaming path. Needs real architectural investigation (real-device confirmation beyond the emulator, possibly a `stream:false` request for the buffered path or an OkHttp-Kotlin-facade transport mirroring #1136) — out of scope for a bounded executor session, filed `needs-plan`. Also affects Workout Scan (#1110) once its photo path is device-tested — same shared `RemoteLLMBackend` transport.
  Build: verified via `skip app launch --android` (not yet published — see next session note for the publish outcome). #1100 (Stop-hook lane-scoped skip) also closed this session: fix had already landed (`ff33e89c`) but the issue was never closed — re-verified with a proper decoy-process test (my own self-test hit the documented pgrep ancestor-exclusion caveat) rather than re-implementing.

- **2026-08-03 (scout, Opus):** IMAGE-IN / CAPTURE reconciliation (executor `/android-parity` PID 7297
  Sonnet + planner PID 7330 LIVE on emulator-5554 → Android UNTOUCHED per the scout-#3 collision lesson;
  iPhone sim was uncontended but this was a source + issue-state sweep, no device drive needed). Trigger:
  6 days since scout #12 (2026-07-28) — verify-don't-trust against live `gh`. **Headline: #1128 (image-in
  seam) CLOSED 2026-07-31 (`9aff629f`)** — shipped `DriftPlatform.imagePicker.pickLibraryImage()`
  (`DriftCore/.../Adapters/ImagePicking.swift`), registered on Android (`DriftAndroidApp.swift:53`), wired
  into exactly ONE consumer so far (`ProgressGalleryAndroid.swift:84`). Crucial shape: the seam is
  **photo-LIBRARY only, NOT live camera** — it unblocks Snap-from-library / WorkoutScan-image / Coach
  photo-attach, while barcode + live PhotoLog capture still need a SEPARATE camera seam. This invalidated
  the "blocked on #1128" premise the matrix cited across Food/Today/Coach/Capture + the
  [[project_android_image_in_seam_blocker]] memory (updated this session). **Actions:** (1) filed **#1174
  P1** — Coach input-bar photo-attach, a genuine tracking hole: the `AIChatView+InputBar.swift:121-142`
  comment forward-references #1125 for "photo attach", but **#1125's filed scope is cards + interview
  only** (verified in its body) and #1111 is the Food-tab Snap (a different surface) — so photo-in-chat
  was owned by no issue; now buildable on the landed seam. (2) Refreshed **#1110** (Workout Scan): removed
  stale `blocked` (its #1128 blocker landed → image path buildable now; PDF still #1109-SAF-gated) +
  commented the per-path nuance ([[harness_stale_blocked_label]]). (3) Added a matrix row for **#1137**
  (Coach send button = DEAD TAP, only IME enter sends — `broken`; the old Input-bar row wrongly implied
  "send" worked). Rows changed: **9** (Capture ×4 refined; Coach input-bar repointed #1125→#1174 + NEW
  #1137 send-button row; Food barcode + Snap ×2; Today Snap chip; Progress-photos add-entry; Nav font
  #1165). Issues filed: **1** (#1174). Issues refreshed: **1** (#1110 `blocked` cleared). No code touched
  (matrix only); tree clean, publish lane's `Skip.env` untouched. Confirmed `3b0946cb`'s dashboard
  meal-remove is **iOS-only** (`Drift/Views/MealTimelineSection.swift`) — does NOT close Android #1131;
  iOS pulled slightly further ahead. Device-verify debt unchanged (emulator contended, 4th+ consecutive
  scout) — next uncontended window: the library-seam consumers (#1174/#1111 once built) + the standing
  Food/Coach/Weight `unknown` rows.

- **2026-07-28 (executor, Sonnet), #1100:** Executed #1100's plan exactly: `.claude/hooks/ensure-clean-state.sh`
  now skips the dirty/untracked-file gate for `DRIFT_PARITY_LANE` ∈ {scout, planner} Stop-hook runs when
  `pgrep -f 'android-parity --dangerously'` finds a live executor sibling (the UNPUSHED gate is byte-identical,
  untouched); all three parity watchdogs (`android-parity-watchdog.sh`/`-planner-watchdog.sh`/`-scout-watchdog.sh`)
  now export their own `DRIFT_PARITY_LANE` right after `DRIFT_AUTONOMOUS=1`. Verified all 5 branches with a
  spawned decoy process standing in for "executor sibling live" (see caveat below — NOT this session's own
  PID): `DRIFT_PARITY_LANE=planner`/`scout` + decoy alive → rc=0 (skip fires); `=executor` and no-lane-var
  (iOS autopilot) + decoy alive → rc=2 (full gate kept, unchanged); `planner` with NO decoy alive → rc=2
  (skip does NOT fire when no executor is genuinely live — not a blanket bypass). Discriminator regex
  confirmed via two backgrounded decoys to match an `/android-parity` process and reject an
  `/android-parity-scout` one. **CAVEAT discovered while testing** (also recorded on the scout-deadlock
  memory): macOS `pgrep -f` silently excludes ANY ancestor of the *calling* process from its match set — this
  session's own executor PID (my direct parent, confirmed via `ps -p $PPID`) was invisible to a `pgrep` run
  from a child shell, which would have produced a false-negative on the discriminator test had I not swapped
  to a genuine backgrounded decoy. Irrelevant to production (scout/planner/executor are independent sibling
  process trees spawned by separate watchdogs — never ancestors of each other) but a real trap for future
  self-testing. No Swift/SharedUI/DriftCore touched (infra-only: 2 hook/watchdog dirs + this note), so no
  Android/iOS build or test run required per the plan; `bash -n` clean on all four scripts. Operator must
  restart the three parity watchdogs for the new `export`s to take effect — not done by this session.

- **2026-07-28 (scout #12):** DEVICE-REFERENCE sweep of **Workout** (operator directive 0-SCREEN-BY-SCREEN-WORKOUT).
  ps-check: executor `/android-parity` (PID 62401, Sonnet) LIVE and parked on the ExerciseVoiceLogSheet on
  emulator-5554 device-verifying its own fresh #1106 fix (e979e2c5 / row-487 flip 58a33c43) → the Android emulator
  was left UNTOUCHED per the scout-#3 collision lesson. (adb quirk resolved for the record: the working adb is the
  homebrew one at `/opt/homebrew/bin/adb`; `~/Library/Android/sdk/platform-tools/adb` does NOT exist here — my first
  probes silently no-op'd on the wrong path and looked like a mid-reinstall stall, it wasn't.) iOS control = PAUSE
  (misfiring hook, reads the iOS file only) but `~/drift-android-parity.txt` = RUN → proceeded. **Method:** drove the
  iPhone 17 Pro sim (516EAAC8, uncontended by the Android executor) to capture FRESH references (operator's
  stale-reference concern per 0-RESUME) for 5 workout surfaces — ExerciseDetailView (pose photo + front/back muscle
  diagrams + Chest/barbell/Intermediate chips + primary/secondary), ExerciseBrowserView ("Exercise Database":
  Done + red "+" custom-CTA + search + All/Chest/Back/Legs/Shoulders/Arms/Core chips + pose-thumb rows with red
  muscle-figure + distinct equipment glyphs Barbell/Bands↔/Machine⚙/Dumbbell), Workout root (Start Workout / Coach Me,
  "Scan or Log a Workout" scan-primary card, Log Past Workout, Templates ⋮, Browse Exercises 950+, burn chips, Apple
  Health band, Muscle Recovery), ActiveWorkoutView empty (close-X, title+date+timer, Add Exercise, command strip),
  and the close-confirm dialog (Minimize — resume anytime / Discard workout). **Cross-checked every visible iPhone
  element against the matrix: workout is SATURATED — all tracked as `ok` or an already-filed gap; ZERO new gaps**
  (consistent with scout #11's exhausted source audit). **Verify-don't-trust reconciliation** of all 12 workout-cited
  issues vs live `gh`: fully consistent — #1095/#1096/#1097/#1099/#1102/#1103/#1106/#1108 CLOSED, #1098/#1100/#1107/#1110
  OPEN, every row matches. Noted #1127 (user-facing custom-exercise delete, `needs-fable`, carved from #1107) now
  tracks the delete affordance referenced by the "custom exercise sheet" / "Your Exercises" rows (#1107). Rows changed:
  **0** (executor already flipped #1106 → row 487). Issues filed: **0** (quality>volume — no un-tracked gap exists).
  No code touched (matrix note only); publish-lane `Skip.env` + graphify dirty files left alone. **Device-verify debt**
  (emulator contended for the 3rd+ consecutive scout): the `unknown` rows — ActiveWorkout exercise-row→ExerciseDetail
  nav, ExerciseBrowser custom-CTA sheet, WorkoutDetail swipe-delete / Edit-Set / menu-drive-through — PLUS the
  device-reverify-pending flips (#1103 IME-focus, #1097 numeric select-all). MITIGATION: the EXECUTOR lane is actively
  discharging device-verification (device-verified #1106 + #1102 + #1098 + BodyMap in recent commits), so this debt is
  being worked, not stuck. Next scout: do NOT re-sweep workout source (saturated) — either grab an UNCONTENDED emulator
  window for the `unknown` device-verifies, or rotate to a less-covered area (capture #1063 / DEXA+photos #1069 /
  Supplements remain the coarsest).

- **2026-07-28 (executor, Sonnet):** Executed the `planned` #1106 issue exactly per
  its Opus plan: `SharedUI/ExerciseVoiceLogSheet.swift` `.onDisappear` (line 66) now
  also calls `viewModel.reset()` + clears `draft`/`resolveTarget`, ungated (no-op on
  iOS since its content view + `@State` die on dismiss regardless). New Tier-1
  `DriftTests/ExerciseVoiceLogViewModelTests.swift` pins `reset()` completeness.
  Both builds green (iOS `xcodebuild build` + Android `skip app launch`), full
  iOS suite 1470/1470 passed (verified via `xcresulttool`, not just exit code —
  the tail-piped log truncated the XCTest-style section). Emulator-drove all 7
  plan verification steps + 3 regression guards: fresh reopen after Cancel, no
  accumulation across a second parse, resolve-picker does NOT wipe the
  in-progress session (highest-risk regression, confirmed safe), swipe-to-dismiss
  reopen is fresh, unsubmitted draft clears. Row 459 flipped `deviation`→`ok`.
  Zero crashes/ANRs across the drive + 5 rapid background/foreground cycles.
  Issue closed. **Publish blocked**: `android-publish.sh` failed twice at "Archive
  iOS ipa" with exit 9 (SIGKILL, 2.5s then 45.8s in, zero `.swift error:` lines in
  either export log — matches the known release-archive-OOM signature, not a code
  issue). Killed a stale leftover `xcodebuild test` process and retried once with
  ~2x the free memory (590MB→1.1GB) — still died; stopped retrying per that
  playbook rather than thrash. `Skip.env` reverted both times, no stray
  versionCode bump landed. **Next session should publish first thing** — this fix
  is on `main` (e979e2c5), just not yet on a Play build. Gap-hunt sweep (Today
  tab, rotated off Workout): posted fresh iPhone-vs-Android evidence to #1061 —
  confirms #1129 (Daily Average/Activity/Recovery block, entirely missing on
  Android) and #1130 (proactive "Food logging paused → Ask AI" nudge card,
  missing) with concrete screenshots, plus the still-outstanding directive-8
  brand-mark gap (Android's header still draws the "D" circle stand-in, not the
  real `BrandMark` asset). No new issue filed — existing ones cover it precisely.

- **2026-07-28 (scout #11):** SOURCE-ONLY staleness reconciliation of **Workout** (epic #1064) — operator directive
  0-SCREEN-BY-SCREEN-WORKOUT area. ps-check found BOTH sibling lanes LIVE (executor `/android-parity` PID 19839 Sonnet,
  `.build/skip-export` touched 13:43 = actively building→installing the APK; planner PID 87150 Opus) so the emulator was
  left UNTOUCHED per the scout-#3 collision lesson. iOS control file = PAUSE (the misfiring P0-#1043 + "PAUSE ACTIVE"
  hooks read the iOS control only) but `~/drift-android-parity.txt` = **RUN** → proceeded. **Verify-don't-trust
  staleness sweep:** cross-checked all 68 issue refs in the matrix against live `gh` state — 13 CLOSED. Workout rows
  citing now-closed issues (confirmed closing commits present) FLIPPED: **row 375** resume-banner persistence
  `broken`→`ok` (#1108 f39655f3 durable SQLite KV store), **row 389** set-done IME-focus-theft `deviation`→`ok`
  (#1103 aab2e238), **row 392** numeric select-all `deviation`→`ok` (#1097 066c91bc), **row 402** mid-workout
  process-death session-loss `broken`→`ok` (#1108 f39655f3 — the P0), **row 417** equipment glyph `deviation`→`ok`
  (#1099 f899db8e). The four runtime-behavioral flips (focus/persistence are RUNTIME facts per [Port Kit Stale On
  Wiring Not UI]) are tagged **device-reverify-pending** (emulator contended, not confirmed on-device this session).
  **row 403** (resume drops Previous ghosts, #1098) — blocker #1108 LANDED so the resume path is fully REPLACED +
  now reachable; premise may be stale → left `deviation`, and refreshed #1098: removed its stale `blocked` label
  ([Stale Blocked Label]) + commented it needs a DEVICE re-verify (not planning — the code path it was filed against
  no longer exists). **Source-audit (directive 0 "no ⚠️ triangles"):** read all 114 platform gates + every raw
  `Image(systemName:)` across the 8 workout SharedUI files — glyph parity is CLEAN: every delta is `sym()`-mapped,
  drawn as a custom Shape behind `#if os(Android)` (Dumbbell/Flame/Clock/BarChart), or a deliberate closest-icon;
  ZERO un-handled triangle candidates (the raw literals at WorkoutView 615/624/780/806/985 are the iOS `#else` side
  of handled pairs; `bottomInset` 100-vs-24 is the intentional floating-pill-tab-bar inset). Rows changed: **6**
  (5 flips + 1 note). Issues filed: **0** (no new gaps — quality>volume). Issues refreshed: **1** (#1098 blocked
  cleared). No code touched (matrix only); publish lane's uncommitted `Skip.env` left alone. **Device-verify debt
  handed to the next uncontended scout window:** the 6 `unknown` workout rows — row 400 (ActiveWorkout
  exercise-row→ExerciseDetail nav), 414 (ExerciseBrowser custom-CTA sheet), 427 (WorkoutDetail swipe-delete), 428
  (WorkoutDetail Edit-Set sheet), 429 (WorkoutDetail menu drive-through), 434 (BodyMap tap→recovery-template) — PLUS
  on-device re-confirm of the 5 flips above + #1098's ghost-drop premise on the new keyValueStore resume path.

- **2026-07-28 (scout #10):** SOURCE-ONLY decomposition of **Body / Weight** (epic #1065) — the last coarse
  un-decomposed domain (Today/Food/More/Coach/Health already split by scouts #5-#9). ps-check found BOTH sibling
  lanes live (executor `/android-parity` PID 23525 + planner PID 23540, Opus) and emulator-5554 up but UNTOUCHED
  per the scout-#3 collision lesson (executor reinstalls the APK mid-drive → phantom app-died). Full diff of iOS
  `WeightTabView.swift` (422 ln) + its 6 sub-views (WeightInsightsView 619 / WeightEntryView 127 / WeightLogListView
  154 / BodyCompEntryView 106 / WeightChartView 379 / BodySummaryCardsRow 307) vs Android `WeightTab.swift` (325 ln)
  + `WeightChartAndroid.swift` (269). **Staleness corrections (verify, don't trust the matrix):** `broken #1091`
  (Log Weight save) and `missing #1092` (weight chart) are BOTH **STALE** — #1091 + #1092 are CLOSED; save now
  validates in-action (not `.disabled`, a Fuse-reactivity fix) and `WeightChartAndroid` (Path-based, Charts absent
  on Skip) is wired → flipped both to `ok`. The "Body summary cards row" was **MISFILED** under #1065 —
  `BodySummaryCardsRow` is mounted in `DashboardView` (Today), NOT the Weight tab → reclassified to #1061. **#1065
  demoted to INDEX**, split into 4 scoped `needs-plan` children: **#1142** WeightInsightsView analytics port
  (body-comp cards → metric trend sheets, weekday pattern, weight-changes sparklines — Android has only a thin
  stats header) / **#1143** body-comp entry (Android AddWeightSheet is weight-only; NO body-comp path exists at
  all) / **#1144** edit-a-weigh-in + >10% outlier banner (Android history rows are delete-only, no correction path;
  planner note: iOS exposes Edit via `.contextMenu` which is ABSENT on SkipUI + steals TextField focus → use
  tap-to-edit) / **#1145** residual affordances (Daily/Weekly granularity, collapsible history, milestone
  celebration + haptic, empty state — AH-sync stays hidden till the health seam). All four are DriftCore-portable —
  no health seam, no camera/cloud (unlike #1069 DEXA + progress photos, left un-decomposed this session: capture is
  seam-blocked per the image-in blocker; ProgressGalleryAndroid re-creation already wired). Rows changed:
  Body/Weight 9-coarse → 17-granular. Issues filed: **4** (#1142-#1145). No code touched (matrix only); worker WIP
  + the publish lane's uncommitted `Skip.env` build-63 bump left alone. Device-verify debt grows by the WHOLE Weight
  tab (source-verified only, emulator contended) — still awaiting an uncontended window alongside Food shared
  surfaces + Coach source-rows + scout #3's 5 workout leftovers + Supplements.

- **2026-07-28 (scout #9):** SOURCE-ONLY decomposition of **Food** (epic #1062) — ps-check found BOTH
  sibling lanes live (executor `/android-parity` PID 23525 Sonnet + planner PID 23540 Opus); `adb` showed
  emulator-5554 up but it was left UNTOUCHED per the scout-#3 collision lesson (executor reinstalls the APK
  mid-drive → phantom app-died). Area: Food was the last coarse un-decomposed mega-epic (Today/More/Health/
  Coach already split by scouts #5-#8), is #2 on the operator's 0-AI-FOCUS queue, and its split also unblocks
  Coach **#1135**. Grep-verified all 10 iOS-only `Drift/Views/Food/**` files (FoodSearchView 49KB, QuickAddView
  36KB, CombosView, ComboLogSheet, ManualFoodEntrySheet, FoodLogSheet, LogMealSheet, PlantPointsCardView,
  ServingMultiplierStepper, VoiceLogSheet) have **ZERO** Android presence; Android ships thin stand-ins
  (`FoodTab.swift` AndroidFoodSearchSheet:39 / AndroidRecentMealsSheet:198) + the shared FoodTabView with every
  create/build/combo/goal/confirm path `#if DRIFT_IOS_APP`-gated. **#1062 demoted to INDEX**; split into 4
  scoped children (mirroring #1067→#1114-1119): **#1138** Food Search hub port (FoodSearchView → replace the
  AndroidFoodSearchSheet stand-in; 6 sections + per-result log; #1075 tracks the stand-in returns-nothing
  break) / **#1139** Quick Add + manual entry + recipe builder (no Android manual-add path today) / **#1140**
  Combos & Recipes hub (CombosView + ComboLogSheet CRUD; Android chips log directly, no editor) / **#1141**
  residual iOS-gated affordances (Plant Points expandable detail + "Log Again"). **Staleness corrections
  (verify, don't trust the matrix):** shared FoodTabView surfaces (date strip/rings/timeline/edit/serving)
  are DEVICE-VERIFY DEBT — they compile via the ported ServingInputView/EditFoodEntrySheet/MealCalendarPicker,
  NOT `missing`; the edit-entry row flipped `unknown`→`broken` **#1120** (cal/macro override fields dead to
  tap). Capture rows stay #1063, Snap→#1111, goal→#1117. Rows changed: Food 22-coarse → 25-granular. Issues
  filed: **4** (#1138-#1141). No code touched (matrix only); worker WIP left alone. Device-verify debt grows
  (Food shared surfaces + scout #8's Coach source-rows + scout #3's 5 workout leftovers + Supplements) — all
  awaiting an uncontended emulator window.

- **2026-07-28 (scout #8):** SOURCE-ONLY reconciliation of **Coach / AI chat** (epic #1066) — ps-check found
  BOTH sibling lanes live (executor PID 97569 + planner PID 94850, Opus) and `adb devices` empty, so the
  emulator was untouched per the scout-#3 collision lesson. Area chosen because the matrix said "iOS-only"
  but commit **b8c244a6 shipped the Coach TEXT chat to SharedUI** (#1066) — a stale section on the operator's
  0-AI-FOCUS priority queue. Full diff of `SharedUI/AIChatView*.swift` (+ViewModel +MessageHandling 2024 ln)
  vs the 8 iOS-only `Drift/Views/AI/**` files: **5 coarse rows → 21 granular rows**, ordered to match `body`.
  Reality: the DriftCore message harness runs on Android so DETERMINISTIC tools WORK (weight/activity logs,
  workout start+templates, delete-food, **navigation** — `.navigateToTab` posts immediately, tab-switch works,
  queries) — flipped those rows `ok`/`deviation`. Four gap-classes, all already tracked except one: **(a)** all
  13 tool-result cards are `#if DRIFT_IOS_APP`, text-summary-only on Android → **#1125**; **(b)** every food-logging
  tool DEGRADES to "add it from the Food tab for now" (single-food `handleSingleFoodIntent`→showingFoodSearch,
  usual-meal→showingMealReview, meal-plan, manual, barcode) → filed **#1135** (the one uncovered operator-priority
  gap — food-via-text is the marquee AI interaction; #1063 is capture not chat; precedent `DescribeMealSheet`
  already ported de-risks it); **(c)** voice/mic/talk-mode shimmed off (`CoachVoiceShims`) → **#1126**; **(d)**
  open-ended cloud-LLM turns HANG on "Looking that up…" (streaming buffered `#else` branch) → **#1133** (already
  filed+diagnosed). Interview ("set me up") `#if DRIFT_IOS_APP` → #1125. BackendSelector/AISetup/AIChooser =
  key-UI (#540), marked **ios-only-by-design** (Nebius-only, no key UI per 0-AI-FOCUS); AIChatInsightsView (#261
  local telemetry) + DriftCoachSheet picker-wrapper likewise ios-only-by-design. **#1066 demoted to INDEX**
  (children #1125/#1126/#1133/#1135). Rows changed: 5→21 (Coach section). Issues filed: **1** (#1135). No code
  touched (matrix only); worker WIP left alone. Device-verify debt grows by the Coach rows (source-verified,
  not driven) — still awaiting an uncontended emulator window alongside the food compiled-shared rows + scout
  #3's 5 workout leftovers + Supplements.

- **2026-07-28 (scout #7):** SOURCE-ONLY structural diff of **Today** (epic #1061) — ps-check
  found BOTH sibling lanes live (executor PID 67317 3:37AM + planner PID 72510 3:45AM), emulator
  untouched per the scout-#3 collision lesson. Full `DashboardView.swift` + `DashboardView+Cards.swift`
  → `TodayTab.swift` (410 ln) diff: **9 coarse rows → 25 granular rows**, ordered to match iOS `body`.
  Every gap classified DriftCore-portable-NOW vs health-seam-gated (#1070). Filed **4 scoped
  portable-now ports**: **#1129** Daily Average energy-balance card (`tdeeCard`: eating/deficit/burning
  ring + target line + explainer, all DriftCore) / **#1130** proactive coaching nudge + behavior insights
  (`BehaviorInsightService` = DriftCore; the on-brand coach surface — Ask-AI wires to the already-ported
  floating chat) / **#1131** meal list swipe-to-delete + dot-rail (`MealTimelineSection` — Android
  `mealsCard` has **NO delete**, a real functional gap) / **#1132** weekly Workout Consistency card
  (DriftCore, NOT health-gated). #1061 demoted to INDEX. **Staleness corrections (verify, don't trust
  the matrix):** row `broken #1093` was STALE — **#1093 CLOSED**, Describe/Search/Recent chips work; the
  residual is **Snap** (camera glyph opens Coach chat, not capture → #1063/#1128). Health-seam rows
  (Activity: Active/Steps + AH `workoutCard`; Recovery: sleep/HRV/RHR) stay `missing`→#1070 because Android
  correctly **HIDES** them (no fake zeros, [[android_hide_unwired_integration_ui]]) rather than render empty —
  NOT new ports until the seam lands. Nav-gated deviations point at existing ports (profile nudge→#1116,
  goal card→#1117, tdee nav→#1118, feedback banner→#1114, backup banner→#1094, Voice method→#1126). Confirmed
  the floating Coach button **IS** ported (`ChatIconButton`→AIChatView, AppShell + ContentView) — Coach-entry
  row flipped to `ok`. No code touched (matrix only); worker WIP left alone. Emulator-drive debt unchanged
  (food compiled-shared rows + scout #3's 5 workout leftovers + Supplements device-verify) — still needs an
  uncontended window; the 4 new Today ports are source-verified, not device-verified.

- **2026-07-28 (scout #6):** SOURCE-ONLY sweep — ps-check found BOTH sibling lanes live
  (executor `/android-parity` PID 74920 + planner PID 74936, all started 1:49AM), so the
  emulator was untouched per the scout-#3 collision lesson (executor reinstalls the APK
  mid-drive → phantom app-died). Area: **Health sub-screens (#1068)**, the operator's
  0-EVERY-SCREEN mandate and the last big coarse area after scout #5 did More. Enumerated
  the full iOS tree from source (Biomarkers Tab/Detail/LabReportUpload/Detail 1595 ln,
  GlucoseTabView 517, CycleView 647): **4 coarse rows → 24 granular rows**. Filed 3 scoped
  needs-plan ports: **#1122** Biomarkers (donut/patterns/reports/search/grouped-list/trend +
  lab-OCR seam) / **#1123** Glucose (zone chart + SAF CSV import + HC glucose read) / **#1124**
  Cycle (phase timeline + 2 charts — **HARD-blocked on #1070**: 100% Health-driven,
  empty-state-only until Health Connect grows cycle reads; flagged for planner plan-vs-block).
  **#1068 demoted to INDEX** (comment recorded) so the planner never chews the 4-screen
  ~2,800-line monolith (same as #1067→#1114–1119). **Two staleness corrections (verify,
  don't trust the matrix): Supplements is DONE** — ported to SharedUI + wired `MoreTab:146`,
  was #1068's 4th sub-screen, dropped from the queue (row → ok); **Progress Photos** → deviation
  (`ProgressGalleryAndroid.swift` exists + wired `MoreTab:147` — Android re-creation, not the
  SharedUI port). More-hub HEALTH-rows note refreshed (2 of 7 dests now landed). Portability
  baked into every row: all data/logic services are DriftCore; recurring seams = `Charts`/`Canvas`
  Skip-absent (Path port, precedent `WeightChartAndroid`), `fileImporter`→SAF (#1109), HealthKit
  →Health Connect (#1070); `LabReportOCR` (Vision/PDFKit)→Nebius per 0-AI-LADDER, no key UI. No
  code touched (matrix only); worker WIP tree was clean. Harness: the per-turn iOS `PAUSE` +
  `#1043 P0` hook injections are the parked iOS lane leaking in (parity control=RUN) — false
  stops. Emulator-drive debt unchanged (food compiled-shared rows + scout #3's 5 workout
  leftovers + now Supplements device-verify) — still needs an uncontended window.

- **2026-07-27 (scout #5, Fable):** SOURCE-ONLY sweep #2 — ps-check found BOTH sibling
  lanes live (executor with #1097 WIP on the tree, planner mid-session), so the emulator
  was untouched; picked the operator's 0-EVERY-SCREEN mandate (More tab) over the food
  rotation — More had zero sub-screen rows. Enumerated the ENTIRE iOS More tree from
  source (MoreTabView.swift 1098 lines + 8 Settings/ files, ~3.5k lines): hub (11 nav
  rows), SettingsView (7 sections), NotificationsSettingsView, UsageInsightsView,
  ProfileView, GoalView + GoalSetupView, AlgorithmSettingsView, backup stack, BYOK.
  More section rewritten 8 coarse → 40 granular rows. Filed 6 scoped needs-plan ports:
  **#1114** hub / **#1115** Settings screen / **#1116** Profile / **#1117** Goal+Setup
  (also flips FoodTabView's iOS-gated goal affordances — food rows repointed) /
  **#1118** Algorithm / **#1119** Notifications page + scheduling seam (the one real
  architecture decision). **#1067 demoted to INDEX (needs-plan removed)** so the planner
  never chews the 3.5k-line monolith in one pass. Policy calls baked into rows: BYOK
  screen + WebSearchSettingsCard = ios-only-by-design (0-AI-FOCUS bans ALL key-entry UI
  on Android); hub HEALTH rows stay hidden until #1068/#1069 destinations land (no dead
  taps, #1093 lesson); every "persists across relaunch" acceptance inherits #1108.
  Portability verified from source: TDEEEstimator / WeightGoal / WeightTrendCalculator /
  ChatTelemetryService / FeatureUsage are all DriftCore; goal flow is Chart-free
  (GoalView's `import Charts` is vestigial); iOS-only deps = NotificationService
  (→ #1119 seam), BackupService (→ #1094/#1109), AIChatInsightsView (hide link),
  HealthNutritionSyncService (hide behind HC-write capability). Queued for a future
  Fable session, NOT absorbed here (one sweep per session): needs-fable escalations
  #1105 (Skip collection-persistence audit) + #1109 (SAF bridge design). Emulator drive
  debt unchanged: food compiled-shared rows + scout #3's 5 workout leftovers still need
  an uncontended window. No code touched; worker WIP left alone.

- **2026-07-27 (scout #4, Fable):** SOURCE-ONLY sweep — ps-check found the executor
  lane live (16+ min in, #1108 WIP on the tree) so the emulator was never touched
  (scout #3's collision lesson applied). (1) Post-manual-window enumeration refresh:
  operator checkpoint e8821123 (07-26) added the SetEntrySanity set-done dialog to
  shared ActiveWorkoutView — reconciled: scout #1's "implausible-weight" ok row IS
  this dialog's ceiling variant (build 44 postdates the 22:56 checkpoint; builds 46+
  published 01:55+); annotated the un-driven variants (3× jump-from-last, reps>100,
  duration>90m, "Let me fix it" path) + the bare-"form tips"→current-exercise
  refinement. (2) WorkoutScan tracking hole closed: #1095 closed descoping scan to
  #1063, but #1063 never enumerated workout scan and carries no needs-plan label —
  the operator-flagged gap (0-RESUME.b) sat in no lane's queue. Filed **#1110 P2
  needs-plan** (scoped port: picker/streaming seams, hardening-commit inventory,
  DriftCore-extraction question, done-when); both scan rows repointed #1095→#1110.
  (3) Food area sharpened from source (next in rotation, most unknowns): FoodTabView
  gating is DISCIPLINED — every iOS-only sheet's entry affordance is gated with it
  (no #1093-class dead taps found in source). 8 unknown rows → missing (recipe
  builder, combos+combo-log, goal setup, plant points detail, confirm-log,
  CombosView, ManualFoodEntrySheet, LogMealSheet — all under #1062/#1067),
  suggestion chips → deviation (Android quick-logs directly w/ toast undo,
  documented interim), 2 rows added (Snap shortcut missing #1063; entry-row
  contextMenu with Log Again + Move Up/Down as real residuals). Compiled-shared
  rows (calendar sheet, edit sheet, timeline, donut, serving stepper) stay unknown
  pending an uncontended-emulator drive — that's the next scout's food work, plus
  the 5 leftover workout drive-throughs from scout #3. 1 issue filed, no code
  touched, worker WIP (DriftAndroidApp.swift, AndroidPrefsFacade.kt) left alone.

- **2026-07-27 (executor, Sonnet):** Executed #1102's plan exactly: `WorkoutService.
  saveSession`/`loadSession` switched from `UserDefaults` `Data` to `String` (JSON),
  with a legacy-Data read fallback. 2 new Tier-0 tests, full DriftCore + iOS suites
  green (516f85cd, pushed). **On-device verification found the fix insufficient** —
  filed **#1108 P0**: UserDefaults writes made during app *runtime* never reach
  `shared_prefs/defaults.xml` on this build, for ANY value type, not just Data.
  Proven 5 ways: scenePhase-background persist (HOME press, confirmed real
  onPause/onStop via dumpsys — no write), 30s auto-save tick (90s undisturbed
  foreground wait — no write), the explicit synchronous "Minimize" button call
  (write demonstrably executes in-process — Resume banner shows — but still never
  hits disk after 90s), the mandated `am force-stop` + relaunch repro (session
  genuinely lost, no banner), and an unrelated control test — the More tab weight-
  unit lbs/kg toggle (plain String/enum preference, zero relation to WorkoutService)
  — which visibly recomposes in the UI but never touches `defaults.xml` either.
  `shared_prefs/` mtime stayed frozen at the last fresh-install timestamp through
  the entire ~30min session. Root cause unknown (Skip Fuse bridge's disk-flush
  mechanism, not the Swift-side code) — `needs-plan`, not a mechanical fix. Flagged
  **#1104** (same String pattern, was `planned`) directly and relabeled it
  `needs-plan` — it would very likely hit the identical wall since its own
  Done-When requires the same `am force-stop` survival test. #1102 relabeled
  `planned` → `blocked` (dependency #1108); do not close until #1108 lands and the
  Variant A/B repro is re-verified. No publish this session (DriftCore-only change,
  no user-visible improvement yet given #1108).

- **2026-07-27 (scout #3, Fable):** Workout unknown-row burn-down, part 2, on build 48
  (verified f5ceecc9 in-binary first). Drove: past-workout sheet (pastDate badge Jul 26 +
  close-confirm), voice/text sheet end-to-end (typed → LOCAL parse → review; #1079 holds —
  canonical names, no junk-create; unmatched → "Not in library" resolve → picker → Add
  applies), Import alert (Load Package I → "Added 0", name-dedup DB-safe), picker
  leading-swipe Favorite full round-trip (Favorites section materializes; star.slash
  collapses to star.fill → noted on #1099), custom-exercise sheet (name + 7-part Targets
  menu; canceled unsaved — no custom-delete API exists), rest-chip menu (6 options
  0:30–3:00; post-select chip state unverified, see below). 10 rows resolved. Filed
  **#1106 P1** (Fuse keeps the sheet's @State viewModel alive across presentations —
  Cancel → reopen resumes the stale parsed session and exercises ACCUMULATE across
  canceled sessions; double-log risk; iOS resets by construction) and **#1107 P2** (two
  pre-#1079 raw-utterance customs — "3x10 bench press at 135" ×2 — permanently pollute
  "Your Exercises"; no delete path). **Session cut at ~60%: the executor lane
  (claude -p /android-parity, live since 05:53) reinstalled the APK mid-drive — logcat
  "Package REPLACED" 06:10:42 + 2× "app died, no saved state" (06:08:34, 06:10:01)
  killed my active-workout sheet; evidence + proposed emulator mutex commented on #1100.
  Aborted device work rather than bank phantom evidence — next scout: ps-check for a
  live executor BEFORE driving.** Still unknown: per-set warmup flag, active-row→detail
  nav, WorkoutDetailView edit-set/swipe-delete/menu drive-throughs, browser custom CTA,
  BodyMap tap→template. New harness datum: cold-launch FIRST composition can exceed 5s
  on SwiftShader — full-screen mangled intermediate (1-char-wide vertical text columns)
  at 5s post-launch, settled at ~8s; the 2.5s popup rule extends to whole-screen first
  composition — never file a render bug off a first screenshot (checked: #1093 is about
  dead TAPS, unaffected). DB left clean: voice sessions canceled (and died with the
  process — nothing persists, per #1102's own mechanics), custom sheet canceled,
  favorite round-tripped, package load added 0, in-flight workouts never saved.

- **2026-07-27 (scout #2, Fable):** Workout unknown-row burn-down (0-FOCUS): drove
  the full create-template flow (name → picker multi-select → edit-exercise sheet:
  stepper bounds, rest dropdown, warmup toggle → sectioned save), template preview
  actions (row→detail, Start, Edit, Favorite↔Unfavorite, Delete), templates ⋮ menu,
  active-workout close dialog, exercise ⋮ menu, kg/lbs unit menu, command-strip
  focus. 19 rows updated (13 unknown→ok, 3 resolved from source as dead-code/
  ios-only-by-design: Rename + Delete-Template alerts unreachable on BOTH platforms,
  Delete-Workout alert iOS-only). **Filed #1102 P0: SavedSession never persists on
  Android — `UserDefaults.set(Data)` is dropped by Skip's SharedPreferences bridge
  (prefs dump has no session key; `__unrepresentable__` marker precedent), so any
  process death loses the whole workout; proven with two controlled kills (with and
  WITHOUT a prior background transition). Flipped the kill+resume row ok→broken —
  scout #1's pass evidently exercised the same-process path only.** Filed #1103 P1:
  set-done toggle pops the IME with a cursor dropped into the notes/Tip TextField
  (screenshot-evidenced; ties to executor #2's set-row x-range breadcrumb). Infra:
  the emulator's qemu process crashed twice mid-session (host-side, snapshot
  auto-saved; ~20-30min uptime each) — earlier "spontaneous sheet dismissal"
  anomalies attributed to that, not to app menus (deliberate slow re-drive survived
  all menu interactions). SwiftShader first-composition of any popup takes >1s —
  screenshot 2.5s+ after popup-triggering taps or you record a false negative.
  Not driven (left unknown): Import alert, rest-chip menu options, picker/browser
  custom-exercise sheets, per-set warmup flag, active-row→detail nav, voice-log
  sheet (Nebius residual per 0-AI-LADDER). DB left as found (ScoutQA template
  created, driven, deleted; test workouts discarded; the two crash-lost sessions
  left no rows by the very bug filed).

- **2026-07-27 (scout #1, Fable):** Matrix created from full iOS source scan
  (Drift/Views/** + SharedUI/**: every .sheet/.fullScreenCover/.contextMenu/
  .swipeActions/.alert/NavigationLink). Area swept on-device: WORKOUT (0-FOCUS)
  — full end-to-end drive on emulator build 44: root, browser (chips FIXED,
  live search, tap-through), detail (crossfade works), picker (multi-select +
  batch add), active workout (set edit, rest timer, implausible-weight dialog,
  finish/completion/share), history → WorkoutDetailView (⋮ menu complete),
  template preview (warmups + rest times), kill+resume. 27 rows updated.
  Filed: #1096 P0 (first-set-done relaunches MainActivity → dumped to Today),
  #1097 P1 (numeric fields insert-not-replace; NumericFieldSelectAll has no
  Android equivalent), #1098 P2 (resume loses Previous ghosts), #1099 P2
  (detail equipment chip wrench). Commented #1095: streak card + history rows
  VERIFIED WORKING (descoped); scan entry + fetchRecentWorkouts=[] +
  show-all-10 remain. #1079 (junk custom exercise from raw utterance) is
  closed-fixed; the "3x10 bench press at 135" row visible in picker is
  leftover pre-fix data, not a live bug.

- **2026-07-27 (executor #1, Sonnet):** No `planned` issue existed yet (planner
  lane hadn't caught up); per 0-RESUME-2026-07-26(a) re-audited Workout root +
  the two surfaces the operator hand-edited this week (TemplatePreviewSheet,
  ActiveWorkoutView close/finish). Fresh iPhone-vs-emulator side-by-side
  confirmed root/template-preview/active-workout structure already matches
  (corroborates scout's pass above). **Found + FIXED a real gap the scout's
  content-level pass wouldn't catch: iOS 26 draws system glass chrome (gray
  capsule behind toolbar TEXT buttons, near-white shadowed circle behind
  ICON buttons) that Drift's source never draws explicitly (bare
  `Button("Close")` / `Image(systemName: "xmark.circle")`) — Android's
  in-content header ports (#1089 pattern) rendered these as flat
  text/icon with zero chrome, looking chrome-less next to iOS.** Added
  `toolbarPillChrome()` / `toolbarCircleChrome()` to SkipUICompat.swift
  (Android-gated; circle variant avoids real `.shadow()` per #1074 — a single
  offset-fill layer, not a blur pass) and applied at the two Android-gated
  call sites (TemplatePreviewSheet's Close, ActiveWorkoutView's X/Finish) —
  the shared `closeButton`/`finishButton` properties themselves are untouched
  so iOS's real toolbar is byte-identical. Verified via rebuild + fresh
  screenshot both call sites; matches iPhone closely. iOS suite 1274 green,
  Core 2331 green, android-build-check green, `skip app launch` green both
  before/after. Independently re-derived the Apple-Health-band root cause
  (`HealthConnectService.fetchRecentWorkouts` hardcoded `{ [] }`) — matches
  the row already in this table, good corroboration. Also chased "3 of 7
  exercises show a silhouette instead of a photo in the Full Body template"
  (TRX Rows/Wrist Extension/Wrist Flexion) to ground: assets ARE bundled
  (1790/1790 synced), `registerCustomExercises()` is add-only-if-missing-by-
  name (never backfills an existing record's imageUrl), so this is the SAME
  class of stale pre-fix local dev-DB row as the scout's "3x10 bench press"
  note above, not a live code bug — leaving as-is rather than "fixing" test
  data. Residual scout-filed chrome-adjacent work still open: #1096 P0
  (MainActivity relaunch on first-set-done, needs-plan — did not attempt,
  needs real investigation into Skip's notification-permission bridge),
  #1097/#1098/#1099.

- **2026-07-27 (executor #2, Sonnet):** Claimed the Opus plan on #1096 and
  shipped it verbatim: Skip Fuse *shims* `UserNotifications`, so
  `canImport(UserNotifications)` was true on Android and the real rest-end
  notification branch (lazy `requestAuthorization`) compiled into the app —
  that lazy permission ask is what relaunched `drift.android.MainActivity`
  (harness-skip-permission-relaunches-mainactivity). Fix: two guards in
  `SharedUI/ActiveWorkoutView.swift` tightened to
  `#if canImport(UserNotifications) && !os(Android)`, routing Android to the
  pre-existing `#else` no-op stubs — a pure narrowing, iOS byte-identical.
  Verified on-device from a `pm revoke POST_NOTIFICATIONS` (notDetermined)
  state: mark set 1 done → single MainActivity (`dumpsys activity
  activities`), zero `requestAuthorization`/`UNUserNotification` in logcat,
  rest bar counts down in-sheet; Finish ~2s later opens the completion sheet
  ("Nice work!"), matching scout capture `23-finish-retry.png` — capture
  `19-finish-options.png` (misnamed; its actual content is the dumped-to-
  Today bug) never reproduced. iOS suite 1274/1274 green before commit.
  Commit f5ceecc9. Also root-caused (did not fix, out of scope for this
  plan) why the row-1 "done" toggle and "delete set" controls sit at
  adjacent-but-distinct x-ranges in the same cell (~851-917 vs ~917-1043) —
  a blind coordinate tap on the delete sub-range removed a *different* row
  than the one tapped, worth a look if #1076's set-row interaction sweep
  revisits this view (not reproduced carefully enough this session to file
  with confidence — noting as a breadcrumb, not a bug report).

  **Gap-hunt sweep (Today tab, rotated off Workout per directive 7):**
  confirmed rings/donut is `ok` — the small colored dot at each ring's 12
  o'clock position at 0% progress is CORRECT, not an Android artifact: it's
  `Circle().trim(from:0,to:0).stroke(...lineCap:.round)` drawing its round
  cap even at zero length (both iOS sim and Android emulator show the same
  dot at 0%, matching skipui-fuse-perf-facts' "Circle().trim().stroke()
  rings WORK"). Found a real, well-evidenced gap: iOS's Dashboard 3-tile
  row under the meals list is `BodySummaryCardsRow` (Drift/Views/
  BodySummaryCardsRow.swift) — ALWAYS three fixed cards, WEIGHT / SLEEP /
  READINESS, each with spec-pinned empty-state copy ("Log your weight to
  track progress" / "Connect Apple Health for sleep data" / "Connect Whoop
  or log a manual score", pinned by #821 Done-When #2). Android's row in
  the same position (confirmed via this session's own element dump: text
  "WEIGHT"/"157.9 lbs", "WORKOUTS"/"1"/"this week", "STREAK"/"3w") shows
  WEIGHT / WORKOUTS / STREAK instead — not a re-skin, a different
  component entirely; Android has no SLEEP or READINESS tile anywhere in
  this row, so a user with Health Connect sleep/HRV data would never see
  it surfaced here the way an iPhone user with HealthKit data does. Logged
  as a new `deviation` row rather than fixed (out of scope for this
  session's plan); needs #1070 (Health Connect adapter) for real data
  before a port is meaningful, but the row could ship its empty states
  today. Not filing a new issue — #1061 already scopes "unknown" Today-tab
  sub-components and is the natural owner.

## Workout (epic #1064 · single-source: SharedUI/WorkoutView.swift hosted by WorkoutTab)

| screen | sub-interaction | status | issue |
|---|---|---|---|
| Workout tab root | template grid (cards; "Show all N" affordance, caps at 5) | ok | #1095 verified non-gap: loaded 11 templates on emulator, "Show all 11" appears + expands, shared code unmodified |
| Workout tab root | streak card (conditional: current > 0) | ok | |
| Workout tab root | burn chips (active cal / steps; gated on DriftPlatform.health) | ok | |
| Workout tab root | Health Connect workouts band (fetchRecentWorkouts real data via readWorkoutsJson facade) | ok | #1095 shipped: header Android-gated to person glyph + "Health Connect" label (iOS unchanged, heart.fill + "Apple Health"); device-verified w/ seeded session (type/duration/calories correct, DESC sort) |
| Workout tab root | history collapsible + rows → WorkoutDetailView (auto-expand on save) | ok | |
| Workout tab root | history row .contextMenu (delete) — gated off in source :423; Android path = detail ⋮ menu (verified) | ios-only-by-design | |
| Workout tab root | Templates ⋮ menu (New Template / Load Packages I–IV / Remove All; Import iOS-only) | ok | |
| Workout tab root | templates EMPTY state (`emptyTemplatesActions`: "No templates yet" + Import + Drift Packages pills) | ok | scout #28 device-verified (104) — was an un-enumerated row. Drift Packages → 4-item menu → "Added 5 Drift Package I templates" + OK alert |
| Workout tab root | templates POPULATED card vs iPhone, same 5-template fixture on both devices | ok | scout #28 **state-matched side-by-side** `ios-01`/`and-11`: count `5`, the same five names, the same `N exercises · M warmups` subtitles and chevrons. Only delta is the menu glyph — iOS `ellipsis.circle` (⋯ in a ring), Android Material `MoreVert` (⋮). Recorded, NOT filed: same meaning, and ⋮ is the Android idiom |
| Workout tab root | Start Empty Workout → ActiveWorkoutView sheet | ok | |
| Workout tab root | **AI Coach button glyph** — iOS `brain.head.profile` (brain-in-head); Android renders Material **AccountCircle** (the account avatar) | deviation | #1252 scout #28, side-by-side `ios-01`/`and-11` on the post-#1233 build. `Symbols.swift:10`. Worse after #1233, which maps `person.2*`→`person.crop.circle.fill` — the AI button now shares a glyph family with the app's real people affordances |
| Workout tab root | **Log Past Workout glyph** — iOS `clock.arrow.circlepath`; Android renders Material **Refresh ⟳** ("re-run this workout") | deviation | #1252 · `Symbols.swift:11` → `WorkoutView:181` |
| Workout tab root | **History header glyph** — same `clock.arrow.circlepath` → **Refresh ⟳** in accent | deviation | #1252 scout #28 device side-by-side `ios-03`/`and-22` · `WorkoutView:427`. Two more Android call sites outside Workout: `TodayTab:691` Recent chip, `WeightTab:384` weight history — 4 total |
| Workout tab root | Muscle Recovery body map + per-group chips (soreness data) | ok | |
| Workout tab root | resume banner ("Workout in progress — Resume") — on-disk persistence FIXED via durable SQLite KV store | ok | #1108 closed f39655f3; device-verified both variants (#1102 closed, executor session 2026-07-28) |
| Workout tab root | past-workout log sheet → ActiveWorkoutView(pastDate:) w/ Jul-26 date badge; close-confirm fires | ok | save path not driven |
| Workout tab root | voice/text log sheet: typed entry → parse → review card → Log CTA (see ExerciseVoiceLogSheet rows) | ok | parse=LOCAL tier; Nebius residual 0-AI-LADDER |
| Workout tab root | scan workout sheet (`showingScan` → WorkoutScanSheet, iOS-only file; scan-primary entry REPLACED voice/text on iOS — Android still shows the legacy voice/text sheet) | missing | #1110 (#1095 closed-descoped) |
| Workout tab root | create template sheet (`showingCreateTemplate` → CreateTemplateView) | ok | |
| Workout tab root | edit template sheet (`editingTemplateForEdit`; via preview Edit, prefilled + Update CTA) | ok | |
| Workout tab root | exercise browser sheet (`showingExerciseBrowser`) | ok | |
| Workout tab root | template preview sheet (warmups, pose thumbs, rest times, start/edit/favorite/delete) | ok | |
| Workout tab root | Rename Template alert — `showingRenameAlert` set nowhere: dead code on BOTH platforms | ok | |
| Workout tab root | Delete Template alert — dead code both platforms (preview deletes immediately, same as iOS); Remove All alert reachable via ⋮ (menu verified, alert itself not driven) | ok | |
| Workout tab root | Delete Workout alert — trigger lives in the iOS-only history contextMenu; Android deletes via detail ⋮ | ios-only-by-design | |
| Workout tab root | Import alert: ⋮ Load Package I → "Added 0 Drift Package I templates" + OK (name-dedup, DB-safe) | ok | |
| ActiveWorkoutView | FIRST set-done → notif-permission moment relaunches MainActivity, dumps to Today | ok (fixed f5ceecc9) | #1096 |
| ActiveWorkoutView | close → confirmationDialog (Minimize / Discard workout / Keep going + message) | ok | |
| ActiveWorkoutView | set done pops keyboard into notes/Tip TextField — FIXED: tap-to-edit, set-DONE no longer steals IME focus | ok | #1103 closed aab2e238; device-reverify pending (runtime focus; scout #11) |
| ActiveWorkoutView | add exercises → ExercisePickerView sheet | ok | |
| ActiveWorkoutView | set row: decimal-pad keyboard appears, value commits | ok | |
| ActiveWorkoutView | set row: focus select-all — FIXED, typing replaces not inserts | ok | #1097 closed 066c91bc; device-reverify pending (runtime; scout #11) |
| ActiveWorkoutView | SetEntrySanity set-done dialog (operator e8821123 07-26; the driven "really heavy" = its absolute-ceiling variant). Un-driven variants share the mechanism: 3× jump-from-last (+100 lb floor), reps>100, duration>90m, "Let me fix it" cancel path; markSetDone now stable-ID (survives index shifts across the confirm round-trip) | ok | ceiling variant driven post-checkpoint (build 44) |
| ActiveWorkoutView | set row: prev-weight ghost values + prefill | ok | |
| ActiveWorkoutView | set row: done toggle ✓, per-exercise kg/lbs header menu ✓ (flip re-labels, doesn't rewrite field text — identical shared code); per-set warmup flag not driven | ok | |
| ActiveWorkoutView | rest-time chip Menu: opens w/ 6 options 0:30–3:00 | ok | chip-update after select unverified — lane collision (#1100) killed app; cheap re-check |
| ActiveWorkoutView | set done → green tint + inline rest timer countdown + coach toast | ok | scout #28 re-verified on 104: a **single** tap paints the filled green ✓, tints the weight/reps cells green, and drops the inline rest bar counting down from the exercise's 1:30. **Trap recorded for the next scout:** a double-tap (easy to do when aiming by bounds) toggles done back OFF while the rest bar keeps running, which reads exactly like "the checkbox doesn't paint" — I nearly filed it. Re-test with one tap on a fresh row before believing it |
| ActiveWorkoutView | exercise ⋮ (xmark.circle) menu: Favorite / Track by Time (drawn clock) / Remove — the Android contextMenu replacement | ok | |
| ActiveWorkoutView | command strip: tap → focus + IME with send action (parse path = Nebius residual, 0-AI-LADDER; e8821123 refinement: bare "form tips" resolves to the current exercise — Tier-0-tested, no new UI surface) | ok | |
| ActiveWorkoutView | exercise row → NavigationLink ExerciseDetailView | unknown | |
| ActiveWorkoutView | finish → options sheet (save-as-template/favorite) → completion card + share text | ok | scout #28 re-drove end-to-end (104): options sheet = "Nice work!" + Duration/Exercises/Sets trio + Save as template + Favorite all exercises + Save Workout/Back; completion card = 💪 "Workout Complete", full emoji share text, Share, Share-with-friends + Share-with-my-coach toggles, Send to someone specific, Done |
| ActiveWorkoutView | Android in-content X/Finish chrome scrolls with content (iOS pins them in the toolbar, `:323` `#if !os(Android)`) | ok | scout #28 **hypothesis tested and REFUTED**: the chrome does scroll off, but the scroll's own tail carries a full-width **Finish** + **Cancel Workout**, so the actions are never unreachable. Cosmetic only — deliberately NOT filed |
| ActiveWorkoutView | "N sets" stat glyph (`sym("number")` → Material **List**; iOS shows `#`) — also `Track by Reps` in the exercise ⋮ | deviation | #1252 (weakest of that issue's three; explicitly droppable) · `Symbols.swift:161` |
| ActiveWorkoutView | mid-workout kill + resume — FIXED: SavedSession persists via durable SQLite KV store, survives process death (both kill variants) | ok | #1102 CLOSED — device-verified Variant A (30s tick, no backgrounding) + Variant B (HOME then force-stop): both show Resume banner, restore exercise/set/done-state/timer, and clearSession works on Finish + Cancel (executor session 2026-07-28) |
| ActiveWorkoutView | resume drops Previous-column ghosts (shows "—") — CONFIRMED still reproduces on the new keyValueStore resume path (not stale): pre-interrupt Previous showed "185 lbs × 12", post-resume reads "—" | deviation | #1098 device re-verify done (executor session 2026-07-28), ready for planning |
| ExercisePickerView | search field: autofocus, live results, tap result w/ keyboard up | ok | |
| ExercisePickerView | recent/your/all sections + last-weight decoration | ok | |
| ExercisePickerView | row .swipeActions(leading): swipe reveals Favorite, tap → Favorites section appears; Unfavorite restores | ok | star.slash→star.fill collapse noted on #1099 |
| ExercisePickerView | multi-select circles + "Add N Exercises" batch CTA | ok | |
| ExercisePickerView | custom exercise sheet: name field + Targets menu (7 parts) + Add/Cancel | ok | save-path not driven (no custom-delete API; junk-averse) |
| ExercisePickerView | "Your Exercises" carries pre-#1079 raw-utterance customs ×2; no delete path exists | ok | FIXED a8a62339 (#1107 CLOSED): run-once launch prune (`ExerciseDatabase.pruneLegacyUtteranceCustoms`, history-guarded so referenced names survive) wired on both platforms via the durable KV seam (#1108); device-verified the run-once flag persists across real Android process death, not just the Tier-0 simulation. User-facing delete UI still carved to #1127 |
| ExerciseBrowserView | body-part filter chips row visible + filtering (bugsweep-A FIXED) | ok | |
| ExerciseBrowserView | search field live filter (char-by-char, combined w/ chip) | ok | |
| ExerciseBrowserView | rows: pose photo thumbnails + distinct equipment glyphs | ok | |
| ExerciseBrowserView | row → NavigationLink ExerciseDetailView (works w/ keyboard up) | ok | |
| ExerciseBrowserView | custom-exercise CTA (+ top-right) sheet | ok | scout #28 device-verified (104): the Android in-content header (`:55-71`) carries `Done` + `plus.circle.fill` "Add custom exercise"; tapping it opens the Custom Exercise sheet (name field, Targets menu defaulting to Chest, Cancel/Add). Posted to #1234, whose "no Done pill / blank list on open" claims did NOT reproduce |
| ExerciseDetailView | pose crossfade photos (-0/-1 HEIC animate) | ok | |
| ExerciseDetailView | muscle diagrams primary/secondary + name/level chips | ok | |
| ExerciseDetailView | equipment chip glyph — FIXED to match browser rows | ok | #1099 closed f899db8e; source-verified (sym map + shape) |
| ExerciseDetailView | per-exercise history / PR (est. 1RM per row) | ok | |
| TemplatePreviewSheet | warmup + exercise sections, pose thumbs, per-exercise rest, notes | ok | |
| TemplatePreviewSheet | exercise rows → NavigationLink detail (crossfade, muscles, PR) | ok | |
| TemplatePreviewSheet | Start Workout / Edit / Favorite↔Unfavorite / Delete Template (immediate, no confirm — same as iOS) | ok | |
| CreateTemplateView | add exercises via picker sheet (nested sheet, multi-select, batch CTA; catalog fills async ~2-3s on emulator) | ok | |
| CreateTemplateView | per-exercise sets Stepper bounds (+/- work, floor clamps at 1) | ok | |
| CreateTemplateView | edit-exercise sheet: sets stepper, Rest dropdown 0:15–3:00, warmup toggle → WARMUP section round-trip, Track-by, notes, Remove | ok | |
| WorkoutDetailView | header stats + set rows w/ per-set 1RM | ok | |
| WorkoutDetailView | ⋮ menu: Share / Edit Name & Notes / Save as Template / Delete | ok | |
| WorkoutDetailView | set row .swipeActions(trailing) delete | ios-only-by-design | source-resolved scout #28: `:121` is `#if !os(Android)`, and the file's own comment records it is a **no-op on BOTH** platforms (this is a ScrollView, not a List). Tap-to-edit is the live path on both — nothing to port |
| WorkoutDetailView | Edit Set (iOS alert / Android sheet stand-in) | ok | scout #28 device-verified (104): tapping a set row opens `EditSetSheet` titled "Edit Set" / "Back Squat — Set 1" with both values prefilled (185 / 5) and Cancel+Save; Cancel returns cleanly. The sheet-not-alert substitution is deliberate (#1077 strips `.keyboardType` inside a SkipUI alert) and the `.large` detent + per-field view scopes are load-bearing, both documented in-file |
| WorkoutDetailView | menu actions drive-through (rename/delete/save/share sheets) | ok | scout #28 device-verified (104): ⋮ opens all four items (Share / Edit Name & Notes / Save as Template / Delete Workout), matching iOS. **Edit Name & Notes driven end-to-end**: BOTH alert TextFields render and — contra the one-TextField-per-scope worry — the SECOND field commits; typing `legday` into Notes and tapping Save wrote `notes='legday'` to the row (verified in `files/Drift/drift.sqlite`, not from the screen). **Delete Workout driven end-to-end**: confirm alert renders with iOS's title+message, Delete removes the row (4→3 workouts in the DB) AND pops the view — i.e. `dismiss()` from an `.alert` action WORKS, narrowing #1219 to `.confirmationDialog` specifically (posted there). Share / Save as Template not fired |
| ExerciseVoiceLogSheet | typed parse → review: "3x10 bench press at 135" → canonical Bench Press card (#1079 re-verified live) | ok | parse=LOCAL tier; Nebius wiring residual (0-AI-LADDER) |
| ExerciseVoiceLogSheet | resolve-target: unmatched name → "Not in library — tap to pick" → full picker → select+Add applies name to row | ok | |
| ExerciseVoiceLogSheet | Cancel keeps parsed session — reopen resumes stale review, exercises accumulate (iOS resets) | ok | FIXED e979e2c5 (build 65, #1106 closed): `.onDisappear` now also calls `viewModel.reset()` + clears `draft`/`resolveTarget`, ungated (no-op on iOS). Device-verified: fresh reopen after Cancel, no accumulation across a second utterance, resolve-picker does NOT wipe the in-progress session, swipe-to-dismiss reopen is fresh, unsubmitted draft clears. New Tier-1 `ExerciseVoiceLogViewModelTests`; iOS suite 1470/1470 green |
| BodyMapView (recovery) | muscle figure colored by soreness (front+back render) | ok | |
| BodyMapView (recovery) | tap muscle → suggested recovery template | ok | device-verified (executor session 2026-07-28): tapping an under-trained chip (e.g. "Chest, 8d ago") expands an inline "haven't trained X in over a week" note + tappable template quick-starts (Start Push Day/Full Body/P5 Day 2/4); tapping a suggestion opens the real template pre-loaded with its warmup+working-set structure |
| MuscleHighlightCard | only render site is ExerciseDetailView muscle diagrams (device-verified ok above); "per-workout" premise stale | ok | source-resolved |
| CoachMeView (AI Coach) | reached from `WorkoutView:107`; in-content chrome Close / "Coach" / Reset | ok | **first device drive, scout #28** (104) — discharges scout #27's "cheapest undriven screen" residual |
| CoachMeView (AI Coach) | opening turn + suggestion chips + input bar vs iPhone | ok | scout #28 side-by-side `ios-06`/`and-07`: same bubble copy ("Let's build you something. How many days a week can you train — and which days?"), same 2/3/4/5-days chips, same "Tell the coach…" field. A **match** |
| CoachMeView (AI Coach) | disabled send button doesn't dim on Android (iOS pales the glyph; Android's `SendUpShape` fill stays full accent) | unknown | scout #28 saw this on the executor's then-uncommitted #1233 WIP for `SendUpShape`; NOT re-checked after `3e439102` landed, so deliberately not filed. One screenshot settles it |
| CoachMeView (AI Coach) | chip → conversation advances → program draft → Start workout / Save as template | unknown | scout #28 tapped "3 days" but the executor lane took the device mid-turn; the capture is theirs, not mine, so it is discarded rather than reported |

## Food (epic #1062 = INDEX · single-source: SharedUI/FoodTabView.swift hosted by FoodTab + Android stand-ins AndroidFoodSearchSheet/AndroidRecentMealsSheet · scoped ports #1138 search-hub / #1139 quick-add+manual / #1140 combos+recipes / #1141 residual affordances; capture #1063, goal #1117, edit-bug #1120)

Source-decomposed 2026-07-28 (scout #9); **sub-interaction-enumerated 2026-08-04 (scout #15)**. #1062 was a
coarse mega-epic, split into 4 scoped children mirroring #1067->#1114-1119. All 10 iOS-only food files
(`Drift/Views/Food/**`) have ZERO Android presence (grep-verified); Android ships thin stand-ins
(`FoodTab.swift` AndroidFoodSearchSheet:39 / AndroidRecentMealsSheet:198) + the shared FoodTabView with every
create/build/combo/goal/confirm path `#if DRIFT_IOS_APP`-gated. SHARED FoodTabView surfaces (date strip, rings,
timeline, edit sheet, serving input) compile on Android via the ported ServingInputView/EditFoodEntrySheet/
MealCalendarPicker/MealTimePicker/FoodLogViewModel/DescribeMealSheet -- those rows stay `unknown` = DEVICE-VERIFY
DEBT (executor lane held the emulator again this session; 6th consecutive scout). FoodTabView line citations below
re-verified at HEAD 2026-08-04 -- all still accurate.

**iOS moved after scout #9's sweep, and the #1138-#1141 issue bodies + #1138's planner plan (2026-07-29) all
predate it:** `bab6b201` (07-30) folded barcode Scan into the search FIELD as a trailing accessory (empty-query
only; the clear-x takes over while typing), cut the chip row 4->3 (`Saved`/`Build`/`Custom`) and standardized
every user-facing string on "**Meal**"; `fdc49f9e` (07-30) replaced the bare `DatePicker` in ManualFoodEntrySheet
+ QuickAddView with `MealTimePicker` (time slider + auto-following meal chip); `e9b4d5cf` (07-31) removed
LogMealSheet's `Done` button. Staleness commented onto #1138 + #1139 this session -- an executor following the
plan verbatim would ship the pre-refactor layout.

| screen | sub-interaction | status | issue |
|---|---|---|---|
| Food tab root | date strip — **DEVICE-VERIFIED ok scout #20**: renders Sat 8→Sat 15 w/ Tue 11 pill, taps change day. Android windows the strip to −3/+7 days vs iOS −30/+7 (`FoodTabView.swift:386-394`, deliberate: `ScrollViewReader.scrollTo` never fires on Fuse) — deeper history only via the month sheet | deviation (documented, by design) | — |
| Food tab root | date-strip dot — **NOT a bug** (scout #20 checked before filing): the dot under today with an empty diary is the today-marker, `dayDotColor(isToday:hasFood:)` `:545-547` returns `Theme.accent` for today regardless of food; `hasFood` only colors non-today days | ok | — |
| Food tab root | Select Date calendar sheet (`showingDatePicker` → MealCalendarPicker, os(Android) in-content header :410-430) | unknown | device-verify debt (sheet not opened — executor took the emulator mid-sweep) |
| Food tab root | macro summary card (P/C/F/Fb bars + kcal headline) — **DEVICE-VERIFIED ok scout #20**: renders and updates live across two logs (0→280→500 kcal, macros + "N left" all tracked) | ok | — |
| Food tab root | meal timeline sections + entry rows — **DEVICE-VERIFIED ok scout #20**: "Snack · 12:22 AM–12:23 AM · 500 cal" section header w/ `+`/chevron, per-entry name + time + portion + macro line + cal + `✕`; time-range collapses correctly as entries accrue | ok | — |
| Food tab root | Food Diary **sort / meal-grouping chip row** (`:844-876`) — renders only when `todayEntries.count > 1`; 🍽 toggle then 🕐/P/C/F/Fb/🌱 flat-sort chips. Emoji labels render monochrome-white on the ink capsule on Android where iOS keeps the color emoji (`.foregroundStyle` does not recolor Darwin color glyphs) | unknown | device-verify debt (tap intercepted by executor; emoji-tint delta is source-derived, wants a side-by-side) |
| Food tab root | Logging Consistency heatmap card (`:1252`, shared) — **DEVICE-VERIFIED renders scout #20**: 30-cell grid + "N/30 days" + Less/More legend; cell fills tracked the two logs | ok | — |
| Food tab root | plant-points row (`:615-642`) — **DEVICE-VERIFIED renders scout #20** via `LeafShape`; fractional totals ("3.8/30") are intentional (`:625` picks `%.1f` when non-integral), and `+N new today` counts distinct new species so it can exceed the weighted total — shared, **not** an Android defect | ok (row renders; tap is the gap) | #1141 (tap only) |
| Food tab root | `#if DEBUG` "Seed sample data" button (`:1205-1213`) — visible on the emulator because that is a debug build; correctly compiled out of release. **Verified-clean, do not file** | ios-only-by-design (DEBUG-gated, both platforms) | — |
| Food tab root | entry row edit sheet (`editingEntry` → EditFoodEntrySheet, SharedUI ported; beware stale SharedUICopy dupe #1071) — cal/macro OVERRIDE fields reported dead to tap | broken | #1120 |
| Food tab root | serving input in edit sheet (ServingInputView ported) | unknown | device-verify debt |
| Food tab root | add-food search sheet — Android stand-in `AndroidFoodSearchSheet` (FoodTab.swift:39); iOS FoodSearchView (49KB, 6 sections + 7 sub-sheets) NOT ported; #1075 = stand-in returns-nothing break | deviation | #1138 |
| Food tab root | recipe builder sheet (`showingRecipeBuilder` DRIFT_IOS_APP :203) → QuickAddView — no Android trigger | missing | #1139 |
| Food tab root | manual food entry (`showingManual` → ManualFoodEntrySheet) — no Android manual-add path at all | missing | #1139 |
| Food tab root | combos sheet (`showingCombos` iOS-gated :207/:787) + combo log sheet (`comboToLog` :210) → CombosView/ComboLogSheet; Android combo chips log DIRECTLY w/ toast undo (interim :753) | missing | #1140 |
| Food tab root | goal setup sheet (`showingGoalSetup`) — sheet + BOTH macro-card tap affordances iOS-gated (:600/:612); gates flip in the GoalSetupView port | missing | #1117 |
| Food tab root | plant points detail — static LeafShape row renders on Android; tap + expandable list iOS-gated :634-641 | missing | #1141 |
| Food tab root | confirm-log sheet (`showingConfirmLog` :237) — only trigger is the iOS-only contextMenu "Log Again" :1115 | missing | #1141 |
| Food tab root | barcode scanner fullScreenCover (`showingScanner` :165) — inherently LIVE-camera (AVFoundation); the landed #1128 seam is photo-library-ONLY, does NOT cover barcode → still needs a camera seam | missing | #1063 (live-camera seam pending) |
| Food tab root | Snap shortcut (safeAreaInset camera.viewfinder → PhotoLog) — DRIFT_IOS_APP :128-156; Food-tab entry point still not ported (Today's chip is the only Snap entry on Android) | missing | #1111 (Today chip shipped; Food-tab entry unclaimed) |
| Food tab root | suggestion chips: iOS → FoodLogSheet/ComboLogSheet review; Android quick-logs DIRECTLY (deliberate interim :753-781). **WRITE PATH DEVICE-VERIFIED ok scout #20** — tapped 2 chips, both persisted with correct cal/macros/portion and the diary + macro card + plant row all updated | deviation (by design) | #1140/#1138 |
| Food tab root | quick-log confirmation toast (`flashCopied` :365-370 → `.overlay(alignment: .bottom)` :175-185, 2s self-cancelling `.task(id:)`) — **DEVICE-VERIFIED ok scout #20**: green "Added Dal Tadka to today" capsule, bottom-anchored, gone by +3s. NB it is a toast only — there is **no Undo action** in it on either platform; the matrix previously called it "toast undo", which overstates it (the trash `✕` on the row is the undo) | ok | — |
| Food tab root | toast **paint latency**: capture at +0s after the chip tap showed no toast, no new row and no macro change; everything appeared together by +1s. Consistent with [[skip_fuse_compose_recomposition_delivery]] — the synchronous `@State` write does not schedule a recomposition, the repaint rides the async `reload()`. Same mechanism as #1180/#1137 | deviation | #1180 (same root cause) |
| Food tab root | entry-row contextMenu (Edit/Favorite/Log Again/Copy/Move) — Darwin-only by house rule; Edit=row tap, Delete=✕, Favorite/Copy=edit sheet mapped; Log Again + Move Up/Down have NO Android path | deviation | #1141 |

### Food search hub (#1138 · iOS `Drift/Views/Food/FoodSearchView.swift` **1021 ln** vs Android stand-in `FoodTab.swift:39` `AndroidFoodSearchSheet` 150 ln)

Enumerated 2026-08-04 (scout #15) from the iOS file at HEAD. One row per sub-interaction so the port can't
silently drop any ([[feedback_android_full_parity]]). Everything here is `#1138` unless a different issue owns it.

| screen | sub-interaction | status | issue |
|---|---|---|---|
| Search hub | search field + live debounce (iOS 200ms + off-main detached; Android 200ms via `.task(id:)`) | ok | — |
| Search hub | **result QUALITY**: iOS `FoodService.searchFood` (spell-correct + Indian synonym expansion curd/dahi/thayir->yogurt + `searchFoodsRanked` exact/prefix/phrase tiers + `food_usage` personal rank + time-of-day boost + `trackSearchMiss`); Android calls raw `AppDatabase.searchFoods` (`FoodTab.swift:184`) = prefix-then-ALPHABETICAL, none of the above | broken | **#1193** |
| Search hub | min query length: iOS searches from 1 char, Android gates at `>= 2` | deviation | #1138 |
| Search hub | fuzzy fallback — iOS retries with the last char dropped when 0 hits and q>=4 (`:137-139`); Android none | missing | #1138 |
| Search hub | **barcode accessory INSIDE the search field** (`barcode.viewfinder`, empty-query only, `:156-168`, new 07-30) -> `BarcodeLookupView` fullScreenCover; clear-`x` takes over while typing (Android HAS the clear path via SearchQueryField) | missing | #1063 (live-camera seam) |
| Search hub | 3 quick chips `Saved`(bookmark)/`Build`(fork.knife)/`Custom`(square.and.pencil) `:280-292` — Android has no chip row at all | missing | #1140 (Saved) / #1139 (Build+Custom) |
| Search hub | zero-query section **RECENT** (`FoodService.recentFoods(limit:8)`, non-embedded) | missing | #1138 |
| Search hub | zero-query section **COMBOS** (`viewModel.combos` -> `comboToLog` -> ComboLogSheet; itemCount + total-cal subtitle) | missing | #1140 |
| Search hub | zero-query section **⭐ FAVORITES** (`viewModel.favoriteFoods` -> `recentEntryRow`) | missing | #1138 |
| Search hub | zero-query section **FREQUENTLY USED** (`viewModel.frequentFoods`) | missing | #1138 |
| Search hub | zero-query section **YOUR FOODS** — embedded-only, frequency-then-recency blend, dedup by lowercased name, cap 8 (`:231-234`) | missing | #1138 |
| Search hub | zero-query section **POPULAR** — cold-start browse only (hidden once `yourFoods` non-empty); canonical-name filter drops fuzzy junk (`:923-939`) | missing | #1138 |
| Search hub | Android shows ONE hint line ("Search the food database — dosa, dal, eggs…") in place of all six sections above | deviation | #1138 |
| Search hub | `foodSuggestionRow` **trailing `+` = 1-TAP QUICK-LOG at last-used servings** (`:402-411`), distinct from tapping the row (opens log sheet). Android's `+` glyph is decorative — the whole row opens the confirm sheet, so the 1-tap path does not exist | missing | #1138 |
| Search hub | `recentEntryRow` split behaviour: DB food -> log sheet; recipe/manual -> bookmark icon + `+` quick-adds macros directly (`:460-475`) | missing | #1138 |
| Search hub | **`confirmLog` toast + haptic on EVERY add path** ("Added X · N cal" capsule, 1.5s, token-guarded; `:83-108`) — #1025 filed because silent adds caused double-logging. Android has no add confirmation at all | missing | #1138 |
| Search hub | `contextMenu` Favorite/Unfavorite on suggestion + recent rows (`:414-422`, `:478-486`) — Darwin-only gesture, needs an Android affordance | missing | #1138 |
| Search hub | results `Section("Foods")` row = name + macroSummary + unit info (`1 <unit>` or `<size><unit>`); Android row = name + "N kcal · P Ng · size" | deviation | #1138 |
| Search hub | results **leading swipe = Favorite** (`:596-603`) | missing | #1138 |
| Search hub | results **trailing swipe = Delete**, Scanned-category foods only (`:604-613`) | missing | #1138 |
| Search hub | results `Section("Your meals")` recipe matches + **`group · N` badge** when `expandOnLog` (`:643-649`); tap logs the recipe directly | missing | #1140 |
| Search hub | recipe row trailing swipe Delete (`:657-665`); leading swipe **Edit** routes to QuickAddView-rebuild (has `recipeItems`) OR `EditRecipeSheet` (flat) — `:666-676` | missing | #1140 |
| Search hub | **`EditRecipeSheet`** (`:945-1003`, nested in this file, unnamed in the #1138 body): Name + per-serving cal/P/C/F/fiber `decimalPad` fields, Save disabled on empty name, title "Edit meal" | missing | #1140 |
| Search hub | **Online Results** section (globe header) — OpenFoodFacts + USDA in parallel, opt-in `Preferences.onlineFoodSearchEnabled`, fires when local hits < 5 and q >= 3, dedup vs local + within itself. **No longer transport-blocked** (scout #21): #1194 is closed and every DriftCore HTTP consumer now rides `DriftPlatform.httpSession` — this is a plain port, not a blocked one | missing | #1138 |
| Search hub | "Searching online…" states (full-screen when zero local hits, inline Section when some) | missing | #1138 |
| Search hub | `noResultsView` = "No results for X" + **Log with AI** (borderedProminent) + **Enter manually**; Android has the AI row but no manual-entry escape | deviation | #1138 / #1139 |
| Search hub | inline `describeWithAIRow` between Foods and Your-meals when no exact match and q>=2 (`:622-624`); Android appends it after the flat list | deviation | #1138 |
| Search hub | log sheet (`logFoodSheet` `:798-910`) vs Android `ServingConfirmSheet`: iOS adds per-unit macro header line, `ServingInputView`, totals card (cal + P/C/F chips + fiber), `.presentationDetents([.fraction(0.65), .large])` | deviation | #1138 |
| Search hub | log sheet **`SuspiciousPieceBanner`** multi-piece sanity check (`:829-837`, the TJ-meatballs class) | missing | #1138 |
| Search hub | log sheet **`PastDayLogBadge`** when the viewed day isn't today (`:864-868`) + `.pastDayLogBadge` on the standalone hub (`:66`) | missing | #1138 |
| Search hub | log sheet toolbar **star favorite toggle** in the `principal` slot (`:880-889`) | missing | #1138 |
| Search hub | nav chrome: title flips to "Add Food (N logged)" and Cancel -> **Done** once anything is logged (`:69-75`) | missing | #1138 |
| Search hub | `embedded: Bool` mode (LogMealSheet host drops NavigationStack + toolbar and swaps the section set) | missing | #1138 (dep LogMealSheet port) |
| Search hub | Coach handoff pre-select: `initialQuery`/`initialServings`/`initialMealType`/`initialSelectionId` -> auto-open the log sheet on the resolved row (#930/#978 correctness) | missing | #1138 / #1135 |
| Search hub | keyboard: focus-on-appear one runloop tick after present (`:266`); `.scrollDismissesKeyboard(.immediately)` on results, `.interactively` in the log sheet | unknown | #1138 (device-verify) |

### Build / Custom entry (#1139 · iOS `QuickAddView.swift` 738 ln + `ManualFoodEntrySheet.swift` 180 ln · no Android trigger exists)

| screen | sub-interaction | status | issue |
|---|---|---|---|
| QuickAddView | "Build a Meal" — FOOD ITEMS list, empty copy "Add food items to build your meal" | missing | #1139 |
| QuickAddView | `IngredientPickerView` sheet (`:208-210`) + per-item edit sheet (`editingIndexBinding` `:211`) + remove-item button (`:88`) | missing | #1179 (builder carve-out) |
| QuickAddView | Total row + Servings field (`decimalPad` `:127`) | missing | #1139 |
| QuickAddView | **`Log items individually` Toggle -> `expandOnLog`** (`:139-142`) — drives the `group · N` badge on "Your meals" rows | missing | #1139 |
| QuickAddView | `MealTimePicker` (`:151`, replaced the bare DatePicker 07-30) | missing | #1139 |
| QuickAddView | `"Delete meal?"` destructive alert (`:180-184`) + save-as-recipe / rebuild-existing (`editingRecipeID`) | missing | #1139 |
| ManualFoodEntrySheet | "Quick Add": name + Calories (`numberPad`) + P/C/F/Fiber + Serving (`decimalPad`), live "Macros sum to N kcal" cross-check (`:64`) | missing | #1139 |
| ManualFoodEntrySheet | **`MealTimePicker`** (`:122-125`, replaced the bare DatePicker 07-30) — logs the PICKED mealType, not `autoMealType` | missing | #1139 |

### Saved meals / combos (#1140 · iOS `CombosView.swift` 164 ln + `ComboLogSheet.swift` 214 ln · no Android entry)

| screen | sub-interaction | status | issue |
|---|---|---|---|
| CombosView | "Saved meals" list; trailing swipe Delete + Edit, leading swipe (`:26-36`); toolbar Done + `+` add-meal | missing | #1140 |
| CombosView | empty state "No saved meals yet" + "Create meal" CTA (`:130-134`) | missing | #1140 |
| ComboLogSheet | per-combo sheet: FOOD ITEMS + `ServingMultiplierStepper` per item (`:154`), title = combo name | missing | #1140 |
| ComboLogSheet | menu **Delete combo** + `"Delete <name>?"` destructive alert (`:70-88`) | missing | #1140 |
| ComboLogSheet | legacy-format notice ("saved in an older format… logged as a single entry", `:166`) | missing | #1140 |
| ServingMultiplierStepper | +/- stepper w/ editable `decimalPad` field, `.onSubmit` commits + drops focus (`:30-39`) — Android IME caveat | missing | #1140 |

### Residual food surfaces

| screen | sub-interaction | status | issue |
|---|---|---|---|
| LogMealSheet (308 ln) | segmented Recent/Search/Describe/Snap host; Android ships `AndroidRecentMealsSheet` (Recent only, no segmented chrome) | deviation | #1138 |
| LogMealSheet | `Done` button REMOVED 07-31 (`e9b4d5cf`, swipe-down dismisses) — Android stand-ins still render an in-content Done | deviation | #1138 |
| LogMealSheet | Snap segment auto-triggers `PhotoLogFlowView` then bounces back to Recent on dismiss (`:107`) | missing | #1063 |
| PlantPointsCardView (201) | plant-diversity card + expandable plant list + "No plant foods logged yet" empty state | missing | #1141 |
| MealReviewSheet / PhotoLogReviewView | editable review — every photo/capture logging path funnels through it on iOS | missing | #1063 |
| VoiceLogSheet (471) | voice food logging: Describe -> Listening… -> "Understanding what you ate…" -> "Couldn't hear that"/Try again -> review; mic dictate button | missing | #1063 (speech seam #1178) |

## Today (epic #1061 = INDEX · Android-only re-creation: TodayTab.swift **665 ln** vs iOS DashboardView.swift + DashboardView+Cards.swift · **#1129 #1131 #1201 #1213 all CLOSED**; live scoped issues: **#1225 card order/fold · #1226 cold start · #1202 reload discipline [absorbs #1203] · #1130 nudge+Insights content nondeterminism (feature itself SHIPPED) · #1075 skeletons · #1116/#1114/#1094 banners · #1117 goal card · #1132 consistency card · #1070 health-seam columns** · `mealsCard` now hosts the SharedUI single-source `MealTimelineSection`)

Source-enumerated 2026-07-28 (scout #7): full iOS→Android structural diff, no emulator
(both sibling lanes live). Rows ordered top→bottom matching iOS `DashboardView.body`.
Data classified DriftCore-portable-NOW vs health-seam-gated (#1070). Android correctly
HIDES health sections (no fake zeros, [[android_hide_unwired_integration_ui]]) rather than
render them empty — those stay `missing`→#1070, not new ports. Shared components all live
in iOS-only `Drift/Views/` (LogMethodCardsRow, BodySummaryCardsRow, MealTimelineSection,
V6CoachingNudge, WorkoutConsistencyCard, GoalProgressCard, TodayDonutView, V6Rings).

**Re-verified 2026-08-04 (scout #17), source-only — 8th consecutive scout with no device
access.** The 07-28 rows had gone stale in both directions: one row was a FALSE deviation
(Log methods — iOS has no Voice card) and one was actively MISLEADING (Meal timeline —
"dot-rail", which iOS deleted 2026-05-24, and which #1131's Done-When still required).
Two rows were misrouted to blocked seam epics that can't fix them (WEIGHT column → #1070).
New this pass: a SPEED block (#1202) and the meal-list ordering defect (#1201) — the Today
section had never carried a single perf row despite operator directive 0-PERF-P0.

**DEVICE-VERIFIED BOTH PLATFORMS 2026-08-11→17 (scout #23), Android build 92 + iPhone 17 Pro
build 380 — the first true side-by-side in the program.** Fourteen rows were stale and four
of the issues they pointed at were **CLOSED** (#1131, #1201, #1129, #1213), i.e. the board was
aiming the executor at dead tickets and at two features that already ship (meal card,
nudge+Insights). New this pass: the card-order/fold defect (#1225), an unowned cold-start
miss against directive 0-PERF-P0 (#1226), and a nudge/Insights content nondeterminism logged
on #1130. Two tempting leads were run down and recorded CLEAN so nobody re-chases them: the
nudge's warning triangle and the single-person social-pill glyph are both deliberate,
documented, directive-0a-correct fallbacks.

| screen | sub-interaction | status | issue |
|---|---|---|---|
| Chrome | brand header: iOS = `BrandMark` **asset** in the **nav toolbar** (principal); Android draws a "D" **circle IN scroll content** — wrong element AND wrong placement | deviation | #1121/dir-8 |
| Chrome | privacy banner — Android `lock.fill` vs iOS `lock.shield.fill`; Android adds a trailing Spacer (iOS is leading-aligned) | deviation | #1061 |
| Chrome | pull-to-refresh — iOS has `.refreshable { await viewModel.loadToday() }` (`DashboardView.swift:360`); Android has none. **Device-verified scout #23**: pulling down at the top of the Today tab produces no spinner and no overscroll affordance | deviation | #1061 |
| Chrome | 180s auto-refresh poll — Android reloads on `.foodEntryAdded` + onAppear instead. The *substitution* is still an acceptable interim, but see the SPEED rows below: the onAppear half is unthrottled. | deviation | #1202 |
| **Speed** | **no reload throttle.** iOS skips `loadToday()` when data is <30s fresh (`DashboardView.swift:346-352`) and DELETED its duplicate `.onAppear` load on purpose ("the duplicate here raced it on each tab switch (perf 2026-07-09)", `:336-341`). Android has no `lastFullLoadAt` equivalent — `.onAppear { store.reload() }` (`TodayTab.swift:170`) fires unconditionally on every entry to the tab, on top of `init()` (`:47`) and the `.foodEntryAdded` observer (`:53-55`). Directly on operator directive 0-PERF-P0. | deviation | #1202 |
| **Speed** | **500 workouts fetched TWICE per reload.** `weeklyWorkoutCounts(weeks: 1)` and `workoutStreak()` are called back-to-back (`TodayTab.swift:106-107`); `workoutStreak()` is itself `weeklyWorkoutCounts(weeks: 52)` (`WorkoutService.swift:663-666`) and both funnel into `fetchWorkouts(limit: 500)` (`:638-639` → `:278-282`). No caching between them. Every hop crosses JNI. | deviation | #1202 |
| **Speed** | **entire weight table read + sorted to display one number.** `WeightServiceAPI.getHistory(days: 365)` returns the whole table unfiltered (`WeightServiceAPI.swift:70-76` — `if days >= 365 { return entries }`), then Android sorts all of it to take `.first` (`TodayTab.swift:100`). iOS reads the same value from already-loaded `viewModel.latestWeight`. | deviation | #1202 |
| **Speed** | **overlapping unstructured reloads.** `reload()` wraps everything in a bare `Task { }` (`TodayTab.swift:69`) — no stored handle, no cancellation, no re-entrancy guard, so a tab switch racing a `.foodEntryAdded` post can have two loads writing the same `@Observable` fields in unspecified order. iOS's `.task` is view-lifetime-bound and cancels. | deviation | #1202 |
| Nutrition hero | "% of goal" chip + rings render against `resolvedCalorieTarget()` even when no `WeightGoal` exists — so a goal-less install reads "N% of goal" against a TDEE-derived number. **Checked and NOT a fabricated value:** `resolvedCalorieTarget()` falls back to real TDEE with a 1200 floor (`FoodService.swift:369-377`), and Android's `max(t.target, 1200)` (`TodayTab.swift:82`) is a redundant re-floor, not an invented goal. The wording is the only deviation; folded into the existing no-goal-fallback row. | deviation | #1061 |
| Banners | profile-incomplete nudge → ProfileView ("Add age, sex & height…") — Android none | missing | #1116 |
| Banners | 7-day feedback banner (#759, days 7–14 → More/Report-a-bug; xmark dismiss) — Android none | missing | #1114 |
| Banners | stale-backup banner (#561, >3d → Backup settings sheet) — Android none | missing | #1094 |
| Nutrition hero | iOS `calorieBalanceCard` = `TodayDonutView` (goal path) + no-goal fallback (eaten + P/C/F/Fiber chips); Android `intakeCard` re-creates 3 concentric rings + legend but is ALWAYS ring-mode (no no-goal fallback) | deviation | #1061 |
| Nutrition hero | skeleton while loading (`SkeletonCalorieBalanceCard`) — Android has no skeleton (shared TodayStore mitigates the cold "0 kcal" flash, #1075) | deviation | #1075 |
| Log methods | **CORRECTED scout #17** (row was a FALSE deviation since 07-28): iOS is Snap · **Describe** · Search · Recent — there is no Voice card. `LogMethodCard` has exactly 4 cases (`LogMethodCardsRow.swift:87-88`) and `:12` records "#935 merged the old Voice/Text pair". Android's Snap · Describe · Search · Recent is the SAME set, not a substitute. Do not route this to #1126 (that's TTS/voice-input, correctly carved to #1126/#1178). | ok | — |
| Log methods | container styling: iOS = `LazyVGrid` 4 flexible cols, `minHeight 56`, `.padding(.vertical, 10)`, `strokeBorder(Theme.separator, 0.5)`, `.dynamicTypeSize(...accessibility2)`; Android = `HStack(spacing: 10)`, `.padding(.vertical, 16)`, `.shadowSoft()` and **no border**. Taller chips + shadow-instead-of-hairline. LazyVGrid avoidance may be deliberate ([[skipui_font_scale_rendering_traps]] #1159 — Texts+LazyVGrid vanish at font_scale >1); confirm before "fixing" to a grid. | deviation | #1121 |
| Log methods | Recent chip glyph: iOS `clock`, Android `clock.arrow.circlepath` — different Material mapping. Cosmetic; not filed separately. | deviation | #1121 |
| Log methods | **Snap chip**: opens `SnapMealSheet` (#1111) — Take Photo (`CameraCaptureFacade`/`CameraCaptureService`) + Choose from Library (`DriftPlatform.imagePicker`, #1128) both capture correctly; the cloud vision round-trip COMPLETES since #1177 closed (`861411f8`, build 81) — a real thali returns 7 separated dishes with macros and logs to the diary. Error+Retry verified (graceful, no crash); a foodless photo now says "couldn't spot any food" instead of blaming the network (#1195). No longer opens Coach chat (that misrouted placeholder is gone). | ok | #1111 |
| Log methods | Describe / Search / Recent chips wired (was `broken` #1093, now CLOSED) → DescribeMealSheet / AndroidFoodSearchSheet / AndroidRecentMealsSheet | ok | #1093 (closed) |
| Meal timeline | **PORTED TO THE SHARED iOS COMPONENT — the ten rows this block used to carry are obsolete.** `bdf9e48f` (in build 92) moved `MealTimelineSection.swift` into `SharedUI/` and points both `DashboardView` (`:194`) and Android's `mealsCard` (`TodayTab.swift:293`) at it, deleting the Android flat-list re-creation. **#1131 and #1201 are both CLOSED.** Rows below are device-verified scout #23 against that shared component | ok | #1131 (closed) |
| Meal timeline | row order earliest-first (`rows(from:)` sorts ascending on both platforms) — was the #1201 defect | ok | #1201 (closed) |
| Meal timeline | tap-to-expand portion + P/C/F(+Fiber) macro chips — shared component, both platforms | ok | #1131 (closed) |
| Meal timeline | in-row **Remove** — shared component; both platforms call `AppDatabase.shared.deleteFoodEntry(id:)` then reload (`DashboardView.swift:203-206` == `TodayTab.swift:294-297`), byte-equivalent delete path | ok | #1131 (closed) |
| Meal timeline | header **"+"** — **device-verified scout #23**: opens the Add Food search sheet. iOS posts `.openLogMeal(mode: .search)` → `LogMealSheet`'s segmented Recent/Search/Describe host; Android opens `AndroidFoodSearchSheet` (search-only, "Done" dismiss at LEADING edge). Same intent, different host — that host gap is #1198's scope, not a new row | deviation | #1198 |
| Meal timeline | empty-state copy — **device-verified identical**: both read "Log your first meal — try the **Snap** card above". Android's glyph is a bare fork+knife where iOS draws it inside a circle outline (Android-gated in the shared file: `fork.knife` is unmapped and would render a triangle) | ok | — |
| Meal timeline | row content — the meal-type pill iOS never showed is gone with the re-creation; rows are `time · name · kcal` on both | ok | #1131 (closed) |
| Meal timeline | swipe-to-delete — still Android-gated OFF **deliberately** (`DragGesture` vs Compose scroll is an unproven runtime interaction, and in-row Remove already covers deletion). iOS keeps its hand-rolled `SwipeToDeleteContainer` | deviation (by design) | — |
| Meal timeline | kcal math — Android `Int(e.calories * e.servings)` == iOS `entry.totalCalories`. **Verified equal, no bug.** | ok | — |
| Meal timeline | skeleton while loading (`SkeletonMealTimelineSection`) — Android none | deviation | #1075 |
| Body summary row | **SPLIT scout #17 — the old row filed all three columns under #1070, hiding a portable-now fix behind a seam.** SLEEP + READINESS are genuinely HealthKit-sourced and correctly hidden ([[android_hide_unwired_integration_ui]]); Android substitutes WORKOUTS / STREAK (DriftCore). That half stays #1070. | missing | #1070 |
| Body summary row | **WEIGHT column needs NO health seam and is broken parity today**: iOS shows a `%+.2f unit/wk` rate line + **goal-aware value color** (green aligned / red against / neutral ink when no goal) — `BodySummaryCardsRow.swift:162-196`, `goalAlignedColor :246-263`. Android passes fixed `Theme.accent` and renders the value in `Theme.textPrimary` unconditionally (`TodayTab.swift:396`, `:412-414`), with no rate at all. Violates design tenet #3 (goal-aware color, never "good/bad"). Both inputs already run on Android — `TodayTab.swift:74` already calls `WeightTrendService.shared.trendWeight`, and `weeklyRate` is its sibling property (`WeightTrendService.swift:26`). | deviation | #1203 |
| Coaching nudge | iOS `V6CoachingNudge` (topmost proactiveAlert, Ask-AI pill, 24h dismiss; `BehaviorInsightService` = DriftCore) — **not at HEAD**: `TodayTab.swift` body ends at `statTrio` (:259). **IN FLIGHT scout #23**: the executor installed build 93 from its uncommitted #1130 work at 08:59:17 and the nudge renders there (title, detail, working Ask-AI pill, × dismiss, iOS's after-the-trio adjacency). Do not mark shipped until it commits | missing (in flight) | #1130 |
| Behavior insights | iOS `insightsCard` (BehaviorInsight list under "Insights") — **not at HEAD**. **IN FLIGHT scout #23**: renders in the executor's build 93 (INSIGHTS header + lightbulb card + multiple rows, last on the tab). Do not mark shipped until it commits | missing (in flight) | #1130 |
| Goal progress | iOS `goalCard` (`GoalProgressCard` → GoalView) / empty "No weight goal set" — Android none (statTrio has WEIGHT value only, no progress card) | missing | #1117 |
| Daily Average (TDEE) | ~~Android none~~ — **ROW WAS STALE, corrected scout #20 by screenshot**: the card SHIPS (`TodayTab.swift:390-480`) and renders eating / deficit-ring / burning + the target line + a Weight pill. #1129 is **CLOSED**; residual = iOS's second source pill ("Apple Health", device-confirmed present on iOS scout #23) and the explainer→AlgorithmSettings route (`TodayTab.swift:387-389` documents the card deliberately doesn't navigate until #1118 lands) | deviation | #1118 (route) / #1070 (2nd pill) |
| Daily Average (TDEE) | ~~target line prints the wrong goal DIRECTION and magnitude (`gain 95.6 lbs`)~~ — **FIXED, device-verified scout #23**: build 92 renders `Target: eat 2340 kcal/day to **lose 6.8 lbs**` against stored latest 81.1 kg / target 78.0 kg. **#1213 is CLOSED** | ok | #1213 (closed) |
| Daily Average (TDEE) | ~~iOS side-by-side owed; no iPhone build installed~~ — **DEBT CLEARED scout #23, 2026-08-17: the iPhone 17 Pro simulator (516EAAC8, iOS 26.4) now has Drift build 380 installed** and was driven this session. Four scouts had recorded this as blocking `0-SCREENSHOT-EXACT-IS-THE-BAR`; iOS-side claims can now be screenshot-backed. Capture with `xcrun simctl io 516EAAC8-… screenshot`, tap via mobile-mcp (points = px/3) | ok | — |
| Activity section | iOS "Activity" header + `healthRow` (Active cal / Steps → Exercise tab) — Android hides (HealthKit seam) | missing | #1070 |
| Activity | iOS Apple-Health `workoutCard` (burned N cal, ≤3 workouts) when today workouts exist — Android none (HealthKit seam) | missing | #1070 |
| Activity | iOS `WorkoutConsistencyCard` (weekly, 24h dismiss; `BehaviorInsightService.workoutConsistencyVariant` + WorkoutService = DriftCore, NOT health-gated) — Android none | missing | #1132 |
| Recovery section | iOS "Recovery" header + `sleepRecoveryCard` (Recovery/Sleep scores, HRV/RHR, → SleepRecoveryView) / empty "Body Rhythm" — Android none (sleep/HRV/RHR = HealthKit seam) | missing | #1070/#1061 |
| Recovery | iOS `supplementCard` (N/M taken → SupplementsTabView) when supplements configured — Android none (Supplements TAB is ported #1068; dashboard entry not) | missing | #1061 |
| Coach entry | floating `ChatIconButton` → AIChatView — PORTED (AppShell.swift + ContentView.swift), matches iOS single AI access point | ok | #1066 |
| **Card order** | **`dailyAverageCard` sits at body slot 4 (`TodayTab.swift:246` at HEAD) where iOS puts `tdeeCard` 12th (`DashboardView.swift:259`, after `goalCard`).** That one 528px card (+14px spacing) above the social pill pushes the four log-method chips AND the whole TODAY'S MEALS card off the first paint — on Android you must scroll to reach any logging entry point; on iOS all four chips, the meals card and the stat trio are visible unscrolled. Relative order *below* the hoist is correct. | deviation | **#1225 (P1)** |
| **Speed** | **cold start 4.2–5.8s** (5 runs, `am force-stop` → `am start -W`: 5583/5777/4825/4188 ms on build 92 + 4325 ms on build 93, all `LaunchState: COLD` — the executor reinstalled mid-sweep, so re-baseline on one build) against operator directive 0-PERF-P0's **< 2.5s** emulator exit criterion — and the emulator is *faster* than the Pixel 2 baseline. Cold start is a trustworthy metric per 0-EMULATOR-GPU-CAVEAT(a) (unlike SwiftShader framestats). Unowned: #1073/#1074 closed, #1202 covers per-reload redundancy only. | broken | **#1226 (P1)** |
| Coaching nudge + Insights | ~~nondeterministic across launches~~ — **RETRACTED by scout #23 in the same session.** The "absent" launches were build 92 (feature genuinely absent) and the "present" ones build 93 (executor's WIP, installed 08:59:17 mid-sweep); a residual two-variant difference *within* build 93 is untrustworthy because that lane was driving and plausibly seeding food rows at the time. **No finding here.** Recorded only so the next scout doesn't re-derive it from the same contaminated screenshots — and as the standing lesson: re-check `lastUpdateTime` at the END of a drive, not just the start | — | — |
| Coaching nudge | glyph — the protein alert draws a **red warning triangle**, which reads like a directive-0a violation. **NOT verified clean — do not cite scout #23 for this.** The reasoning I checked (`exclamationmark.triangle.fill` falls through `sym()` deliberately *because iOS draws the identical glyph*) lives in the executor's **uncommitted** `SharedUI/V6CoachingNudge.swift`; `Drift/Views/Shared/V6CoachingNudge.swift` at HEAD has no `behaviorInsightGlyph` at all. It is #1130's verifier's call, not the scout's | unknown | #1130 |
| Social pill | glyph — iOS `person.2.fill` (two people), Android renders a single person. **VERIFIED CLEAN, do not chase:** `Symbols.swift:86-89` records that skip-ui maps no two-person glyph at all (person.2/person.3/group/people all absent) and falls to `person.crop.circle.fill` per directive 0a (closest same-meaning glyph, never the triangle). | ok | — |
| Social pill | tap → pushes `SharingView` onto the Today NavigationStack (Friends screen, identity card, search, privacy footnote). **Device-verified scout #23.** | ok | — |
| Nutrition hero | tap → Food tab (`TodayTab.swift:293` `Button { selectedTab = .food }` == iOS `DashboardView.swift:172` `Button { selectedTab = 2 }`). **Device-verified scout #23** — lands on Food with the day strip on today. | ok | — |
| Daily Average (TDEE) | info **(i)** → inline explainer expands (`Required −210 / Current −210 kcal/day`, `Trend: -0.42 lbs/wk → -210 kcal/day`, `Based on 21-day weight trend.`), animated, matching iOS's `showDeficitExplainer` block (`DashboardView+Cards.swift:116-152`). **Device-verified scout #23.** | ok | — |
| Stat trio | taps route WEIGHT→Body, WORKOUTS→Workout, STREAK→Workout (`statTrio`, near the end of the file); iOS's `BodySummaryCardsRow` has a single `onTapBody` so all three go to Body. Downstream of the WORKOUTS/STREAK-for-SLEEP/READINESS substitution, not a separate defect. | deviation (by design) | #1070 |
| Stability | 5× background/foreground cycles + 6 cold launches + tab round-trips: `adb logcat -d -b crash` **empty** for com.drift.health, `dumpsys activity anrs` clean, last tab correctly restored. **Device-verified scout #23** (directive 0-NO-CRASH). | ok | — |

## Body / Weight (epic #1065 = INDEX · Android-only re-creation: WeightTab.swift 326 ln vs iOS WeightTabView.swift 422 ln + 6 sub-views · **live scoped issues: #1205 insights+CURRENT-card+chrome [absorbs #1142] / #1143 affordance completion [absorbs #1144 #1145] / #1220 range-chip chart blanking / #1221 history-row content** · DEXA+photos → #1069 = INDEX, decomposed 2026-08-03 into #1185 DEXA screen / #1190 DEXA charts / #1191 DEXA PDF-import / #1186 gallery data defects / #1187 viewer / #1188 gallery structure / #1189 Trends sheet, plus existing #1166 capture · **Weight-tab rows DEVICE-VERIFIED 2026-08-11 (scout #22, build 90)**; DEXA + progress-photo rows below remain source/scout-#14 vintage)

> **Repointed 2026-08-11 (scout #22):** #1142, #1144 and #1145 are **CLOSED** — consolidated by the Fable planner into #1205 (#1142) and #1143 (#1144, #1145). Eleven rows in this section still cited the closed issues, i.e. the board was pointing the executor at dead tickets. All now point at the surviving issue.

| screen | sub-interaction | status | issue |
|---|---|---|---|
| Weight tab | overall structure — Android WeightTab re-creation, not the iOS WeightTabView single-source port | deviation | #1065 |
| Weight tab | element ORDER — iOS `timeRangeBar → chart → bigChangeBanner → insights → history`; Android `CURRENT card → red Log Weight button → chips → chart → history` | deviation | #1205 |
| Weight tab | weight chart renders (WeightChartAndroid, Path-based — Charts absent on Skip) | ok | #1092 |
| Weight tab | **`1W` chip REMOVES the chart card entirely** — chips filter the data + `!displayPoints.isEmpty` gates the view (`WeightTab.swift:143,193`); iOS plots the full series and uses range only as a window | broken | #1220 |
| Weight tab | chart pan/scroll through history inside the window (iOS `.chartXVisibleDomain`) — Android chart is a static Path, zero gestures | missing | #1220 |
| Weight tab | time-range chips 1M/3M/6M/1Y/All re-window correctly (1M → `Jul 13…Aug 4`, avg + difference recompute) | ok | — |
| Weight tab | stats header — **self-contradicting**: displays `178.8 lbs` over `Current: 180.1lbs`, and prints "7-day change: -0.5lbs" while the 7d chip is absent (`change()` returns nil when the newest entry IS the window edge) | broken | #1205 |
| Weight tab | nav title renders LARGE; iOS pins `.navigationBarTitleDisplayMode(.inline)` (`WeightTabView.swift:76`) — modifier is bridged per #1200 | deviation | #1200 |
| Weight tab | toolbar back chevron (→ Today) + toolbar `+` — Android has neither; uses an in-body full-width red button iOS lacks | missing | #1205 |
| Weight tab | Log Weight save — **bright primary CTA silently no-ops on empty input**; iOS renders it `.disabled` (`WeightEntryView.swift:74`) | deviation | #1143 |
| Weight tab | log sheet: decimal keypad appears (digits + `.` + `,`), typing commits, comma-decimal maps to `.` | ok | — |
| Weight tab | log sheet: **no date field** — every Android weigh-in is stamped today, a missed day can't be back-filled; iOS `Section("Date")` + `DatePicker` | missing | #1143 |
| Weight tab | log sheet: field stroke turns accent-pink on focus (Material `OutlinedTextField` under `.roundedBorder`) — reads as a validation error | deviation | #1204 |
| Weight tab | delete a weigh-in — button WORKS, but it's a one-tap unconfirmed trash on every row; iOS hides delete behind a `.contextMenu` destructive item | deviation | #1221 |
| Weight tab | history row CONTENT — raw ISO `2026-08-04`, date-leading hierarchy, no month grouping/median, no per-row delta, no HK heart, no dividers, non-lazy | missing | #1221 |
| Weight tab | Daily/Weekly granularity menu | missing | #1143 |
| Weight tab | WeightInsightsView: trend-EMA + explainer + body-comp cards → metric sheets + weekday pattern + weight-changes sparklines | missing | #1205 |
| Weight tab | body-comp entry (fat%/BMI/water + muscle/bone/visceral in log sheet) | missing | #1143 |
| Weight tab | edit a weigh-in (tap-to-edit — iOS `.contextMenu` absent on Skip) | missing | #1143 |
| Weight tab | big-change outlier banner (>10% → correct/edit/remove) | missing | #1143 |
| Weight tab | collapsible history disclosure (chevron + N entries) — Android list is always-expanded | deviation | #1143 |
| Weight tab | milestone celebration overlay + haptic | missing | #1143 |
| Weight tab | empty state (manual-log CTA; AH-sync stays hidden till health seam) — Android shows inline "No weights yet" | deviation | #1143 |
| Weight tab | chart trend line sits above the scale points — VERIFIED CLEAN, not a bug: lagging EMA over a declining series, built from full 365d history before windowing (`WeightTab.swift:86`), so NOT the windowed-EMA-reseed bug iOS fixed | ok | — |
| Today dashboard | body summary cards row (`BodySummaryCardsRow` — mounted in `DashboardView`, NOT the Weight tab; misfiled here) — confirmed iOS-only, `Drift/Views/BodySummaryCardsRow.swift`, **zero** Android references | missing | #1061 |
| Weight tab | **dark mode**: the chart's headline `Average` value (`"81.7"`, `WeightChartAndroid.swift`) and the `"History"` row label render **white-on-white and vanish**, while the adjacent `"kg"` and `"35 entries"` survive because those carry explicit colours. Same root cause as the More-tab labels — any `Text` without `.foregroundStyle` inherits Material `onSurface`; iOS is immune via `DriftApp.swift:53` *(driven #24, build 94)* | broken | **#1228** |
| Today tab | **dark mode renders correctly** — its `Text`s do carry explicit `Theme` colours, so the #1228 class does NOT hit Today. Recorded so the fix's verification doesn't assume every tab is broken *(driven #24)* | ok | — |
### Body composition — DEXA (#1069 index · iOS `Drift/Views/BodyComposition/DEXAOverviewView.swift` 632 ln · NO Android route exists)

Source-enumerated 2026-08-03 (scout #14). **The whole data layer is already in DriftCore and
Android-available** (`Models/DEXAScan`, `Models/DEXARegion`, `Domain/Health/DEXAService`,
`Domain/Health/BodyCompositionAnalysis`) — these are pure view ports, not seam work.

| screen | sub-interaction | status | issue |
|---|---|---|---|
| DEXA | route from More — Android `MoreTab.swift` has no Body Composition row at all | missing | #1185 |
| DEXA | overview cards (BF% / lean / fat / visceral, goal-aware deltas, 0.05 neutral threshold) + miniStat row (RMR / A-G / bone / total) | missing | #1185 |
| DEXA | "WHAT CHANGED" breakdown card — `BodyCompositionAnalysis.scanDelta` narrative + verdict tint + weight-trend `reconcile` line | missing | #1185 |
| DEXA | regional breakdown (arms/trunk/legs/android/gynoid) + muscle balance L/R table | missing | #1185 |
| DEXA | "All Scans (N)" list + per-scan delete + "Clear All" destructive alert | missing | #1185 |
| DEXA | manual entry sheet (`DEXAEntryView`) — the ONLY data-in path Android can have, since PDF is iOS-only | missing | #1185 |
| DEXA | trend charts (BF% / fat mass / lean mass) — `Charts` absent on Skip, needs Path port; lean-mass drop must read RED | missing | #1190 |
| DEXA | BodySpec PDF import (`.fileImporter` + spinner + result/error cards) — blocked on #1175 seam AND PDFKit-free parser | missing | #1191 |

### Body composition — progress photos (#1069 index · Android re-creation `ProgressGalleryAndroid.swift` 169 ln vs iOS `ProgressGalleryView.swift` 311 ln + viewer 277 + charts 170 + add-entry 478)

Device-verified 2026-08-03 (scout #14, emulator-5554 build 79) except where noted.
Wired at `MoreTab.swift:120` → `:190` (sheet). Add-entry runs on the landed #1128 image-in seam (`:84`).

| screen | sub-interaction | status | issue |
|---|---|---|---|
| Progress photos | gallery route + check-in cards render | ok | — |
| Progress photos | thumbnail tap → full-screen viewer — **DEAD TAP**, screen pixel-identical after tap; viewer absent entirely | broken | #1187 |
| Progress photos | viewer depth: pose switcher, date swipe, stat-overlay chips, compare mode + goal-aware deltas | missing | #1187 |
| Progress photos | card date — Android renders raw ISO `2026-07-30` vs iOS `Jul 30, 2026` | deviation | #1186 |
| Progress photos | card weight — Android exact-date match vs iOS nearest-within-±14d, so weight usually absent | deviation | #1186 |
| Progress photos | measurement line — Android hardcodes **inches** + chest-only vs iOS unit-aware 4-site `displayOrder` | deviation | #1186 |
| Progress photos | measurement-only check-ins (no photo) never appear — Android groups by photos; `fetchProgressEntries()` is public in DriftCore | missing | #1186 |
| Progress photos | 4-up pose slots with placeholders for missing angles — Android draws only existing photos | deviation | #1188 |
| Progress photos | timeline scrubber (segmented pose picker + horizontal dated thumbs, ≥2 entries) — source-only, needs ≥2-entry device check | missing | #1188 |
| Progress photos | Compare / Trends action row — source-only, needs ≥2-entry device check | missing | #1188 |
| Progress photos | empty state — Android is 2 lines of grey text with no "Add First Check-in" CTA | deviation | #1188 |
| Progress photos | tap-to-edit / delete a check-in — Android header inert; **no correction path exists at all** | missing | #1188 |
| Progress photos | privacy banner — `lock.fill` + larger type + always shown vs iOS `lock.shield.fill` + `.tiny` + only when non-empty | deviation | #1188 |
| Progress photos | toolbar add glyph — bare `+` vs iOS `plus.circle.fill` | deviation | #1188 |
| Progress photos | add-entry depth: 4 poses (camera + library each), measurements by `MeasurementSite.Group`, notes, delete, MeasurementGuideSheet | deviation | #1166 |
| Progress photos | live timer camera (`TimerCameraView`) — needs a camera seam beyond #1128's library-only pick | missing | #1166 |
| Progress photos | Trends sheet (`ProgressChartsView`): insights (ratios / symmetry / biggest movers) + per-site Path charts | missing | #1189 |

## More / Settings (epic #1067 = INDEX · Android re-creation: MoreTab.swift **194 ln** vs iOS MoreTabView.swift **1099 ln** + 9 sibling files · scoped ports #1114 / #1116 / #1117 / #1118 / #1146)

Source-enumerated 2026-07-27 (scout #5), re-verified against HEAD 2026-08-04 (scout #18),
**FIRST DEVICE DRIVE 2026-08-17 (scout #24, Android build 94 vs iPhone 382)**. Every `ok`
row below marked *(driven #24)* was exercised on the emulator, not read from source; the
`missing` rows remain source-verified (no Android route exists to drive). Persistence
acceptance on every ported control inherits #1108 (CLOSED). KEY POLICY (0-AI-FOCUS): no
key-entry UI of any kind ships on Android.

**Scout #24 issue-pointer repair:** 23 rows in this table pointed at **CLOSED** issues.
`#1115` (Settings port) was absorbed into **#1114**; `#1119` (notifications) was decomposed
into **#1146**; `#1192` (COMING TO ANDROID) was superseded by **#1227**; `#1124` (Cycle) is
now closed outright, which discharges scout #18's "leave the call to the planner" note.
All 23 re-pointed. Historical session notes above are left verbatim — they are the record of
what each scout saw, not live pointers.

**Scout #18 staleness note:** `MoreTabView.swift` moved 6× between the enumeration and HEAD
(SOCIAL section added, Cycle row deleted, Report-a-bug re-homed in-app, UsageInsightsView
replaced by TelemetrySettingsView). #1114 and #1115 were sitting in `planned` with specs
encoding the *pre-change* iOS, so both were knocked back to `needs-plan` with corrected scope.
Rows below are HEAD-accurate; the ones marked ⚠ are where the old spec would have built a
regression.

| screen | sub-interaction | status | issue |
|---|---|---|---|
| More hub (MoreTabView :4-210) | hub layout: HEALTH/**SOCIAL**/APP sections, navRow chrome (36pt icon tile, subtitle, chevron, contentShape), inline title | missing | #1114 |
| More hub | ⚠ **SOCIAL section** (`:69-75`, added 2026-07-30): "Friends & Coaches" → SharingView, deliberately its own section not an APP row. **Android already ships it** (`MoreTab.swift:139-159`) — a literal port of #1114's pre-change spec would DELETE a working section | ok | — |
| More hub | ⚠ nav title `.inline` (`:142`, "large title made the nav bar jump ~50pt on every swap"). **No Android-only view sets displayMode at all** (0 hits in drift-android/Sources); SharedUI port inherits it, Fuse bridging is #1200. **MEASURED ON DEVICE #24**: Android draws a large left-aligned ~44sp title in a bar that **never collapses on scroll** — ~230px of 2400 permanently, vs iOS's ~100px centred inline bar — and because it is opaque and pinned, scrolled content passes under it and is **clipped mid-glyph** (PRIVACY subtitle cut in half). Highest-visibility instance of #1200; evidence posted there | deviation | #1114/#1200 |
| More hub | nav title in **dark mode** is white on the light bar — the "More" title is effectively invisible. Same root cause as the body labels below | broken | **#1228** |
| More hub (Android-only) | "COMING TO ANDROID" card (`MoreTab.swift:161-173`) is a hardcoded string array — lists **shipped** Coach chat (#1066) and photo logging (#1111) as unshipped; drifts further with every port. Device-confirmed 2026-08-03 build 79 | deviation | #1227 |
| More hub | ⚠ HEALTH rows **×6, NOT ×7** (corrected #18): Body Rhythm→SleepRecoveryView, Supplements, Body Composition→DEXAOverviewView, Progress Photos→ProgressGalleryView, Glucose, Biomarkers. Destinations: Supplements + Progress Photos LANDED (`MoreTab.swift:96,120`); remaining #1122 (Biomarkers) / #1123 (Glucose) / #1069 (Body Comp) / **#1208 (Body Rhythm)**. Full-hub port keeps rows HIDDEN until each dest lands (no dead taps, #1093) | missing | #1114 |
| More hub | ⚠ **Cycle row DELETED from iOS** 2026-07-28 (`b8b14696`; `:29-32` "keep the first impression light for new users"). The `hasCycleData` conditional is gone with it. #1114's old spec said to build it → would ship a row iOS doesn't have. CycleView is now unreachable on BOTH platforms (flagged on #1124) | ios-only-by-design | #1124 (deferred) |
| More hub | ⚠ **Body Rhythm → SleepRecoveryView (589 ln) had NO scoped issue** — #1068 scopes only Biomarkers/Glucose/Cycle/Supplements, and the matrix mis-routed it to #1061 (the *Today* epic) because the file sits in `Drift/Views/Dashboard/`. Filed #18. Blocked on Charts→Path + an HRV/RHR facade (#1176) | missing | **#1208** |
| More hub | APP row Profile → ProfileView | missing | #1114/#1116 |
| More hub | APP row Weight Goal → GoalView | missing | #1114/#1117 |
| More hub | APP row "Bring Your Own Key" → PhotoLogSettingsView — `#if !os(Android)`, no replacement row | ios-only-by-design | KEY POLICY |
| More hub | APP row Settings → SettingsView | missing | #1114 |
| More hub | ⚠ footer "Report a bug" is **no longer an external Link** — `NavigationLink { SupportView() }` since 2026-08-02 (`b46d434b`, `:117`); the external link WAS the bug ("`support_tickets` had zero rows from either platform"). `SupportView` is SharedUI and **already wired on Android** (`MoreTab.swift:191`) — but as a `.sheet` row under a **TRACKING** header, not a footer link | deviation | #1114 |
| More hub | version line `Drift · v{version} · {year}` (Android keeps its build stamp, gated — `MoreTab.swift:177`) | deviation | #1114 |
| More hub | pop-to-root on tab reselect (`navId` reset via selectedTab onChange) | missing | #1114 |
| More hub (Android-only) | ⚠ **PRIVACY card w/ 2 live toggles** — `usageTelemetryEnabled` (ON by default) + `aiCaptureEnabled` (`MoreTab.swift:46-68`). iOS homes these in Settings → Telemetry & Privacy, which Android lacks. Telemetry IS live on Android (`DriftAndroidApp.swift:66-67,93,98`), so "retire the stub" per #1114 **removes the only opt-out for a running cloud pipeline** — privacy-tenet break. Must land with #1114's TelemetrySettingsView. Copy also weaker than iOS (drops the "@username / account" line) | deviation | #1114 |
| More hub (Android-only) | PRIVACY toggle **durability — DEVICE-VERIFIED #24**, upgrading scout #18's source-only verdict. Switched "Share anonymous usage" OFF → `am force-stop` → cold relaunch: still OFF in the UI **and** `drift_usage_telemetry_enabled=0` in `app_pref`. The opt-out genuinely survives process death; [[skip_userdefaults_data_writes_dropped]] is closed for these keys (#1108). Restored to ON after the test | ok | — |
| More hub (Android-only) | PRIVACY toggle **legibility** — in system dark mode `"Share anonymous usage"` and `"Share AI conversations"` render **white-on-white and are invisible**, because both are `Text(...).font(.subheadline)` with no `.foregroundStyle` (`MoreTab.swift:48,60`) while the card stays hardcoded light. The user cannot read the label of the control governing AI-conversation upload | broken | **#1228** |
| More hub (Android-only) | TRACKING card: Supplements · Support & feedback · Progress Photos, all `.sheet` where iOS **pushes**; sheets cost ~80dp of nav chrome ([[skipui_sheet_chrome_and_hscroll_height_traps]]). "Support & feedback" under a *TRACKING* header is also an IA mismatch. **All three DRIVEN #24 and all three open + render correctly** (Supplements → empty state + streak card; Support → loads, see latency row; Progress → empty state w/ Android-aware copy); the deviation is presentation-mode only, not function | deviation | #1114 |
| More hub | Health Connect card: ⚠ **first tap imports nothing, ever** — `requestPermissions()` is fire-and-forget (`HealthConnectFacade.kt:92-94`), so `syncWeight()` races the grant dialog; result + error both discarded (`MoreTab.swift:80-88`). No status line in ANY outcome (iOS has 4 + 3s auto-clear); no `availabilityStatus()` gate (states 0/2 render as a dead promise); uses anchor-based `syncWeight()` not iOS's deliberate `fullResyncWeight()`; skips body-comp. **DEVICE-PROVEN #24**: grant dialog opens and auto-CLOSEs (7 perms are `USER_FIXED`), app logs `permissions granted: 0`, then `SecurityException: Caller doesn't have READ_WEIGHT` — swallowed, screen pixel-identical before/after. `USER_FIXED` is terminal, so a status string alone can't fix it (commented on #1207) | broken | **#1207** |
| More hub | Health Connect permission ask does **NOT** spawn a duplicate `MainActivity` — task stayed `sz=1`, one `rootOfTask=true` record across the grant round-trip. [[harness_skip_permission_relaunches_mainactivity]] / #1096 is **clear on this path** *(driven #24 — don't re-chase)* | ok | — |
| More hub (stub today) | PREFERENCES weight-unit picker — **works end-to-end** *(driven #24)*: tap kg → Body tab re-renders in kg (81.1 kg, chart axis, Log Weight) → returns to More still kg → survives `am force-stop` + cold relaunch (`app_pref.weight_unit=kg` in `files/Drift/drift.sqlite`). Residual deviation is content only: stub order `lbs,kg` vs iOS `kg,lbs`, and iOS's home is Settings→UNITS w/ the "exercise weights stay in lbs" caption | deviation | #1114 |
| More hub (stub today) | PREFERENCES picker **chrome**: `.pickerStyle(.segmented)` renders as a Material SegmentedButton — pink filled segment + leading ✓ glyph in an outlined capsule — where iOS is a white thumb on grey with no checkmark. Same family as #1204's text fields/buttons; added to that issue rather than filed separately *(driven #24)* | deviation | #1204 |
| More hub (stub today) | HEALTH CONNECT connect/sync card — live; iOS equivalent is Settings→HEALTH SOURCES with status text | deviation | #1114/#1070 |
| More hub (stub today) | privacy blurb + "coming to Android" list — Android-only interim, retires with hub port | deviation | #1114 |
| SettingsView (:195-898) | UNITS: Body Weight Unit segmented kg/lbs + "exercise weights stay in lbs" caption | missing | #1114 |
| SettingsView (:256-306) | HEALTH SOURCES: "Sync from Apple Health" one-action full resync + body-comp import + 3s status line (HC wording on Android, #1095 header precedent). Android's stand-in is the More-hub HC card — see the `broken` row above; plan #1114 to CONSUME #1207's status/gating, not re-derive it | missing | #1114/#1070/#1207 |
| SettingsView | HEALTH SOURCES: Write Nutrition toggle (#934; foreign-app-detect / auth-denied / unavailable states, auto-disable reason line) — needs HC WRITE; hidden until seam grows writes | missing | #1114/#1070 |
| SettingsView | HEALTH SOURCES: "Sync Past Data…" confirmationDialog (30/90/all, skip-foreign-days) — write-gated, same hiding | missing | #1114/#1070 |
| SettingsView | iCloud Backup NavigationLink row — Android backup screen is #1094/#1109's deliverable; row hidden until it exists | missing | #1094/#1109 |
| SettingsView | DATA: Export Workouts CSV + Export Food Logs CSV (DriftCore-built CSV; UIActivityViewController → Android share seam, coordinate w/ #1109 SAF bridge) | missing | #1114 |
| SettingsView | PRIVACY: Online Food Search toggle + conditional "only search terms sent" caption | missing | #1114 |
| SettingsView | PRIVACY: WebSearchSettingsCard — Google key+cx / Brave key fields, expand/collapse, active-provider line: pure key-entry UI; Android web_search runs keyless/provisioned tier with NO settings surface | ios-only-by-design | KEY POLICY |
| SettingsView | ⚠ **PRIVACY: Usage Insights row → UsageInsightsView — THE SCREEN NO LONGER EXISTS.** `rg -l UsageInsightsView` = 0 hits repo-wide; replaced 2026-07-28 by TelemetrySettingsView ("counters tallied what happened on THIS phone, which never answered what real users reach for"). #1114's spec still cites it at `:1030-1098` and says "fold in here" → executor would rebuild a deleted screen. Row deleted, superseded by the two below | ios-only-by-design | *(removed from iOS)* |
| SettingsView (:459-531) | PRIVACY: **Support & feedback** row → `SupportView()` (`:499`) — never enumerated. `SupportView` is already SharedUI + already reachable on Android, so this row is near-free | deviation | #1114 |
| SettingsView | PRIVACY: **Telemetry & Privacy** row → `TelemetrySettingsView()` (`:516`) — never enumerated | missing | #1114 |
| TelemetrySettingsView (:1069-1116) | ENTIRE screen — 2 toggles (`usageTelemetryEnabled` on-by-default, `aiCaptureEnabled` off) + footer disclosure ("Neither is linked to your @username or to a Drift account"). Pure DriftCore, no seams. **Load-bearing on Android**: it's the destination the More-stub toggles must move into, or the opt-out disappears | missing | #1114 |
| SettingsView | NOTIFICATIONS row → NotificationsSettingsView; hidden until #1146 lands | missing | #1114/#1146 |
| SettingsView | ADVANCED: AI Chat Telemetry card — staged-intent toggle (enable-confirm alert, revert-on-cancel binding :548-562), delete-confirm alert, turns count, Export JSON, Delete all (ChatTelemetryService = DriftCore) | missing | #1114 |
| SettingsView | ADVANCED: telemetry "View insights" → AIChatInsightsView (iOS-target file) — link hidden on Android until an AI-insights port exists | missing | #1114 (hide) |
| SettingsView | ADVANCED: Algorithm row → AlgorithmSettingsView | missing | #1114/#1118 |
| SettingsView | ADVANCED: Refresh food database button (idle / refreshing / refreshed-N / failed states, 0-count = real error) | missing | #1114 |
| SettingsView | Danger Zone: Factory Reset + destructive confirm alert + Reset Complete alert (AppDatabase.factoryReset + UserDefaults key sweep — #1108 interaction) | missing | #1114 |
| NotificationsSettingsView (:910-1025) | 4 toggle cards: Health Nudges / Smart Meal (+ conditional "Use my eating patterns" sub-toggle) / Medication Dose / GLP-1 Weekly — setters write DriftCore Preferences then NotificationService.refreshScheduledAlerts() (iOS-only service) | missing | #1146 |
| Android notification seam | DriftPlatform.notifications-shaped seam: channels model, explicit POST_NOTIFICATIONS flow (#1096: Skip's UserNotifications shim must NEVER compile in; no lazy permission asks) | missing | #1146 |
| ProfileView (GoalView+Profile :43-327) | sex segmented Male/Female/N-A — N/A sets `sexUndisclosed`, counts complete, auto-fill never overwrites it | missing | #1116 |
| ProfileView | age range menu picker (Not set + 6 ranges → midpoint) | missing | #1116 |
| ProfileView | height cm↔ft/in segmented mode switch; 1 vs 2 numberPad fields, 50–300cm clamp, silent save | missing | #1116 |
| ProfileView | weight decimal field: unit flip mid-edit reconverts via TEXT as source of truth; commit on FOCUS LOSS → real WeightEntry + trend refresh (Android IME commit trigger must be defined; #1097 select-all remedy applies) | missing | #1116 |
| ProfileView | "Changes save automatically" / Saved flash; health auto-fill on appear when incomplete | missing | #1116 |
| GoalView (GoalView.swift, Chart-free) | profile card row w/ completeness badge (check vs "Improve accuracy") | missing | #1117 |
| GoalView | GoalProgressCard + Update Goal → GoalSetupView sheet | missing | #1117 |
| GoalView | macro-target pills (kcal/P/C/F) + derivation explanation line + fat-minimum note | missing | #1117 |
| GoalView | Pace (required vs actual, on-track status color) / Daily Target deficit pair (goal-aware sign-based color) / Projection (early / behind / on-schedule / wrong-direction states) | missing | #1117 |
| GoalView | Clear Goal + empty state ("No Goal Set" + Set Weight Goal prominent CTA); custom back chevron | missing | #1117 |
| GoalSetupView (sheet, iOS Form) | target weight decimal + kg/lbs segmented; Diet Style radio list (DietPreference cases + subtitles) | missing | #1117 |
| GoalSetupView | custom-macros section (3 numberPad gram fields; footer auto-computes blanks within calorie target; fat-clamp warning) | missing | #1117 |
| GoalSetupView | Calorie Target field w/ 1200 floor (red footer + Save disabled) OR implied-kcal readout when all 3 macros set | missing | #1117 |
| GoalSetupView | Timeline stepper 1–24 months + live "This means:" projection (auto + macro-vs-TDEE variants, exceeds/below warnings, >1000 kcal "Aggressive" note) | missing | #1117 |
| GoalSetupView | Save validation (no parseable target = disabled) + "Log your current weight first" alert; edit mode prefills all fields | missing | #1117 |
| AlgorithmSettingsView (478) | TDEE hero (live cachedOrSync) + target/goal context + Required-vs-Current pair; "Set goal" NavigationLink fallback | missing | #1118 |
| AlgorithmSettingsView | accordion (one-open): Activity slider 22–36 + Reset-to-29; Profile sex/age/height fields (auto-expand while editing); Fine-tune slider ±500 step 25 + Reset — Slider-on-Fuse fidelity is a named plan question | missing | #1118 |
| AlgorithmSettingsView | Advanced disclosure: active-source chips + AH resting/active/steps line (hide when seam nil — no fake zeros); Estimation Style presets ×3 (config-equality detection); How-it-works rows; conditional Reset All | missing | #1118 |
| BackupSettingsView (228) | auto-backup toggle + last-backed-up line, Back Up Now w/ live phase text, Restore picker entry, "What's in my backup?" disclosure, iCloud-unavailable alert — iCloud substrate is Apple-only; Android substrate = #1094/#1109 (SAF) | missing | #1094/#1109 |
| RestorePickerView (163) | backup list, destructive restore confirm, atomic restore + relaunch prompt, empty/loading states | missing | #1094/#1109 |
| BackupOnboardingSheet (115) | app-level onboarding prompt (trigger: DriftApp.swift:67 → Android trigger would live in DriftAndroidApp) | missing | #1094 |
| PhotoLogSettingsView (323) | ENTIRE screen — provider picker, model picker, SecureField key entry + Paste/Save/Replace/Clear, Keychain storage, Test Connection ping: all key management. Android photo AI = provisioned Nebius (#1111) + local Google tier | ios-only-by-design | KEY POLICY |
| *(verified clean #18 → **DEVICE #24**)* | **Preference durability** — `weightUnit` / `usageTelemetryEnabled` / `aiCaptureEnabled` all route through `kv` = `DriftPlatform.keyValueStore` (`Preferences.swift:16-26`, `:447-465`), NOT UserDefaults. **Proven on device #24** by force-stop + cold relaunch (both keys held; values read back out of `app_pref` in `files/Drift/drift.sqlite`). [[skip_userdefaults_data_writes_dropped]] is closed here (#1108 CLOSED). Don't re-chase | ok | — |
| *(verified clean #18)* | **SharedUICopy divergence** — all 53 files in `drift-android/Sources/DriftAndroid/SharedUICopy/` are byte-identical to `SharedUI/` at HEAD. The sync script is current; no Android-runs-different-code bug today. (#1071 is CLOSED — the mechanism remains a hazard but has no live ticket) | ok | *(#1071 closed)* |
| Health Connect | connection flow + permission grant — `onLaunch()` calls `requestAuthorization()` silently, no settings-hub entry, sync failures swallowed by `try?`; worse than iOS's explicit "Sync from Apple Health" button + status text + past-sync dialog. (#1090 CLOSED; live owner is #1207 for the More-card path) | missing | #1070/**#1207** |
| More hub (app-shell) | **dark mode is half-applied** — cards/background are hardcoded light (`Theme.swift`), but any `Text` without an explicit `.foregroundStyle` inherits Material `onSurface` → **white on white**. On More that is `"Weight unit"` (`:21`), both privacy toggle labels (`:48`,`:60`) and the nav title. iOS is immune by design: `Drift/DriftApp.swift:53` sets `.preferredColorScheme(.light)`; Android has **no** equivalent and ships `Theme.AppCompat.DayNight.NoActionBar` (`AndroidManifest.xml:55`) *(driven #24; iOS dark screenshot is pixel-identical to its light one)* | broken | **#1228** |
| App shell (every tab) | full-bleed band between scroll content and the floating tab bar: pale lavender in light mode, **black in dark mode**, while the page stays light — i.e. the Material *window* background showing through instead of `Theme.background`. Same root cause as the row above, folded into one issue rather than filed separately *(driven #24, present on Today/Food/Workout/Body/More)* | deviation | **#1228** |
| Support sheet | `SupportView` (SharedUI) opens instantly but its ticket list shows a bare spinner for **~6s** before resolving to the empty state — no timeout, no error path. Same file iOS uses, so the delta is transport, not layout; worth an iOS-side timing comparison before anyone plans it *(driven #24 — unowned, deliberately not filed on a single unmatched sample)* | unknown | — |
| More hub | cold start to first paint measured **3496 ms** (`am start -W`, `LaunchState: COLD`, build 94) against directive 0-PERF-P0's 2.5s criterion — better than the 4.2–5.8s recorded on builds 92/93 but still 1.4x over. Posted as a data point on #1226 with a recommendation to use a median-of-5 baseline | deviation | #1226 |

## Coach / AI chat (epic #1066 = INDEX · single-source: SharedUI/AIChatView*.swift + AIChatViewModel + MessageHandling(2134 ln) · hosted by ContentView floating ChatIconButton + TodayTab coach sheet)

**Board state corrected scout #25 (2026-08-17):** this section pointed at **four CLOSED issues** — **#1209** (P0, "Coach executes NO tools"), **#1180** (@Observable repaint), **#1137** (dead send button) and **#1135** (food-logging degrades) — across ~10 rows that all read `broken`. Every one of those rows described an app that no longer exists: Drift Coach on Android now executes real tools against real user data. Live scoped children: **#1125** cards+interview · **#1126** voice · **#1133** streaming-hang · **#1210** send glyph · **#1231** badge glyph · **#1232** (NEW, P1) answers render empty · **#1233** (NEW, P1) warning-triangle glyph.

Source-reconciled 2026-07-28 (scout #8). The Coach TEXT chat **SHIPPED** to SharedUI (#1066, commit
b8c244a6): `AIChatView` (+ChatBubble/+InputBar/+Suggestions/+MessageHandling), `AIChatViewModel`, Nebius
brain (`CoachCloud.install` synchronous in onAppear). iOS wraps it in `DriftCoachSheet` (owns the backend
picker); **Android presents `AIChatView()` directly** (ContentView:31 + TodayTab:161) — no picker, Nebius-only,
correct per 0-AI-FOCUS no-key-UI. The message harness (`AIChatView+MessageHandling`) is DriftCore-shared and
runs on Android — but ⚠ **DEVICE-VERIFIED 2026-08-10 (scout #19): NO tool routes at all.** The message harness
reaches `ToolRegistry.shared.execute()`, which is **empty for the life of the Android process** — `rg "registerAll"
drift-android/Sources/` returns nothing, while `Drift/DriftApp.swift:38` calls `ToolRegistration.registerAll()`
and `LocalAIService.swift:81` documents that it must be. Every tool name therefore comes back `unknown tool`,
and `AIToolAgent.swift:809-812` converts that into one canned string — *"I'm here. Ask me about your food,
weight, sleep, or workouts…"* — with `didFail: false`, so nothing surfaces the breakage. **Four consecutive
device turns → four identical fallbacks** (typed text, and the app's own "Weekly summary" pill twice). This is
**#1209, P0**, and it sits UPSTREAM of most rows below: the "deterministic tools route" claim and the per-tool
`deviation | #1125 (card)` rows are **source-true but device-false** — the card is missing *and* the tool never
ran. Remaining gap-classes: **(a)** all 13 tool-result CARDS are `#if DRIFT_IOS_APP` (→#1125); **(b)** food-logging
tools additionally route through iOS-only sheets (→#1135, dep #1062) — downstream of #1209, which must land first;
**(c)** VOICE shimmed off (`CoachVoiceShims` no-ops → #1126); **(d)** ⚠ **the "turns HANG on 'Looking that up…'"
claim is STALE** — replies now land in ~2s with a `via Nebius` badge (logcat `⏱ AIToolAgent Phase 2 (classify):
1481-3002ms` × 4). What survives of #1133/#1180 is a **repaint** defect, not a hang: state lands and Compose
never recomposes, so the turn is invisible until an unrelated interaction pokes the UI. Interview ("set me up")
is `#if DRIFT_IOS_APP` (→#1125). BackendSelector / AISetup / AIChooser are key-UI, iOS-only-by-design.
Rows below are DEVICE-verified 2026-08-10 (build 85 — byte-identical to HEAD for every Coach file; the only
Android deltas since are `SnapMealSheet`/`TodayTab`/`Symbols`) except where marked source-only.

| screen | sub-interaction | status | issue |
|---|---|---|---|
| Coach entry | floating ChatIconButton (ContentView) + TodayTab coach sheet → AIChatView | ok | |
| Chat shell | header ("Drift Coach" + close), scroll, thinking dots, TypewriterText, Android scroll-sentinel | ok | |
| Empty-state hero | iOS = ListeningCircle (a large pink mic circle + "Tap to talk"); Android = static SparkleShape + "Ask me anything". **Side-by-side captured scout #25** (`ios-02-coach-empty.png` / `and-03-coach.png`): iOS's hero is voice-first, so this substitution is the correct read of #1126, not a separate bug. Header `voiceCluster` (speaker + waveform pill, top-left) and the input-bar mic are likewise iOS-only — all one issue | deviation | #1126 |
| Suggestion pills — content | ⚠ **cleared lead, recorded so nobody re-chases it.** Android showed 2 pills (`Log lunch`, `Start smart workout`) where `pillsForTimeAndMeals` (`AIChatView+Suggestions.swift:44-112`) predicts 3 at 13:06 — `Calories left` was missing. **Not a parity bug: it is data.** The device DB holds an orphan `meal_log` row (`id 9018, 2026-08-17, lunch, created 19:06:05Z`) with **zero** `food_entry` rows, so `loggedMeals` contains "lunch" while `totals.eaten == 0`, which drops the branch to the single `totals.eaten == 0` pill. Verified by querying `meal_log`/`food_entry` directly. iOS showed 3 pills because it was opened from the Exercise screen (`.exercise` adds "What should I train?") — the pills are screen- **and** time- **and** data-aware, so any pill comparison must control for all three | ok | — |
| Input bar — photo attach | **SHIPPED #1174** (build 96). Android camera control = drawn `CameraShape` (accent when attached, mirroring iOS `camera`→`camera.fill`) → `DriftPlatform.imagePicker` → 52pt thumbnail + remove-X, placeholder flips to "Describe the photo (optional)…", user bubble renders the photo at iOS 200×150. Bytes are mirrored to `ChatPhotoCache` (DriftCore) because SkipUI has no Data→Image path. **Attach needs `uiRefreshKick`** — returning from the picker Activity gives Compose no window change, so without it the thumbnail never paints (#1180 class) | ok | |
| Input bar — mic | iOS `idleControls` adds a mic; Android gates it off (`#if DRIFT_IOS_APP`) pending the SpeechRecognizer seam | deviation | #1178 |
| Input bar | ~~send button disabled precisely when a user reaches for it (`canSend` never re-evaluates while the keyboard is up)~~ — **FIXED, DEVICE-VERIFIED scout #25 (build 96). #1137 is CLOSED.** a11y tree with the keyboard UP and `text="what is my current weight"` in the field: `ai-chat-send enabled="true"`, and the tap sent the turn on the first try. Also confirmed the inverse still holds — with an empty field the glyph greys out and reads `enabled="false"`, which is correct. Char-by-char typing updates the field live | ok | #1137 (closed) |
| Input bar | send GLYPH is a different object: iOS `arrow.up.circle.fill` (filled circle+arrow) vs Android an outlined **paper plane** — `Symbols.swift:110` maps it, device `content-desc="paperplane.fill"`. Contradicts the policy the same file states for `dumbbell`/`flame`/`sparkles`/`timer` ("closest same-meaning icon, never a different object"), each of which got a `Shape` instead | deviation | **#1210** |
| Suggestions row | ⚠ **#1180 is now CLOSED** and this row's "pills paint nothing" verdict predates the fix — but the pills were **not re-driven** in scout #25 (the session went deep on tool content instead). Do not read this as either working or broken until someone taps a pill on ≥ build 97. The old evidence: pills fired but painted nothing until an unrelated recomposition flushed both queued turns at once | unknown | #1180 (closed — needs re-verify) |
| Deterministic turns | RemoteProviderBadge ("via Nebius") renders — device-confirmed again scout #25. #1209 no longer gates tool-backed paths (registry wired). meal-planning / ClarificationCard / Retry still **never driven** | unknown | — |
| Open-ended cloud-LLM turn | **transport + content both confirmed good, scout #25**: replies render with a `via Nebius` badge and real per-user data; logcat `Phase 2 (classify): 5031ms / 6150ms`, `Phase 1 (rules): 0ms`. The old "canned fallback" content verdict is dead with #1209. Latency is the residual — a 5–6s classify on a cloud turn is slow enough to feel, and is unowned (#1226 covers cold start, not turn latency) | deviation (latency) | — |
| Reply CONTENT (all tools) | ~~every turn returns the same canned deflection; ToolRegistry empty on Android~~ — **FIXED and DEVICE-PROVEN scout #25 (builds 96 + 97). #1209 is CLOSED.** `ToolRegistration.registerAll()` is wired at `drift-android/Sources/DriftAndroid/DriftAndroidApp.swift:68`. Driven: `what is my current weight` → *"You're making steady progress this week. Your current weight is 180.1lbs, down 0.5lbs in the last 7 days"* — the real stored value, with a `via Nebius` badge and a `Checking your data…` tool-status string (not the deflection). logcat `⏱ AIToolAgent Phase 2 (classify): 5031ms` / `Phase 1 (rules): 0ms` on subsequent turns. **Drift Coach executes real tools against real user data on Android** | ok | #1209 (closed) |
| Chat history | persists across close (X) → reopen — bubbles + `via Nebius` badges all survive | ok | |
| Chat scroll on reopen | opens scrolled to TOP with the newest turn cut off. **NOT filed as a deviation**: the scroll block (`AIChatView.swift:97-112`) only fires `.onChange(of: messages.count)` on BOTH platforms — there is no `onAppear` scroll-to-bottom for either, so iOS very likely does the same. Needs an iOS side-by-side before anyone calls it Android-only (cf. the sharing-ChatView "opens scrolled-to-top" deferred item) | unknown | — |
| Tool-result cards | 12 of 13 (food/nutrition/weight/workout/nav/supplement/medication/sleep/glucose/biomarker/help) are still `#if DRIFT_IOS_APP` — "text summary only on Android". ⚠ **That safety net does not hold on device**: `AIChatView+ChatBubble.swift:200-203` states *"Every card-emitting turn also carries a text summary, so a card-less bubble still informs"* — scout #25 drove a card-less turn that rendered **no text either**, so the user gets nothing at all (#1232). #1125 and #1232 are independent: shipping all 13 cards would not fix the missing text, and fixing the text would not add the cards | missing | #1125 (+ **#1232**) |
| Proposed-meal card | **PORTED #1174** (`SharedUI/AIChatView+ProposedMealCardAndroid.swift`, mirrors `+Cards.swift:14-89`): header + per-item rows + Edit / Log-all pills. Ported ahead of the other 12 because without Log-all a parsed photo meal is unreachable. Note it renders only when the model emits a `propose_meal` JSON block (`parseProposedMealCard`, text-parsed — NOT `ToolRegistry`, so #1209 doesn't gate it); a prose reply is the iOS behavior too | ok | |
| Weight QUERY tool | **DEVICE-PROVEN scout #25**: `what is my current weight` returns the real stored value with trend (*"180.1lbs, down 0.5lbs in the last 7 days"*), correct against the device DB. This is the one tool confirmed working end-to-end on Android. The follow-up turn rendered a bare `180.1 lbs` fragment where iOS draws a weight card — that residual is #1125 | ok | #1125 (card only) |
| Weight WRITE tool | "saves via DriftCore" — registry is wired now, but a write was **deliberately not driven**: this emulator is shared with the executor + planner lanes and [[harness_shared_emulator_test_writes_poison_state]] is how a phantom row reaches a sibling's screenshots. Needs a seeded/disposable run | unknown | #1125 (card) |
| Activity/workout logging tool | "yes/no confirm → saves" — same: #1209 no longer blocks it, but not driven (write path, shared emulator) | unknown | #1125 (card) |
| Workout start / templates / smart-workout | `ActiveWorkoutView` opens + runs from the Workout tab. The CHAT route is **no longer registry-blocked** (#1209 closed) but was not driven scout #25 — the "Start smart workout" pill sits in the suggestions row whose repaint is itself unverified (row above) | unknown | — |
| Delete-food tool | `FoodService.deleteEntry` works as a service; the chat TOOL is registered now (#1209 closed). Not driven — destructive path on a shared emulator | unknown | — |
| Query / nutrition-lookup tools | ⚠ **the tool now RUNS (#1209 closed) but its answer never PAINTS.** `how much protein did I eat today` → assistant turn renders the sparkle avatar + `via Nebius` badge and **no bubble, no text at all**. iOS, same query / same Nebius / same empty diary, answers *"No food logged yet. Log meals to track protein."* The tool's text is real and ungated (`DriftCore/…/Tools/ToolRegistration.swift:256`) and every `remoteProvider` assignment sets `text` in the same reassignment (`MessageHandling.swift:1602/:1611/:1824`) — so the data is right and the paint is wrong, at the `if !msg.text.isEmpty` conditional (`AIChatView+ChatBubble.swift:164`). Repro 2/2 across builds 96 **and** 97, second one on a fresh first-turn chat | broken | **#1232 (P1)** / #1125 (card) |
| Navigation tool | ⚠ "tab switch WORKS on Android" — still source-only. #1209 no longer blocks it (registry is wired), but `navigate(tab)` was **not driven** this session. Its text is set inline (`"Opening \(label)…"`, `MessageHandling.swift:1418`) so it may escape #1232's empty-bubble path — untested either way | unknown | #1125 (card) |
| Food-logging tools | ~~tools not in the registry, turn never reaches the sheet~~ — **the chat→sheet route WORKS on device, scout #25 (#1209 + #1135 both CLOSED)**: a food-shaped turn fires `openFoodSearch` and `AIChatView.swift:225-231` presents `DescribeMealSheet` seeded with the query. The remaining gap is the *surface*, not the wiring — see the two rows below | ok (route) | #1138/#1139 (surface) |
| Coach → food handoff SURFACE | ⚠ **same routing decision, very different landing.** iOS presents `FoodSearchView` (`AIChatView.swift:159-162`) — an "Add Food" hub with an **editable search field**, an × clear button and live Online Results, immediately actionable. Android presents `DescribeMealSheet(initialQuery:)` which **auto-parses first**; on a parse miss the user gets an error screen and must tap **Try again** to reach an editable "Describe your meal" field. *Recoverable — verified, it is NOT a dead end* — but two extra steps and one alarming error before matching iOS's first screen, and it is a describe/parse box where iOS gives a search box with results. Driven side-by-side with `how much protein have I had today` on both devices | deviation | #1138 / #1135 |
| Coach → food handoff, parse-miss glyph | the parse-miss screen draws a **⚠️ hazard triangle** (`DescribeMealSheet.swift:208` → `Symbols.swift:65` maps iOS's `exclamationmark.bubble` **to** `exclamationmark.triangle`). iOS draws a speech-bubble-with-! there. Directive 0a bans exactly this substitution; 3 call sites share it | broken | **#1233 (P1)** |
| Nested food sheet → Cancel | ⚠ observed **once**: cancelling the Coach's food sheet on Android closed **Drift Coach too** and left the user on the Today tab, where iOS's Cancel returns to the chat with history intact (device-verified on iOS, `ios-06-after-cancel.png`). Logged `unknown` **not** `deviation` — the Android half had a confound (the cancel came from the post-"Try again" input phase, and the app had been reinstalled mid-session), and one confounded observation is not a parity claim. One clean run settles it | unknown | — |
| Voice talk-mode | ImmersiveVoiceView + ListeningCircle + header voiceCluster (speaker/waveform) + mic + TTS — all iOS-only, `CoachVoiceShims` no-ops on Android | missing | #1126 |
| Interview ("set me up") | multi-turn TrainingProfile Q&A → Nebius routine — `handleMultiTurnState` is `#if DRIFT_IOS_APP` | missing | #1125 |
| AI Chat Insights | AIChatInsightsView (#261 opt-in local telemetry) — dev/debug surface | ios-only-by-design | |
| Backend selector / AISetup / AIChooser | Local Brain/Cloud picker + BYOK key-UI (#540) — Android is Nebius-only, no key UI (0-AI-FOCUS) | ios-only-by-design | |
| DriftCoachSheet wrapper | backend-picker sheet wrapper — iOS presents AIChatView inside it; Android presents AIChatView directly | ios-only-by-design | |

## Sharing / Social (single-source: SharedUI/{SharingView,SocialPillRow,CoachPageView,ClientDetailView,PublicProfileSheet,LeaderboardsCard,FocusedSocialViews,CoachSharingCard,CoachBriefingView,CoachMeView,BriefingSnapshot,ChatView,FriendSharePicker,ShareTemplateSheet,SharingDeepLink}.swift ≈4.6k ln · hosted by MoreTab:141 `NavigationLink { SharingView() }` + TodayTab:159 `SocialPillRow()`)

**Section created 2026-08-04 (scout #16) — the area had ZERO rows before today** despite being the
fastest-moving iOS surface of the week (~100 file-touches since 07-28). Every file here is SharedUI
single-source and already compiles + ships in the Android APK; the code is unusually Skip-aware
(Fuse TextField traps gated, `Path`+GeometryReader charts instead of `Charts`, no `contextMenu`/
`swipeActions`, "not private — Fuse can't bridge private @State" notes throughout).

**✅ TRANSPORT IS CLEAR — the "#1194 gates this whole area" premise is dead (scout #21, 2026-08-11,
device-proven on build 89).** This block previously claimed `SyncClient.swift:40` binds
`session = URLSession.shared` and therefore no Android device could ever obtain a sharing identity.
At HEAD that line reads `session: any HTTPDataSession = DriftPlatform.httpSession` — the Android
facade seam — and all three construction sites (`SharingService:18`, `SupportService:80`,
`TelemetryService:25`) take that default. Three independent proofs, all collected 2026-08-11:

1. **The emulator holds a real sharing identity.** `sync_session` has **1 row** — username
   `driftoffline`, uid `cf600644-…`, unexpired GoTrue JWT. (Scout #16 read zero rows on build 80 and
   inferred unreachability; that inference is retired.)
2. **REST reads succeed.** The hub rendered its "No friends yet" empty state, not `couldNotLoadCard`
   — and `connections()` is deliberately NOT `try?` (`SharingView:811`), so a failed fetch would have
   thrown into the error card. Live friend search returned `@neha` from the server.
3. **Writes succeed too.** `telemetry_events` holds **2,412 `platform='android'` rows**, most recent
   2026-08-11 11:02 UTC, through the same `SyncClient`.

So nothing below is transport-blocked. Rows still marked `unknown` are **untested**, and the reason
they're untested WAS a fixture problem. *(Rewritten scout #26, 2026-08-17: **the fixture blocker is
GONE.** A real graph now exists — `driftoffline` (emulator) ↔ `driftscout26` (iPhone 17 Pro sim,
Drift 382 = HEAD), `role=friend status=accepted` — built **through the request/accept UI**, so scout
#21's two-INSERT SQL recipe was never run and is still unused. The iOS sim was signed out, so a
throwaway identity was claimed on it; the operator's `@ashish` account was untouched. This also
discharges #21's residual — every iOS claim in this block is now a genuine side-by-side, not
source-derived.)* **The live blocker is now #1243, not fixtures:** the hub loads connections ONCE per
process and never refetches, so changing the graph on one device and looking at the other shows stale
data even after leaving and re-entering the screen. **Any session driving this block must cold-restart
the app after every graph change**, or it will file false "screen is empty" bugs.

*(Extended scout #27, 2026-08-17: **the fixture now carries the TRAINER edge as well**, so the whole
coach cohort is testable without rebuilding anything. `driftscout26` (iPhone) is the **client**;
`driftoffline` (emulator) is the **coach** — direction matters, `sendRequest(role:.trainer)` writes
`requester_id = client, addressee_id = coach` (`SharingService:170`), so the **iPhone** taps "Ask to
coach me" to put Android in the coach seat. Both edges coexist (migration 0003). The client also
enabled **Average sleep + Weight trend**, so `client_briefings` holds a populated row. **Two traps
for the next session:** (1) there are **two sims named "iPhone 17 Pro"** and only `A8E90B07…`
(iOS 26.5) holds the identity — see the Fixture row; (2) #1243 is no longer the only load hazard —
**#1251** means a cold-restarted hub may STILL show "No friends yet" and `@someone`, so confirm a
load is good before concluding a surface is empty.)*

| screen | sub-interaction | status | issue |
|---|---|---|---|
| Onboarding | **username claim** (`SharingView:119` usernameCard) — TextField + "Claim @x" → `startSharing()` → `signInAnonymously()` → `authPost("signup")`. **WORKS** (scout #21): the emulator holds a claimed identity (`sync_session` = `driftoffline`, valid JWT). The old "parks forever" verdict was an inference from a zero-row table on build 80 — retired | ok | — |
| Onboarding | `.textInputAutocapitalization(.never)` now compiles for BOTH platforms — the three `#if !os(Android)` gates are deleted at `SharingView:126` (claim) + `:569` (friend search) and `FriendSharePicker:74`, which also regains `.autocorrectionDisabled()`. The gates were habit-copied, not workarounds: skip-fuse-ui 1.17.3 declares the modifier (`Text/TextInput.swift:44`) and bridges identifier `0` into skip-ui 1.58.0 → Compose `KeyboardCapitalization.None` (`Text/TextField.swift:355`→`:343`, `TextInput.swift:16`). **Correction to the original filing:** the claim "Android IMEs capitalize the first char → field displays 'Ashish'" is FALSE at these pins — a before-shot on build 102 (hub search field, keyboard raised) showed the AOSP keycaps lowercase with shift disengaged, because no-modifier resolves to `KeyboardOptions.Default` (`TextField.swift:118`), not `.sentences`. The delivered value is therefore explicit forwarded intent (immune to a Skip default change) plus the one genuinely-missing behaviour, `FriendSharePicker`'s autocorrect-off. `FriendSharePicker` search renders only at `connections.count >= 6` (`:30`) so it stays undriven — carried on #1197 | ok | #1196 |
| Onboarding | claim button `.disabled(normalizedUsername.count < 3)` + 20-char/charset normalization | unknown | #1197 |
| Identity | identityCard (`:418`) — @username, avatar (accent-gradient circle, first initial), "Find friends & coaches below" subtitle, "Sign out". **Device-verified rendering** (scout #21). Sign-out itself NOT driven — it deletes the server profile, so it stays untested by choice, not by accident | ok | — |
| Identity | **"Findable by search" toggle paints ON before `load()` resolves** — `@State discoverable = true` (`:53`) + `discoverable = (await listed) ?? true` (`:823`). Device showed ON / "People can find you by @username" for an account whose server row is `discoverable = false`; corrected only after an unrelated keystroke. Fail-open on a privacy control | deviation | #1217 |
| Identity | taglineRow (`:998`) — `TextField(axis:)` absent on Fuse, so Android gets a single-line field (gated, deliberate). Renders as "Add a tagline — what you're into" + pencil; edit path not driven | deviation | #1197 |
| Identity | "Share invite link" row (`:453`) — renders, accent-tinted, correct glyph | ok | — |
| Identity | privacy footnote (`:743`) — full "@username and display name … Everything else stays local" copy renders | ok | — |
| Hub | hub body (`:153`) — signed-in root, `.navigationTitle("Friends")`, back chevron. **Device-verified** | ok | — |
| Hub | peopleStrip (`:492`) — friends list row renders with message / chevron / overflow (iOS horizontal `…`, Android vertical `⋮` = correct idiom). **Device-verified scout #26** once a connection exists | ok | — |
| Hub | managementStrip (`:281`) — promote/demote coach, remove connection. **iOS device-verified scout #27**: the row `…` overflow opens **"Ask to coach me"** (indigo) + **"Unfriend"** (red); promotion writes a real pending trainer edge and leaves the friendship intact. The Android `⋮` equivalent is still undriven | ok | — |
| Hub | searchCard (`:566`) — debounced live search via `.onChange` + `.onSubmit`; generation-counter race guard (`searchGen &+= 1`). **WORKS on device** (scout #21): typing `neha` returned `@neha` with working Add-friend / Coach capsules | ok | — |
| Hub | search **results are buried while the IME is up** — Android lifts the floating `PillTabBar` on top of the keyboard, leaving ~28dp between the field and the bar (a result row is ~60dp). Shell-wide, not Friends-specific: `ContentView.swift:11,50-64` | deviation | #1216 |
| Hub | search field renders as a Material `OutlinedTextField` — stroke box *inside* the `Theme.pillBackground` pill (doubled chrome) + 56dp height floor; the stroke turns saturated accent-pink when focused, so it reads as a validation error. iOS draws no border | deviation | #1204 |
| Hub | search-result action capsules — **NOT a bug** (verified-clean, scout #21): `Add friend` renders black and `Coach` renders indigo because they set `Theme.ink` `#0A0A0A` / `Theme.chartTrend` `#5856D6` explicitly under `.buttonStyle(.plain)` (`:662-671`). Matches iOS; the Material-purple look is the token, not a leak. Do not "fix" | ok | — |
| Hub | FRIENDS empty state (`:769`) — "No friends yet. Search a @username above to add a friend or a coach." Distinct from `couldNotLoadCard`, which is what proves REST succeeded | ok | — |
| Hub | requestsCard (`:685`) — **ANDROID side now device-verified (scout #27)**, discharging #26's residual: `FRIEND REQUESTS` card, avatar, handle, role-correct copy **"wants you as their coach"** (not "sent a friend request"), green ✓ / grey ✕, and **accept flips the server row `pending → accepted`**. **Re-verified 6/6 cold starts on build 106** against a restored pending request (`@driftprobe81 → @driftoffline`, additive INSERT, friendships 22→23): real handle, never `@someone`. `ForEach` over the new `IdentifiedRequest` struct renders correctly on Fuse. A request whose sender fails to resolve is now withheld from the card entirely and reported as "A request couldn't load" + Try again — you are never asked to accept a stranger you can't see | ok | — |
| Hub | incomingTemplatesCard (`:715`) — coach-assigned templates, accept/decline | unknown | #1197 |
| Hub | workoutsFromFriendsCard (`:325`) → ClientSessionDetailView (`:1062`) | unknown | #1197 |
| Hub | expander (`:873`) — collapsed connection lists | unknown | #1197 |
| Hub | couldNotLoadCard (`:895`) — correctly ABSENT on device: `connections()` succeeded, so the empty state showed instead. Its "a parked call never throws" caveat is moot now that the facade returns real errors. Not driven in a genuine failure (airplane mode) yet | unknown | #1197 |
| Hub | invite sheet (`SharingDeepLink:37` InviteShareSheet) — `ShareLink` is text-only on Skip (no file attach); Android-gated `.presentationDetents([.fraction(0.75), .large])` vs iOS `.medium` | ok | — |
| Public profile | `PublicProfileSheet` **stranger variant, `.sheet(item:)` PRESENTS** (scout #26, device): tapping a search result opens the modal with the right payload — the eager-Fuse-builder worry does not bite. Chrome (`Close`/`Profile`), avatar, handle, both CTAs, RECENT ACTIVITY empty state all render. **But the primary CTA 'Send friend request' draws a ⚠️ WARNING TRIANGLE** (`sym("person.badge.plus")` unmapped) → #1244 | deviation | #1244 |
| Today entry | `SocialPillRow` — zero-height `Color.clear` load anchor (iOS-found 07-30 deadlock fix), invite pill when signed-out, Android-gated `.frame(minHeight: 38)` for the hScroll-collapse trap | ok | — |
| Today entry | pills: requests / your-coach / clients / leaderboard. **Device-verified both platforms scout #27** — Android showed "1 request" + "Friends" + "See yourself ranked", then **"Your client"** once the trainer edge landed; iOS showed **"Your coach"**. One role pill each, friends+leaderboard correctly hidden: `friendCount` counts only `.friend` rows and `connections()` dedupes a two-edge person to the coach/client kind (`SharingService:342-356`). Shared behaviour, NOT a missing pill | ok | — |
| Focused | `ClientsView` (`FocusedSocialViews:15`) — **DEVICE-VERIFIED ANDROID scout #27** (first ever): "Your clients" title, client row + "Up to date" subtitle + chevron, and the "Friends, coaches & requests" hub link. Reached from the Today "Your client" pill. **`cc864ed1`:** a failed roster read used to render "Nobody has made you their coach yet" — the #1251 lie, one screen over — and now renders `CouldNotLoadCard` + Try again | ok | — |
| Focused | `LeaderboardView` (`FocusedSocialViews:103`) — board-only screen + "Find friends" empty state. Still undriven (needs a friend-kind connection; the #27 promotion consumed the only one) — **but the fixture now holds a pending friend request from `@driftprobe81`, so ONE tap on the hub's green ✓ creates that edge and opens this screen.** Weigh it: accepting also consumes the request that makes `requestsCard` testable. Code-side, its blind spot is closed — a failed `connections()` used to render "Leaderboards compare you with friends. Add one…", i.e. the #1251 lie one screen over; it now shows `CouldNotLoadCard` (`cc864ed1`) | unknown | #1197 |
| Leaderboards | `LeaderboardsCard` (498 ln, 07-30) — steps/calories/workouts/logging-streak boards; IS Android-gated in 3 places | unknown | #1197 |
| Coach page | `CoachPageView` (189 ln, 07-30) — **iOS reference captured scout #27**: "Your coach" inline title, identity card "@x · coaches you", Message row, and the collapsed CoachSharingCard. **Android side still undriven** — needs the reverse trainer edge (Android as client) | unknown | #1197 |
| Client detail | `ClientDetailView` (469 ln) — **DEVICE-VERIFIED ANDROID scout #27** (first ever), all six sections render: header, "What X shares", `YOUR NOTES` + `CoachNoteComposer` field/Add, "Message @x", `HOW THEY'RE DOING` empty state, `ASSIGN A WORKOUT` + "Build a new workout for @x" CTA + no-templates copy. Note-add and template-assign not fired | ok | — |
| Coach sharing | `CoachSharingCard` (350 ln) — **iOS reference captured scout #27**: collapsed reads "Sharing N of 6" + the enabled list + "See what @x sees"; expanded shows "Set a goal to share" + 7 toggles (full history / history+injuries+goal / sleep / calories+protein / weight trend / body comp / training detail). Toggling two really pushed a populated `client_briefings` row. **Android side needs the reverse trainer edge to be reachable** | unknown | #1197 |
| Coach briefing | `CoachBriefingView` (574 ln, 07-29) — **DEVICE-VERIFIED ANDROID scout #27 in BOTH states.** Empty: the "Nothing shared beyond workouts…" `emptyText` path inside ClientDetailView's card. Populated: workouts/7d tile + **two `BriefingTrendChart` Path charts that really render on Fuse** — Weight (-4.8 lb over 2w, 185.6→180.8) and Sleep, endpoint dots and axis labels correct. **The standing 5-GeometryReader perf worry did NOT bite** — painted with the rest of the screen, no progressive fill (structural verdict per 0-EMULATOR-GPU-CAVEAT). Charts are deliberately `Theme.chartTrend` indigo, not goal-aware green/red (`:558`) — matches iOS, do not "fix" | ok | — |
| Coach me | `CoachMeView` (474 ln) — AI coach-me flow; `CoachDraftField:466` is its own struct with the "Fuse binds only the FIRST TextField per scope" note. Reached from `WorkoutView:510` (NOT transport-gated — this one is drivable today) | unknown | #1197 |
| Briefing data | `BriefingSnapshot` (178 ln) — `metrics(level:)` **exercised end-to-end scout #27**: enabling two share levels on iOS wrote a real `client_briefings` row (9-week `sleep_series`, 2-point `weight_series`, `avg_sleep_hours`, `workouts_completed`) that the Android coach then rendered. See the mirror-vs-coach sleep discrepancy row below | ok | — |
| Chat | `ChatView` (177 ln) — **send + cross-device delivery WORK** (scout #26: typed on Android, received on iOS). Push from the profile's sheet-hosted `NavigationStack` works. **But the list is TOP-anchored** where iOS bottom-anchors — `.defaultScrollAnchor(.bottom)` (`:39`) has no skip-fuse-ui implementation. Discharges the `0-SHARING-DONE` 'opens scrolled-to-top' residual with a root cause | deviation | #1245 |
| Share flows | `ShareTemplateSheet` (68 ln) + `FriendSharePicker` (179 ln, coach-first ordering, search, share-with-all) — reached from `ActiveWorkoutView:1610` | unknown | #1197 |
| Support | `SupportService:80` ("Report a bug") — transport is fine (same client as telemetry, which lands). `support_tickets` holds **0 rows from EITHER platform**, but that is equally consistent with "nobody has filed one" on a single-user app, so `broken` is not provable. Needs one real submit from each platform | unknown | #1197 |
| Telemetry | `TelemetryService:25` — **WORKS.** `telemetry_events` holds **2,412 `platform='android'` rows**, latest 2026-08-11 11:02 UTC. The "uploads never complete" verdict was inherited from the #1194 premise and is false; the MoreTab:61 opt-in toggle governs a pipeline that really is running | ok | — |
| Hub | search-result row **tap target** → opens `PublicProfileSheet` (distinct from the Add friend / Coach capsules on the same row). Device-verified scout #26 | ok | — |
| Hub | **hub never refetches connections** — `.task { await bootstrap() }` (`:97`) is the only load trigger; no `onAppear`, no `scenePhase`. Leaving to More and re-entering does NOT refire it (proof: the typed search text AND its result row survive the round-trip = same view instance). A friend accepted mid-session stays invisible until `am force-stop` + relaunch; iOS refetches. **Cold-start-proven both directions** | broken | #1243 |
| Hub | LEADERBOARDS card (`LeaderboardsCard`) — appears on BOTH platforms once ≥1 connection exists, toggle off by default, explainer copy identical. Device-verified scout #26 (post-cold-start) | ok | — |
| Public profile | **pushed variant** (`SharingView:213`, connected person) — correct: no in-content chrome, Back from the stack; relationship pill / Message / Ask to coach me / Unfriend / RECENT ACTIVITY all render. Plan item 4 ✓ | ok | — |
| Public profile | glyphs: relationship pill `person.2.fill` and "Ask to coach me" `figure.strengthtraining.traditional` BOTH collapse to the same generic single-person icon on Android (iOS: two-person / person-lifting) — the two controls become indistinguishable at a glance | deviation | #1244 |
| Public profile | request round-trip — Android send → "Friend request sent to @x." → arrives on iOS → accept flips the server row to `accepted`. End-to-end verified scout #26 | ok | — |
| Public profile | two-tap confirm (remove/unfriend, `PublicProfileSheet`) — deliberately NOT armed by scout #26: arming it would tear down the graph the rest of the block needs. Plan item 6 | unknown | #1197 |
| Chat | composer bar sits above a white band with a gap before the floating tab bar — **VERIFIED-CLEAN, not a bug**: iOS shows the same gap (composer y≈1475, tab bar y≈1840). Recorded so the next scout doesn't file it | ok | — |
| Chat | `ChatView` nav title renders as a ~44 sp LARGE title (~200 px) where iOS is inline+centred; compounds with the top-anchoring (#1245) so a chat opens on a giant title + the oldest message | deviation | #1200 |
| Identity | "Findable by search" fail-open **REPRODUCED + BOUNDED** (scout #26): same screen ON at 17:56, OFF at 18:01, no interaction. Server row `discoverable=false` since **04 Aug** ⇒ display-only mis-paint, **nothing was written**. The "an incidental tap persists a wrong privacy value" hypothesis is REFUTED | deviation | #1217 |
| Onboarding | **claim flow device-verified on iOS** (scout #26): button disabled+grey while empty, live-updates to "Claim @<handle>" and turns black once ≥3 chars, claim writes a real `sync_session`. Android claim was already `ok`; the two now have a matched reference | ok | — |
| Hub | **profile-derived data intermittently vanishes on load** — **FIXED `cc864ed1` (build 106)**, and the filed mechanism was wrong. A Swift+Kotlin probe on both sides of the JNI bridge showed every `profiles` reply matching byte-for-byte (126B↔126B) with one constant bearer token per pass across 3 cold starts: **no silent empty body, no cross-delivery, no token drift.** The real cause is render ordering — `refreshHub()` assigned `conns` LAST, behind two SERIAL round-trips (`myProfile`, then `recentInbox`) that only started once the six-way fan-out had been consumed, so for ~2s of a ~3.2s load the FRIENDS section rendered its initial `[]` as the confident sentence "No friends yet", and `requestSenders` — assigned on the function's very last line while `requests` is assigned near the top — rendered `@someone` beside role-correct copy. Each bridged round-trip is ~1.05s on the emulator; on iOS the same window is imperceptible, which is why iOS never reproduced. Now: all 8 fetches concurrent, `connections` consumed FIRST (~1.1s to correct paint), a `hubLoaded` gate so the emptiness claim can't render before the load lands, and an unnamed request never rendered as an accept/decline row. **19/19 cold starts correct** | ok | — |
| Today entry | the **"1 request" and "See yourself ranked" pills both render the ⚠️ HAZARD TRIANGLE** on the app's landing screen (`SocialPillRow:94` `person.badge.plus`, `:137` `chart.bar.fill`). Device-proven scout #27 on 102 and 103 — the a11y tree literally labels them `"missing icon"`, which is a free regression assertion for the fix | deviation | #1233 |
| Client detail | "Message @x" row draws a **paper plane (send)** where iOS draws a speech bubble — `Symbols.swift:91` maps `message.fill`/`bubble.left.fill` → `paperplane.fill`. Third confirmed surface for that one mapping (hub row, friend row, ClientDetailView) | deviation | #1233 |
| Identity | tagline row draws a **smiley face** where iOS draws a quote bubble (`Symbols.swift:97` `quote.bubble` → `face.smiling`). Deliberate per its inline comment — it was an escape from a triangle in the #1194 session — but still a different object, on a card #1233 already edits | deviation | #1233 |
| Coach briefing | **the client's "See what @x sees" mirror and the coach's actual view disagree on Sleep** (scout #27): iOS preview "-0.7 h over 9w, 6.9→6.2", Android coach "+0.1 h over 9w, 6.4→6.5", same minute. **Android is faithful** — the stored `client_briefings.sleep_series` is first `6.4` / last `6.5`, unchanged since the push — so the client previews a locally-recomputed series while the coach reads the pushed snapshot. Weight matched exactly. NOT filed: one sample, recompute-between-push-and-preview not ruled out, and it is an iOS/shared issue rather than a parity gap. Re-push and read both within one minute to settle | unknown | — |
| Fixture | **two simulators are named "iPhone 17 Pro"** — the booted `516EAAC8…` (iOS 26.4) is signed OUT; the `@driftscout26` identity lives on `A8E90B07-96C5-45D4-A8F6-B4C5253AFB1D` (iOS 26.5, shutdown by default). Booting the wrong twin makes this whole block look like it regressed to the claim screen. Check `sync_session` in the device's `drift.sqlite` before concluding anything | ok | — |

## Capture (epic #1063 · iOS-only: Drift/Views/PhotoLog/**, BarcodeScannerView)

**Seam split (scout 2026-08-03):** #1128 landed a photo-**LIBRARY** seam (`DriftPlatform.imagePicker.pickLibraryImage`),
NOT live camera. So each capture path is gated differently: **library-pick → parse/review** is buildable NOW
(Snap #1111, WorkoutScan-image #1110); **live camera** (PhotoLog capture, barcode) still needs a separate
AVFoundation/CameraX seam; **PDF** needs SAF (#1109). Ship each path or show an explicit "not yet" state — never a dead control.

| screen | sub-interaction | status | issue |
|---|---|---|---|
| Photo log | capture view — Android's own `CameraCaptureFacade` (TakePicture ActivityResult + FileProvider, #1111, 2026-08-03) now covers live camera too, not just library-pick; verified on-device (permission prompt, capture, confirm, no crash) | ok | #1111 |
| Photo log | flow + review (`SnapMealSheet`, #1111) — capture/analyzing/review/error phases all render; capture screen is a line-for-line port of `PhotoLogCaptureView` (544794c8). Happy path COMPLETES end-to-end since #1177 closed (`861411f8`, build 81): real thali → 7 separated dishes with macros → logged. Review-row macros round rather than truncate (#1218). Residual: review is a read-only list where iOS `PhotoLogReviewView` is fully editable (per-item checkbox / name / amount+unit / 5-up macro grid / totals / Add item) — deliberately deferred, it is P0 #1043's arithmetic surface | partial | #1111 (states shipped) / review depth #1222 / barcode 3rd button #1206 |
| Barcode scanner | scan → food match → log — inherently live-camera; NOT covered by the library-only #1128 seam | missing | #1063 (live-camera seam pending) |
| Workout scan | photo/PDF → template or session (WorkoutScanSheet + ReviewView) — **image path UNBLOCKED** (#1128 seam; `WorkoutScanSheet:102` already routes through it); PDF still #1109-SAF-gated; `blocked` label cleared 2026-08-03 | missing | #1110 (image path unblocked; PDF #1109) |

## Health sub-screens (epic #1068 = INDEX · iOS-only: Drift/Views/{Biomarkers,Glucose,Cycle}/** · scoped ports #1122–#1124)

Source-enumerated 2026-07-28 (scout #6). All data/logic services are DriftCore (portable, views
only render): `BiomarkerService`, `GlucoseService`, `CycleCalculations`, `BiomarkerKnowledgeBase`,
`BiomarkerInsights`, `AIScreenTracker`, `SupplementService`. Three recurring seams: (1) `import Charts`
+ `Canvas` are **Skip-absent** → Path port, precedent `WeightChartAndroid.swift` / `TodayDonutView`
trim-rings; (2) `fileImporter`/`UniformTypeIdentifiers` → Android SAF (#1109); (3) HealthKit reads →
Health Connect (#1070). **No Android UI route exists** for Biomarkers/Glucose/Cycle (verified: only
`HealthConnectService` stubs + seed `biomarkers.json`); honest interim placeholder present (`MoreTab`
"COMING TO ANDROID": "Sleep, cycle & biomarkers detail screens") so no dead taps (#1093). **Supplements
is DONE** — ported to SharedUI, wired `MoreTab.swift:146`; removed from the port queue.

| screen | sub-interaction | status | issue |
|---|---|---|---|
| Biomarkers tab (BiomarkersTabView 513) | empty state (cross.case.fill + Upload CTA) | missing | #1122 |
| Biomarkers tab | status **donut** (`DonutRing`=`Canvas` arc → trim/stroke Path port) + optimal/sufficient/out-of-range legend + last-updated | missing | #1122 |
| Biomarkers tab | PATTERNS cards (`BiomarkerInsights.patterns` — DriftCore; iron/metabolic/thyroid/lipid/inflammation) | missing | #1122 |
| Biomarkers tab | LAB REPORTS list → NavigationLink LabReportDetailView | missing | #1122 |
| Biomarkers tab | search field (live filter name/category) + filter chips (All / Out of Range / Sufficient / Optimal) | missing | #1122 |
| Biomarkers tab | grouped biomarker list (status sections) → NavigationLink BiomarkerDetailView; row = value + status badge + AI-parsed badge + `RangeBar` (GeometryReader — per-scroll recompose, keep cheap) | missing | #1122 |
| Biomarkers tab | toolbar Upload → .sheet LabReportUploadView | missing | #1122 |
| LabReportUploadView (325) | `.fileImporter([.pdf])` → `LabReportOCR.extract(fromPDF:)` (iOS Vision/PDFKit) → preview → Save (`BiomarkerService.save*`, DriftCore). Android = SAF PDF pick (#1109) + Nebius parse (0-AI-LADDER) + local Google tier; NO key UI | missing | #1122 (seam #1109/#1070-adj) |
| BiomarkerDetailView (567) | trend `Chart` (LineMark history — Skip-absent, Path port) + all-recordings list + impact categories/knowledge | missing | #1122 |
| LabReportDetailView (190) | results list + **Delete Report** destructive `.alert` → `BiomarkerService.deleteLabReport` + `LabReportStorage.delete` | missing | #1122 |
| Glucose tab (GlucoseTabView 517) | source Picker (Apple Health / Imported; AH→"Health Connect" on Android per #1095) | missing | #1123 |
| Glucose tab | range chips 1D / 3D / 1W / 2W / 1M / All | missing | #1123 |
| Glucose tab | empty state (waveform.path.ecg; source-specific copy) | missing | #1123 |
| Glucose tab | **glucose Chart**: zone RectangleMarks (70-100 / 100-140 / 140-200) + zone-colored LineMark + spike/dip PointMarks + horizontal ScrollView (Skip-absent → Path port; `UIScreen.main` width iOS-gate) | missing | #1123 |
| Glucose tab | stats card (Average / Range / In Zone) + Fasting/Fat-Burning analysis + Glucose Events (spikes/dips) — all DriftCore logic | missing | #1123 |
| Glucose tab | toolbar Import → `.fileImporter([.csv,.txt])` → `GlucoseService.importLingoCSV` (DriftCore); Android = SAF CSV pick (#1109) | missing | #1123 |
| Glucose tab | Apple Health source → `DriftPlatform.health.fetchGlucoseReadings` — `HealthConnectService` returns [] today | missing | #1123 (dep #1070) |
| Cycle (CycleView 647) | hero/summary (Day N, phase, last/avg/next period) | missing | #1124 |
| Cycle | phase timeline bar (GeometryReader segments + fertile overlay + position dot) + phase labels | missing | #1124 |
| Cycle | Body Signals `Chart` (HRV/RHR multi-series LineMark, catmullRom — Skip-absent, Path port) | missing | #1124 |
| Cycle | Cycle Length trend `Chart` (BarMark + 28-day RuleMark + annotations — Skip-absent, bar port) | missing | #1124 |
| Cycle | Recent Periods history + Advanced Insights `Toggle` (→ `Preferences.cycleFertileWindow`) + fertile-window card + privacy note | missing | #1124 |
| Cycle | ALL data via `DriftPlatform.health` (cycle/ovulation/BBT/spotting/HRV/RHR/sleep) — `HealthConnectService` implements NONE; **empty-state-only until #1070 grows cycle reads** | missing | #1124 (HARD dep #1070) |
| Supplements (SharedUI/SupplementsTabView) | tab + add/edit/delete + adherence bars — **PORTED** (SharedUICopy + `MoreTab.swift:146` sheet) | ok | #1121 (source-confirmed; device-verify pending uncontended window) |

## App shell

| screen | sub-interaction | status | issue |
|---|---|---|---|
| Tab bar | 5 tabs, pill highlight, food glyph reads fork-knife (cart FIXED) | ok | |
| **Startup wiring** | **`DriftAndroidApp` never calls `WeightTrendService.shared.refresh()` or `TDEEEstimator.shared.refresh()`** — iOS does both at `DriftApp.swift:228`/`:233` with a documented ordering contract ("Must run before TDEEEstimator.refresh() since TDEE reads `latestWeightKg`"). Android's only refresh is a side effect of `TodayTab.swift:103`; `TDEEEstimator.refresh()` is called **nowhere** on the platform. iOS *had* this exact bug ("initialized lazily by Dashboard's onAppear — non-Dashboard launch paths got stale values") and fixed it by hoisting to launch; Android is still pre-fix. Impact: 3 consumers read `TDEEEstimator.shared.current?.tdee ?? 2000` (`FoodService:374`, `:794`, `AIRuleEngine:182`), so any launch not passing through Today computes food targets + AI reasoning on a flat 2000 kcal. Same class as #1209 — [[android_startup_wiring_diverges_from_driftapp]] | broken | **#1212 (P0)** |
| Startup wiring | audit residual: no scout has diffed `DriftApp.init()` against `DriftAndroidApp` **call-for-call**. #1209 (tool registration) and #1212 (trend/TDEE refresh) were both found one-at-a-time by symptom; the remaining `DriftApp` launch calls have never been enumerated | unknown | fold into #1212's plan |
| Navigation | push/sheet transition speed + font stability; nav titles render in Material typography, not the app font | deviation | #1074/#1165 |
| Theme | dark/light, goal-aware green/red, Material accent leak | unknown | |
| Network transport | `DriftPlatform.httpSession` (OkHttp facade) — **FIXED, row was stale** (corrected scout #21, 2026-08-11). #1194 taught the facade HTTP methods + response headers and moved ALL DriftCore networking onto the seam: `grep -rn 'URLSession.shared' DriftCore/Sources` returns **3 hits, all in `DriftPlatform.swift`** (2 doc comments + the seam's own iOS default at `:53`) — i.e. exactly one real binding, which is the intended one. The "wired into ONE consumer / POST-only" claim is false at HEAD. Device-proven both directions: GET reads (friend search, `connections()`) and POST writes (2,412 android `telemetry_events`) both land | ok | — |
