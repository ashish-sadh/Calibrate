# Third-party asset & data licenses

## Anatomical body model (muscle diagrams)
- **Source:** [react-native-body-highlighter](https://github.com/HichamELBSI/react-native-body-highlighter) (commit `15df9e2d`)
- **License:** MIT — Copyright (c) 2022 ELABBASSI Hicham
- **Usage:** SVG path data extracted by `scripts/extract-body-highlighter.py` into `DriftCore/Sources/DriftCore/Resources/bodyDiagram.json`, rendered natively by `BodyDiagram`/`MuscleBodyView` (#929).

## Exercise pose photos
- **Source:** [free-exercise-db](https://github.com/yuhonas/free-exercise-db)
- **License:** Unlicense (public domain) — no attribution required; noted for provenance.
- **Usage:** start/end pose pairs recompressed to 400px HEIC by `scripts/ingest-exercise-poses.sh` into `Drift/ExercisePoses/` (#929). The exercise catalog (`exercises.json`) derives from the same dataset.
