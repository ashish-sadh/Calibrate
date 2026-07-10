# Body Diagram — anatomical muscle-highlight figures (design doc)

The recovery map (Workout tab) and the exercise-detail muscle diagrams render
a human figure with per-muscle highlight fills. This documents where the
artwork comes from, how it was built, and how to change it.

## Source

**react-native-body-highlighter** — github.com/HichamELBSI/react-native-body-highlighter
(MIT, © 2022 ELABBASSI Hicham), pinned to commit `15df9e2dbc621450001960bed5a30e6a75357faa`.

Files taken:
- `assets/bodyFront.ts`, `assets/bodyBack.ts` — male muscle region SVG paths
- `assets/bodyFemaleFront.ts`, `assets/bodyFemaleBack.ts` — female regions
- `components/SvgMaleWrapper.tsx`, `SvgFemaleWrapper.tsx` — body silhouette outlines

We do NOT depend on the npm package — the data was extracted once into a
bundled JSON. Attribution lives in the JSON header (`source`, `commit`,
`license`) and in `BodyDiagram.swift`'s doc comment.

## Build pipeline (#929)

`scripts/extract-body-highlighter.py` (re-runnable; fetches from GitHub):

1. Downloads the four asset files + two wrappers at the pinned commit.
2. Normalizes every SVG path to **absolute M / L / C / Z only** (H,V→L;
   Q→C; S,T expanded; arcs→cubic Béziers) so the Swift parser stays tiny.
3. Translates each view so its viewBox starts at (0,0) (the source back view
   lives at x+724; female views at −50/−40 and 756).
4. Emits `DriftCore/Sources/DriftCore/Resources/bodyDiagram.json`:

```json
{ "source": "react-native-body-highlighter", "commit": "15df9e2d…", "license": "MIT",
  "models": { "maleFront":  {"viewBox": [724,1448], "outline": ["M…"], "muscles": {"chest": ["M…"], …}},
              "maleBack": …, "femaleFront": …, "femaleBack": … } }
```

## Runtime

- **`DriftCore/…/Workout/BodyDiagram.swift`** — loads the JSON once
  (`models`), `SVGPathParser` (M/L/C/Z only) builds `CGPath`s.
  - `librarySlugs(forDriftMuscle:)` maps Drift's 17 catalog muscle names →
    library slugs (`lats`/`middle back` → the single `upper-back` region).
  - `userGender`: profile sex female → female figure; male/unset/N-A → male
    (2026-07-09 inclusivity). Decodes just the `sex` field of
    `drift_tdee_config` so it stays callable off the main actor.
- **`Drift/Views/Workout/MuscleHighlightCard.swift`** — `MuscleBodyView`
  draws one side in a single SwiftUI `Canvas` (fill per muscle slug, stroke
  the outline). Never one view per path (~80 paths/side).
  `gender` defaults to `BodyDiagram.userGender`, so every call site follows
  the profile automatically.
- Consumers: `BodyMapView` (recovery colors via `slugColors`),
  `MuscleHighlightCard` (primary/secondary highlight + MuscleInfo line).

## Data quirks (verified against upstream — do not "fix")

- `abductors` has **no region** in the v3 data (upstream README claims one —
  stale). `librarySlugs` returns `[]` → nothing highlights rather than lying.
- The **female back** model has no `head`/`ankles` slivers — its artwork
  draws those areas as `hair` and `feet`. Nothing is visually missing;
  operator question 2026-07-09, checked against the pinned source.
- viewBoxes differ per model (male 724×1448, femaleFront 734×1538,
  femaleBack 774×1448) — scaling is per-model in the Canvas, so this is fine.

## Guard tests

`DriftCore/Tests/DriftCoreTests/BodyDiagramTests.swift`:
- parser/model sanity + `UserGenderFigureTests` (sex mapping male/female/unset)
- `femaleModelsCoverEveryMappedMuscleSlug` — the female models must cover
  every slug `librarySlugs` can produce, so a re-extraction can't silently
  un-highlight muscles for women.

## Updating the artwork

Re-run `python3 scripts/extract-body-highlighter.py` (bump the pinned commit
inside the script first if you want newer upstream art), then run the
BodyDiagram test suite. If upstream renames slugs, update
`librarySlugs(forDriftMuscle:)` and the coverage test together.

## Related

- Exercise demo pose photos are a separate system — see
  `Docs/exercise-pose-sourcing.md` (free-exercise-db HEIC pairs + web-sourced
  additions, `PoseCrossfadeView`).
