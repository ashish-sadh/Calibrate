# Shareable cards — leaderboard + finished workout as an image

**Status:** proposal, not started · **Written:** 2026-07-30
**Ask:** "Can we make it a shareable image that can go out to WhatsApp or Insta
story of the leaderboard. Same with finished workout tile."

---

## The privacy decision comes first

This is the part to settle before any code, because it changes the design rather
than the implementation.

**A leaderboard image publishes other people's data to an audience they never
agreed to.** Your friends put their steps on a board visible *to friends* — an
Instagram story is not that. Posting a board with `@asmita 61,203` in it shares
her number with everyone who sees your story, and she has no say and no idea.

That is a different act from every other share in Drift, all of which go to a
person the owner chose.

Three options, in order of how much I'd defend them:

1. **Anonymise everyone but you** *(recommended)*. Your row is named; other rows
   render as `2nd · 61,203` with no handle, or as first-initial avatars. The
   card still shows a real board and a real position — which is what makes it
   worth posting — without publishing anyone's identity. No consent needed,
   because nothing identifying leaves.
2. **Only your own numbers.** A card with your streak/steps and "3rd of 6 among
   friends". Safest, but it stops being a leaderboard and becomes a stat card.
   Probably the right shape for the *workout* card, which is already only about
   you.
3. **Named, with an opt-in bit.** Truthful and social, but needs a new consent
   bit ("let friends include me in shared images"), default off — and a board
   where most people are hidden looks broken.

**Recommendation: (1) for the leaderboard, and the question doesn't arise for
the workout card, which is yours alone.**

Also: the card must never carry body-composition, weight, or anything from the
coach briefing. Steps, calories, workout counts, streaks and a lift number are
fine; those are already the leaderboard's own vocabulary.

---

## What I got wrong, so it doesn't get re-litigated

I said this was blocked on **#1109 (SAF seam)**. It isn't. #1109 is about
*importing* files, which needs an Activity result. Sharing an image *out* uses
`ACTION_SEND` with a `FileProvider` URI and needs no Activity result at all.
Different mechanism, no dependency.

The real constraint is narrower: **SkipUI's `ShareLink` is text-only**
(see [[skipui-sharelink-text-only-no-file]]). That's a SkipUI limitation, not an
Android one — Android's share sheet handles images fine, we just can't reach it
through SkipUI. Which is the same situation `HttpFacade`, `NotificationFacade`
and `HealthConnectFacade` already solve.

---

## Architecture

**One spec, two renderers.** The thing that will rot fastest is two platforms
independently drawing "the same" card and slowly disagreeing. So the card is
described as DATA in DriftCore and each platform only knows how to paint that
description.

```
DriftCore/Sharing/ShareCard.swift
    struct ShareCard {
        enum Size { case story    // 1080×1920
                    case square } // 1080×1080
        var headline: String        // "Food logging streak"
        var subhead: String?        // "last 7 days"
        var rows: [Row]             // rank, label, value, isMe
        var footnote: String?       // "#3 of 6 among friends"
        var accentHex: String
    }
```

Everything about the layout — margins, font sizes, colours — lives in that spec
as constants, so "make the card prettier" is one edit rather than two.

**The seam**, mirroring `DriftPlatform.notifier` exactly:

```
protocol ShareCardRenderer: Sendable {
    @MainActor func share(_ card: ShareCard) async
}
DriftPlatform.shareCards: ShareCardRenderer?
```

Nil on a platform that can't do it, so callers hide the button rather than
showing one that fails — the established rule
([[android-hide-unwired-integration-ui]]).

### iOS

`ImageRenderer` → `UIImage` → `UIActivityViewController`. Roughly half a day
including the card design. `ImageRenderer` renders a SwiftUI view, so the story
card can be a real SwiftUI view built from the spec.

### Android

A fourth Kotlin facade. Two halves:

**Producing the image — draw it natively, don't capture the composable.** The
tempting route is `rememberGraphicsLayer().toImageBitmap()`, but Skip doesn't
expose the graphics layer to Swift and you'd be fighting the toolchain. Painting
onto an Android `Canvas` from the spec is ~100 lines and is *better*: a 9:16
story card looks nothing like the in-app card anyway, and a deterministic
drawing can't break when the SwiftUI view changes.

**Sharing it.** PNG → `cacheDir/shared/` → `FileProvider` `content://` URI →
`ACTION_SEND` chooser. Needs a `<provider>` entry in `AndroidManifest.xml` and a
`res/xml/file_paths.xml`; neither exists yet.

**Trap:** `AnyDynamicObject` cannot call Kotlin `suspend` functions
([[skip-kotlin-interop-suspend-blocker]]). The facade must be blocking or
fire-and-forget. Drawing a bitmap and launching an intent is synchronous, so
this is fine — but don't "improve" it into a coroutine later.

---

## Surfaces

**Leaderboard** — from `LeaderboardsCard`, shares the board currently selected
in the chip strip. Anonymised per the decision above.

**Finished workout** — from the completion sheet, alongside the existing share
switches. Exercise names, sets, best set, duration. This one is entirely the
user's own data, so no anonymisation question.

Both buttons hidden when `DriftPlatform.shareCards == nil`.

---

## Slices

1. `ShareCard` spec + the seam + `DriftPlatform.shareCards` (DriftCore, Tier-0
   testable: spec construction, anonymisation, truncation of long handles).
2. iOS renderer + both entry points. **Shippable alone** — Android hides the
   button.
3. Android facade: Canvas drawing, FileProvider, `ACTION_SEND`.
4. Visual parity pass: same spec, two outputs, compared side by side. Expect
   this to find font-metric differences.

Slice 2 is a legitimate stopping point if Android proves expensive.

---

## Open questions

- **Does the card carry a Drift mark / handle?** A small wordmark is the whole
  growth argument for building this. An `@username` on it is also an invite —
  but see the privacy section; it's the poster's own handle, so it's fine.
- **Story (9:16) or square, or both?** Instagram Stories wants 9:16; WhatsApp is
  agnostic. Both is one extra spec case.
- **Long handles.** `@a_very_long_username_here` will overflow a fixed-width
  card. Truncate in the spec, not in each renderer, or the two platforms will
  truncate differently.
- **Dark mode?** The card is posted outside the app, so it should probably have
  ONE look regardless of the device theme — otherwise the same board produces
  two different images and neither is "the" card.

---

## Estimate

iOS ≈ half a day. Android ≈ a day on top — the Canvas drawing, the FileProvider
plumbing, and a build cycle per mistake (~15 min each on this toolchain). The
fiddly part is not either renderer; it's keeping them producing the same image,
which is what the shared spec exists to contain.
