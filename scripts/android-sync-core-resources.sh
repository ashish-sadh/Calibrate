#!/usr/bin/env bash
# Copy DriftCore's seed resources into the drift-android app module so they
# ship inside the APK. Skip packages only the app module's own Resources/ —
# a dependency package's SwiftPM resource bundle never reaches the APK, and
# marking DriftCore with a Skip/skip.yml would drag the skipstone plugin into
# its Apple builds. CoreResourcesBootstrap extracts these to the directory
# DriftCore's Bundle.module accessor checks at runtime.
#
# The copies are gitignored — run this before any skip build (the
# android-app wrapper does it automatically).
set -euo pipefail
cd "$(dirname "$0")/.."

SRC=DriftCore/Sources/DriftCore/Resources
DEST=drift-android/Sources/DriftAndroid/Resources/DriftCoreSeed
mkdir -p "$DEST"
cp "$SRC"/foods.json "$SRC"/exercises.json "$SRC"/biomarkers.json "$SRC"/bodyDiagram.json "$DEST/"
echo "synced $(ls "$DEST" | wc -l | tr -d ' ') seed files into $DEST"

# Materialize SharedUI (the single-source cross-platform SwiftUI) into the
# module. skipstone's bridge generation does not follow directory symlinks —
# these copies are build artifacts (gitignored); SharedUI/ is the only
# editable location.
UIDEST=drift-android/Sources/DriftAndroid/SharedUICopy
mkdir -p "$UIDEST"
rm -f "$UIDEST"/*.swift
cp SharedUI/*.swift "$UIDEST/"
echo "synced $(ls "$UIDEST" | wc -l | tr -d ' ') SharedUI files into $UIDEST"
