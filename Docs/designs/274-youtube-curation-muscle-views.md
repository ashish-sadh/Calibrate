# Design: Exercise Video Curation + Muscle-Focused Visuals

> References: Issue #274 | Related prior art: #133 (exercise-enrichment), Docs/designs/133-exercise-enrichment.md

## Problem

Users who open an exercise detail today see a static JPG from the free-exercise-db thumbnail (932/966 exercises have one) and — for 33 cherry-picked exercises — a YouTube link. The gap has two shapes:

1. **Video coverage is thin.** Only 33 of ~966 exercises (~3%) link to a demo video. The long tail (hip thrust variations, cable machine attachments, mobility drills) gives users a still image and nothing else.
2. **A still image doesn't show the working muscle.** The user's request is more specific than "more videos": they want the *muscle in motion* — a skeleton/figure animation with the target muscle highlighted. That's a different visual primitive than a YouTube demo. A demo shows form; a muscle-highlight animation shows *what's being trained*.

These are related but distinct. A good design has to decide where each one fits in the exercise detail view, and how to produce the content without a paid team of animators.

Affected surface: `ExerciseDetailView` (Drift/Views/Workout/ExerciseBrowserView.swift:185), `ExerciseInfo` (Drift/Services/ExerciseDatabase.swift:5), `exercises.json`.

## Proposal

Two parallel tracks, both driven by a small amount of one-time curation work, no runtime API calls, no cloud.

**Track A — YouTube curation expansion.** Grow `youtubeUrl` coverage from 33 → ~300 (the exercises that account for >95% of user logs in a typical strength program). Manual curation, stored as flat URLs in `exercises.json`, opened via `SFSafariViewController` (already wired). Scope-boxed by a priority list.

**Track B — Muscle-highlight visual.** Render a simple front+back anatomy figure with the primary muscle(s) tinted, **computed from the `primaryMuscles` field we already have**. Not fetched, not stored as an asset — drawn live from an SF-Symbols-style vector body map. Zero per-exercise curation work: every one of the 966 exercises gets a muscle diagram automatically. This is the biggest leverage point.

Out of scope: licensed 3D animations (expensive, no open source with permissive licensing, violates offline-first), on-device video generation (too slow on A19), per-user custom form videos.

## UX Flow

### Exercise Detail (post-change)

```
┌────────────────────────────────────┐
│   [Bench Press]                    │
│                                    │
│   ┌──────────┬──────────┐          │  ← New muscle-highlight card
│   │  FRONT   │   BACK   │          │    (Track B — every exercise)
│   │  figure  │  figure  │          │
│   │ (chest   │ (tinted  │          │
│   │ tinted)  │ nothing) │          │
│   └──────────┴──────────┘          │
│   Targets: Pectoralis Major        │
│   Assists: Front Delts, Triceps    │
│                                    │
│   [ Watch form video ▶ ]           │  ← Track A — if youtubeUrl present
│                                    │
│   [Thumbnail GIF/JPG] (existing)   │
│                                    │
│   Equipment · Level · Category     │
└────────────────────────────────────┘
```

Priority ordering: **muscle card first** (always present, no network), **video second** (opt-in, requires network), **thumbnail last** (legacy). If the muscle card renders, the thumbnail JPG becomes less necessary; we keep it for now to smooth the rollout.

### AI chat integration

When the AI explains "what muscles does the bench press work", it can reference the same muscle-highlight image by issuing a `showMuscleMap(exercise:)` tool call — no separate asset fetch needed.

```
User: "what does bench press work?"
AI: "Bench press primarily trains your pectoralis major, with front delts and
     triceps assisting. Here's the muscle map:" [renders muscle card]
```

## Technical Approach

### Track A — YouTube curation (the "how to curate" question)

**Source of truth.** Extend `exercises.json` in-place with a `youtubeUrl` field (already optional in `ExerciseInfo`). No new tables, no new files, no new fetches.

**Curation process** (one-time, repeatable):

1. Rank exercises by expected frequency using the existing `free-exercise-db` category/equipment distribution plus the logged-exercise data we already track (table `workout_exercise_usage` via `ExerciseService`). Take the top 300.
2. For each exercise, the curator searches YouTube for `"{exercise name} proper form"` and picks from a pre-vetted channel allowlist: Alan Thrall, Jeff Nippard, Renaissance Periodization, Athlean-X, Squat University, Mind Pump. These are quality-stable and embed-friendly.
3. Paste the watch URL directly into `exercises.json`. Use full `https://www.youtube.com/watch?v=...` form (not shortened) — parses reliably with `URL(string:)`.
4. Commit in batches of 50. Each batch is one PR so review is tractable.

**Tooling to make this less painful.** A small CLI `scripts/exercise-video-curate.py`:
- Reads `exercises.json`, filters to entries missing `youtubeUrl` in the top-N list.
- For each, opens a YouTube search in the default browser (`open`) and prompts for a URL.
- Writes back in sorted, formatted JSON so diffs stay clean.
- 300 entries × ~30s each = ~2.5 hours of curator time. Doable in a few sessions.

