# Third-party asset & data licenses

## Anatomical body model (muscle diagrams)
- **Source:** [react-native-body-highlighter](https://github.com/HichamELBSI/react-native-body-highlighter) (commit `15df9e2d`)
- **License:** MIT — Copyright (c) 2022 ELABBASSI Hicham
- **Usage:** SVG path data extracted by `scripts/extract-body-highlighter.py` into `DriftCore/Sources/DriftCore/Resources/bodyDiagram.json`, rendered natively by `BodyDiagram`/`MuscleBodyView` (#929).

## Material Symbols glyphs (Android)
- **Source:** [Google Material Symbols](https://fonts.google.com/icons) ("restaurant")
- **License:** Apache License 2.0 — Copyright Google LLC
- **Usage:** SVG path bundled as `drift-android/.../Module.xcassets/fork.knife.symbolset` so the Android food glyph reads as food (skip-ui's built-in Material map has no food icon).

## Exercise pose photos
- **Source:** [free-exercise-db](https://github.com/yuhonas/free-exercise-db)
- **License:** Unlicense (public domain) — no attribution required; noted for provenance.
- **Usage:** start/end pose pairs recompressed to 400px HEIC by `scripts/ingest-exercise-poses.sh` into `Drift/ExercisePoses/` (#929). The exercise catalog (`exercises.json`) derives from the same dataset.
