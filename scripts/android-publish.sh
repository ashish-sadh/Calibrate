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

# Clean the Android build tree — stale outputs after a version change cause
# "Duplicate resources" merger failures (seen 2026-07-18).
rm -rf drift-android/.build/Android drift-android/.build/skip-export

(cd drift-android && skip export --plain) || true  # iOS-side sub-steps may fail; the AAB is what matters

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