**What we do NOT do:** no YouTube Data API, no server, no periodic sync. The links are static JSON shipped with the app.

### Track B — Muscle-highlight visual (the real win)

**Rendering primitive.** A SwiftUI view `MuscleHighlightView(primary: [MuscleGroup], secondary: [MuscleGroup])` that draws two body silhouettes (front + back) with Path/Shape, tinted per muscle group. Implementation options ranked by effort:

1. **SVG body map → SwiftUI `Path`** (recommended). Use a free anatomy SVG like the ones from `musclewiki` (CC-BY) or `exrx` (check license). Split into ~30 named paths (one per muscle group). At runtime, union the paths corresponding to `primaryMuscles` and fill them with `Theme.accent`; secondary muscles get `Theme.accent.opacity(0.4)`. All other paths stay muted.
2. **Pre-rendered PNG atlases.** Ship one front + one back master image, one PNG mask per muscle group (~25 masks × ~10KB = 250KB asset budget). Composite at runtime. Simpler than paths but bigger binary.
3. **SceneKit 3D model.** Out of scope — too heavy, binary blowup, rendering inconsistency across devices.

Recommendation: **option 1**. The Exercise model's `primaryMuscles` field (already populated for all 966 exercises) maps directly to the named SVG paths. Matching free-exercise-db's muscle taxonomy (`chest`, `lats`, `traps`, `hamstrings`, …) to the SVG's muscle paths is a one-time ~30-line lookup table. After that, every exercise lights up correctly with no per-exercise work.

**Animation (optional stretch).** Start static. The user's ask mentions "skeleton doing exercises" — true motion animation is a much bigger ask (custom per-exercise keyframes, rigging). Starting with a static *muscle highlight* delivers ~80% of the pedagogical value at <5% of the cost. If usage shows people wanting motion, revisit with a focused Lottie-based approach on the top 30 lifts.

**Files/services touched.**
- New: `Drift/Views/Workout/MuscleHighlightView.swift` — the vector-body SwiftUI view.
- New: `Drift/Resources/body-map.svg` + parser helper (or hardcoded Path arrays if small enough).
- New: `Drift/Services/MuscleMapping.swift` — maps free-exercise-db muscle strings to SVG path names.
- Edit: `ExerciseBrowserView.swift:185` (`ExerciseDetailView`) — insert the card above the existing thumbnail.
- Edit: `Docs/tools.md` + `AIToolAgent.swift` — register `showMuscleMap` tool.

**Dual-model fit.** SmolLM doesn't call tools, so the muscle-map tool lives in Gemma's toolset. SmolLM users still see the card in `ExerciseDetailView` — the visual is independent of the LLM.

**Performance.** Draw once on appear, no network, no cache. <16ms on a mid-tier iPhone for two vector silhouettes with ~30 paths each.

## Edge Cases

- **Exercises with no primary muscle** (e.g., generic "Cardio"). Render a grayed-out body with a "full-body / cardio" label instead of empty tint.
- **Compound lifts with many primary muscles** (e.g., deadlift). Highlight *all* primary muscles; designer picks a visual saturation that stays readable with 4–5 muscles lit.
- **Stretches and mobility drills** that target soft tissue (fascia, ligaments). Fall back to a single-color tint on the involved region — label reads "mobility/stretch" so expectation is set.
- **YouTube URL rot.** Videos get taken down. Track A accepts this — missing video = just no play button. No fallback needed; the muscle card carries the weight.
- **Muscle name mismatches.** free-exercise-db uses lower-case plain-English (`"lower back"`); SVG paths might use Latin (`"erector_spinae"`). The mapping table handles the translation; any unmapped name logs once and falls through to "primary muscle" generic.
- **Kids' / adaptive users.** Body silhouette is a neutral adult outline; we should pick an SVG that doesn't look gendered or hyper-muscled. A "basic athletic" figure reads best.

## Open Questions

1. **Curator.** Who curates the 300 YouTube URLs? If it's the founder (ashish-sadh), ~2.5h of work split across sessions. If it's delegated, we need a channel allowlist + a rubric for "good form video" (no ads in first 10s, clear angle, no overdub music).
2. **License for the body-map SVG.** Preferred candidates: `musclewiki-icons` (CC-BY), Wikimedia Commons' "Gray's Anatomy" line art (public domain but dated aesthetic), `BioDigital` (paid). Need to confirm CC-BY is acceptable with one-line attribution in About.
3. **Secondary muscle visibility.** Do we tint secondary muscles at a lower opacity, or omit them entirely? Proposal: tint at 40% — it lets users see assist patterns, but falls behind the primary. Easy to dial after the first usable build.
4. **Where does the muscle card live for AI chat?** Inline in chat as an image bubble, or as a tap-through sheet? Proposal: inline in chat (under 120pt tall), tap expands to full detail. Matches the existing nutrition-lookup card pattern.
5. **Ordering of the tracks.** Track B (muscle card) is higher leverage — it covers all 966 exercises once, versus Track A which covers 300 with ongoing curation. Proposal: **ship Track B first**, then Track A in a follow-up sprint.

---

*To approve: add `approved` label to the PR. To request changes: comment on the PR.*
