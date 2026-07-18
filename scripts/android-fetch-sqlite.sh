#!/usr/bin/env bash
# Fetch the SQLite amalgamation and build static libs for Android ABIs.
# GRDB's GRDBSQLite is a systemLibrary expecting sqlite3.h; the Android NDK
# ships neither headers nor a linkable libsqlite3, so we vendor our own.
# Output: Frameworks/android/sqlite/{sqlite3.h,libsqlite3-<abi>.a}
set -euo pipefail
cd "$(dirname "$0")/.."

SQLITE_URL="${SQLITE_URL:-https://sqlite.org/2026/sqlite-amalgamation-3530300.zip}"
NDK_HOME="${ANDROID_NDK_HOME:-/opt/homebrew/share/android-commandlinetools/ndk/28.2.13676358}"
NDK_BIN="$NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/bin"
DEST=Frameworks/android/sqlite

mkdir -p "$DEST"
cd "$DEST"
if [ ! -f sqlite3.c ]; then
  curl -sO "$SQLITE_URL"
  zip_name=$(basename "$SQLITE_URL")
  unzip -oq "$zip_name"
  dir_name="${zip_name%.zip}"
  mv "$dir_name"/* . && rmdir "$dir_name"
fi

for abi in aarch64-linux-android28 x86_64-linux-android28; do
  # SQLITE_ENABLE_SNAPSHOT: GRDB's Android build references sqlite3_snapshot_*
  # (its DISABLE_SNAPSHOT define is Linux-only) — without this the app .so has
  # unresolved snapshot symbols and dlopen fails at launch.
  "$NDK_BIN/clang" --target=$abi -O2 -fPIC \
    -DSQLITE_ENABLE_RTREE -DSQLITE_ENABLE_JSON1 -DSQLITE_ENABLE_SNAPSHOT \
    -c sqlite3.c -o "sqlite3-$abi.o"
  "$NDK_BIN/llvm-ar" rcs "libsqlite3-$abi.a" "sqlite3-$abi.o"
  echo "built libsqlite3-$abi.a"
done

# Install into the NDK sysroot so every swift-android build on this machine
# (android-build-check.sh, Skip's gradle-driven builds) resolves <sqlite3.h>
# and links -lsqlite3 without needing injected flags — Skip's gradle → swift
# build invocation offers no clean way to pass -Xcc include paths.
SYSROOT="$NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/sysroot"
cp sqlite3.h sqlite3ext.h "$SYSROOT/usr/include/"
cp libsqlite3-aarch64-linux-android28.a "$SYSROOT/usr/lib/aarch64-linux-android/libsqlite3.a"
cp libsqlite3-x86_64-linux-android28.a "$SYSROOT/usr/lib/x86_64-linux-android/libsqlite3.a"
echo "installed sqlite into NDK sysroot: $SYSROOT"
