# Exercise Pose Sourcing — how to add demo animations for new exercises

The app's exercise "gif" is `PoseCrossfadeView`: a 0.9s crossfade between two
bundled HEIC frames (`Drift/ExercisePoses/<Dir>-0.heic` / `<Dir>-1.heic`,
~5–10KB each). No video, no network. An exercise gets its pair via the
`imageUrl` on its catalog entry (`exercises.json`) or custom-registry `fedDir`
(`DefaultTemplates.customExercises`) — the URL is ONLY a bundle key
(`ExercisePoses.assetBaseName` parses `…/exercises/<Dir>/…`); it is never
fetched at runtime.

**The tenet: never a wrong demo.** A pose showing the wrong equipment or
movement is worse than no pose — leave `fedDir` nil (muscle diagram fallback)
until you have an honest one. "Wrong" per operator (2026-07-09): barbell demo
for a dumbbell/band exercise, ankle band for an above-knee band exercise,
static plank for a dynamic plank variation, two-leg demo for a single-leg lift.

## Source ladder (in order)

1. **free-exercise-db** (public domain, already ~870 pairs bundled).
   Check for an *exact* match first — search `exercises.json` names AND the
   upstream repo (github.com/yuhonas/free-exercise-db). If the dir exists but
   isn't bundled, run `scripts/ingest-exercise-poses.sh`.
2. **FitnessProgramer.com** — best coverage of the muscle-figure art style.
   - Search: `https://fitnessprogramer.com/?s=<query>` (needs a browser UA),
     grep exercise page links, then grep the page for
     `wp-content/uploads/....gif`.
   - **Trap:** pages embed related-exercise gifs; the first gif is often the
     WRONG one. Pick the gif whose *filename* matches the exercise name.
3. **GymVisual** — huge library; product pages at
   `gymvisual.com/animated-gifs/<id>-<slug>.html`, gif at
   `gymvisual.com/img/p/...gif` (180px, watermark across the figure — usable
   but flag it). Site search: `gymvisual.com/recherche?controller=search&search_query=…`.
4. **StrongCurves** (`cdn.strongcurves.com/exercises/<slug>.mp4`) — real
   photography, no watermark, glute/band-focused. Extract frames with an
   AVFoundation swift one-liner (no ffmpeg on this machine).
5. **Spotebi** — flat monochrome illustrations, fine as last resort.
6. Wikimedia Commons / wger.de — rarely have specific gym exercises; check
   but don't expect hits. MuscleWiki is Cloudflare-blocked to curl.

Operator has approved using copyrighted demo gifs for in-app poses
(2026-07-09, "don't worry about copyright for a couple of images") — prefer
public-domain/clean sources anyway; keep GymVisual (watermarked) last among
the art-style sources.

## Converting a gif/video to a pose pair

```python
# start = frame 0; end = frame with max RMS pixel diff from start (peak of movement)
from PIL import Image, ImageSequence, ImageChops
import math
frames = [f.convert('RGB') for f in ImageSequence.Iterator(Image.open('x.gif'))]
def rms(a,b):
    h = ImageChops.difference(a.convert('L'), b.convert('L')).histogram()
    return math.sqrt(sum(i*i*c for i,c in enumerate(h))/sum(h))
start = frames[0]; end = max(frames[1:], key=lambda f: rms(start, f))
```

Review the pair BEFORE shipping (build a contact sheet, eyeball it — the
peak-diff heuristic occasionally picks a mirror frame). Then:

```bash
sips -s format heic -s formatOptions 45 -Z 400 <base>-0.jpg \
     --out Drift/ExercisePoses/<Minted_Dir>-0.heic   # and -1
```

## Wiring

- **Minted dir names** for non-FED sources: `Snake_Case` matching the
  exercise (e.g. `Dumbbell_Bulgarian_Split_Squat`, `Wall_Sit`). Set the
  catalog `imageUrl` (or registry `fedDir`) to the standard FED-shaped URL
  with the minted dir — it's just a key.
- Registry customs propagate pose FIXES to existing installs because
  `registerCustomExercises` passes `imageUrlAuthoritative: true` — a changed
  fedDir overwrites the stored one at next launch. Catalog entries re-read
  `exercises.json` every launch, so they just work.
- **Guard tests:** `DriftTests/ExercisePoseAssetTests.swift` fails the build
  if any catalog imageUrl or registry fedDir lacks both bundled frames —
  typos/orphans can't ship silently. Add the HEICs in the same commit as the
  wiring.
- New files under `Drift/ExercisePoses/` need `xcodegen generate`? No — the
  folder ships as a folder reference; but a NEW TEST file does.

## History

- #929: original FED ingest (pose pack + crossfade).
- 2026-07-09: operator-driven correctness sweep — ~25 wrong analogs replaced
  via the source ladder above (band exercises, Bulgarians, cable variants,
  wall sit, hollow hold, suitcase carry, etc.); `imageUrlAuthoritative`
  added; guard tests added.
