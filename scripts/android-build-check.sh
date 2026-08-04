#!/usr/bin/env bash
# Cross-compile DriftCore for Android — the enforced invariant that keeps the
# core portable (the Android analog of the macOS DriftChatSim build proof).
#
# Prereqs (one-time):
#   brew install swiftly && swiftly install 6.3.3       # swift.org toolchain
#   swift sdk install <swift-6.3.3 android artifactbundle>  # see swift.org getting-started
#   sdkmanager "ndk;28.2.13676358" && run the bundle's setup-android-sdk.sh
#   scripts/android-fetch-sqlite.sh                     # vendored sqlite
#
# The Xcode toolchain cannot cross-compile for Android (module-format mismatch
# with the swift.org-built SDK) — this must run the swiftly-managed swift.
set -euo pipefail
cd "$(dirname "$0")/.."

# Recurrence guard (#1120): SkipUI bridges .scrollDismissesKeyboard to a Compose
# nested-scroll connection that eats pointer input inside the scroller, so every
# TextField under it stops taking focus taps. It cost us the workout set fields
# (#1076) and then, one day later, the Edit-Food override macros — an iOS→SharedUI
# port silently re-imported the trap. The defect is invisible until someone drives
# that exact screen, so grep for it on every check instead.
ungated=$(awk '
  FNR == 1 { prev1 = ""; prev2 = "" }
  /\.scrollDismissesKeyboard/ {
    if (prev1 !~ /#if[[:space:]]+!os\(Android\)/ && prev2 !~ /#if[[:space:]]+!os\(Android\)/)
      printf "  %s:%d:%s\n", FILENAME, FNR, $0
  }
  { prev2 = prev1; prev1 = $0 }
' SharedUI/*.swift)
if [ -n "$ungated" ]; then
  echo "android-build-check: ungated .scrollDismissesKeyboard in SharedUI — starves Android TextField focus (#1120):" >&2
  echo "$ungated" >&2
  echo "wrap each in '#if !os(Android)' / '#endif' — see SharedUI/ActiveWorkoutView.swift:297-305" >&2
  exit 1
fi

SWIFT="${SWIFT_ANDROID_SWIFT:-$HOME/.swiftly/bin/swift}"
TRIPLE="${1:-aarch64-unknown-linux-android28}"

if [ ! -x "$SWIFT" ]; then
  echo "android-build-check: swiftly-managed swift not found at $SWIFT" >&2
  exit 1
fi
NDK_HOME="${ANDROID_NDK_HOME:-/opt/homebrew/share/android-commandlinetools/ndk/28.2.13676358}"
if [ ! -f "$NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/sysroot/usr/include/sqlite3.h" ]; then
  echo "android-build-check: sqlite not in NDK sysroot — run scripts/android-fetch-sqlite.sh" >&2
  exit 1
fi

# --target DriftCore: DriftChatSim (macOS CLI, deliberate _exit/CF usage) and
# the test target are not part of the Android surface.
exec "$SWIFT" build \
  --package-path DriftCore \
  --target DriftCore \
  --swift-sdk "$TRIPLE" \
  --scratch-path DriftCore/.build-android
