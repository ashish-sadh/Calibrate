# Third-party asset & data licenses

## Anatomical body model (muscle diagrams)
- **Source:** [react-native-body-highlighter](https://github.com/HichamELBSI/react-native-body-highlighter) (commit `15df9e2d`)
- **License:** MIT — Copyright (c) 2022 ELABBASSI Hicham
- **Usage:** SVG path data extracted by `scripts/extract-body-highlighter.py` into `DriftCore/Sources/DriftCore/Resources/bodyDiagram.json`, rendered natively by `BodyDiagram`/`MuscleBodyView` (#929).

## Material Symbols glyphs (Android)
- **Source:** [Google Material Symbols](https://fonts.google.com/icons) ("restaurant", "schedule")
- **License:** Apache License 2.0 — Copyright Google LLC
- **Usage:** SVG paths hand-converted to SwiftUI `Path` shapes (`drift-android/.../FoodGlyph.swift`, `ClockGlyph.swift`) — Skip Fuse builds drop `.xcassets` symbolsets from the APK, and skip-ui's built-in Material map has no food or clock icon.

## Nunito font (Android)
- **Source:** [Nunito](https://fonts.google.com/specimen/Nunito) — Vernon Adams, Cyreal, Jacques Le Bailly
- **License:** SIL Open Font License 1.1
- **Usage:** `nunito_semibold.ttf` + `nunito_bold.ttf` bundled at `drift-android/Android/app/src/main/res/font/` as the Android stand-in for SF Rounded (`Theme.rounded` — skip-ui maps `design: .rounded` to plain Roboto, #1074).

## Exercise pose photos
- **Source:** [free-exercise-db](https://github.com/yuhonas/free-exercise-db)
- **License:** Unlicense (public domain) — no attribution required; noted for provenance.
- **Usage:** start/end pose pairs recompressed to 400px HEIC by `scripts/ingest-exercise-poses.sh` into `Drift/ExercisePoses/` (#929). The exercise catalog (`exercises.json`) derives from the same dataset.
