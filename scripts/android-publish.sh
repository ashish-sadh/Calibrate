#!/usr/bin/env bash
# Publish the Android app to Play Internal Testing — the TestFlight-equivalent
# pipeline. Mirrors the iOS testflight-publish flow: bump versionCode, build a
# signed release AAB via skip export, verify the bundle, upload to the internal
# track via fastlane supply.
#
# One-time prereqs:
#   - Play app exists with a first manually-uploaded bundle (done 2026-07-18)
#   - Service-account JSON with "Release to testing tracks" permission at:
#       ~/drift-state/android-keys/play-service-account.json
#   - ~/drift-state/android-keys/keystore.properties copied to
#       drift-android/Android/app/ (upload-key signing)
#   - brew install fastlane bundletool
set -euo pipefail
cd "$(dirname "$0")/.."

# One publish at a time — two concurrent runs race the versionCode bump
# (seen 2026-07-18: both bumped, one commit, mislabeled build number).
LOCK=/tmp/drift-android-publish.lock
if ! mkdir "$LOCK" 2>/dev/null; then
  echo "android-publish: another publish is running ($LOCK exists)" >&2
  exit 1
fi
trap "rmdir $LOCK" EXIT

JSON_KEY="$HOME/drift-state/android-keys/play-service-account.json"
export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk}"
export ANDROID_HOME="${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}"

if [ ! -f "$JSON_KEY" ]; then
  echo "android-publish: missing $JSON_KEY" >&2
  echo "Create it: Play Console → Setup → API access → service account → JSON key" >&2
  exit 1
fi

# Bump versionCode (Skip.env is the single source of truth for both platforms' metadata).
CUR=$(grep -E '^CURRENT_PROJECT_VERSION = ' drift-android/Skip.env | awk '{print $3}')
NEXT=$((CUR + 1))
sed -i '' "s/^CURRENT_PROJECT_VERSION = $CUR\$/CURRENT_PROJECT_VERSION = $NEXT/" drift-android/Skip.env
echo "versionCode: $CUR → $NEXT"

./scripts/android-sync-core-resources.sh

# Clean ONLY the packaging/staging outputs, NOT the Swift compile cache.
# History: this used to be `rm -rf .build/Android .build/skip-export` (for the
# 2026-07-18 "Duplicate resources" merger failure), which made every publish a
# fully COLD release build — by 2026-07-30 that meant 2h10m (the whole Swift
# world at -O, ×4 ABIs). The duplicate-resources bug was root-fixed by
# `--release` below (no more debug+release double-write), so the blanket nuke
# is redundant; scoping it to jni-libs staging + the export dir keeps the
# compiled Swift objects warm (~10-15 min publishes). If a publish ever fails
# with "Duplicate resources" again, the fallback is the old full nuke:
#   rm -rf drift-android/.build/Android drift-android/.build/skip-export
rm -rf drift-android/.build/skip-export drift-android/.build/Android/DriftAndroid/jni-libs

# --release: a plain `skip export` runs `gradle assemble`, which builds the
# debug AND release variants in one invocation. Both variants' Swift builds
# write into the same jni-libs dir (debug: arm64 only; release: all ABIs), and
# the release jni-lib merge then fails with "Duplicate resources" where each
# file conflicts with ITSELF (seen 2026-07-28/29, 8 failed publish attempts).
# Building only the release variant removes the double-write entirely.
# --arch aarch64: every tester phone is arm64 (Pixel 2 up); x86/x86_64 exist
# only on emulators, which install debug builds — never this AAB. Building one
# ABI instead of four cuts the release Swift compile ~4× (2026-07-30: the
# 4-ABI AAB was 205 MB and took 2h10m cold).
# --no-ios: this pipeline only needs the AAB; skip the iOS .ipa export.
# --no-export-project: the project-source zip chokes on GRDB's recursive
# Tests/CustomSQLite symlink loop and wastes ~150 MB; publish never needs it.
(cd drift-android && skip export --release --no-ios --no-export-project --arch aarch64 --plain) || true  # non-AAB sub-steps may fail; the AAB is what matters

AAB=drift-android/.build/skip-export/DriftAndroid-release.aab
if [ ! -f "$AAB" ]; then
  echo "android-publish: no AAB produced — check skip export output" >&2
  exit 1
fi
GOT=$(bundletool dump manifest --bundle "$AAB" | grep -o 'versionCode="[0-9]*"' | head -1)
if [ "$GOT" != "versionCode=\"$NEXT\"" ]; then
  echo "android-publish: AAB has $GOT, expected $NEXT — stale build, aborting" >&2
  exit 1
fi

fastlane supply \
  --aab "$AAB" \
  --track internal \
  --package_name com.drift.health \
  --json_key "$JSON_KEY" \
  --skip_upload_metadata --skip_upload_images --skip_upload_screenshots

git add drift-android/Skip.env
git commit -m "chore(android): publish build $NEXT to Play internal testing

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
echo "android-publish: build $NEXT uploaded to the internal track"
