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
