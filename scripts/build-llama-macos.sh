#!/bin/bash
# Build llama.cpp macOS arm64 framework and add it to the xcframework.
# Matches the iOS build: static libs merged into a single dynamic framework.
# Usage: bash scripts/build-llama-macos.sh

set -e
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMMIT="69c28f1"
SRC="/tmp/llama-src"
BUILD="$SRC/build-macos"
FRAMEWORK_OUT="$SRC/llama-macos.framework"
XCFW="$REPO_ROOT/Frameworks/llama.xcframework"
BACKUP="$REPO_ROOT/Frameworks/llama.xcframework.bak"

echo "=== Step 1: Clone llama.cpp at $COMMIT ==="
if [ -d "$SRC/.git" ]; then
    echo "Source already cloned, fetching..."
    git -C "$SRC" fetch --quiet
else
    git clone --quiet https://github.com/ggerganov/llama.cpp "$SRC"
fi
git -C "$SRC" checkout "$COMMIT" --quiet
echo "Checked out $COMMIT"

echo "=== Step 2: Build macOS arm64 static libs ==="
cmake -S "$SRC" -B "$BUILD" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DCMAKE_BUILD_TYPE=Release \
    -DGGML_METAL=ON \
    -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_BUILD_EXAMPLES=OFF \
    -DLLAMA_BUILD_SERVER=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DGGML_STATIC=ON \
    -DLLAMA_STATIC=ON \
    -Wno-dev 2>&1 | tail -5

cmake --build "$BUILD" -j"$(sysctl -n hw.logicalcpu)" --target llama ggml 2>&1 | tail -10

echo "=== Step 3: Collect static libs ==="
LIBS=$(find "$BUILD" -name "*.a" | grep -v test | tr '\n' ' ')
echo "Libs: $LIBS"

echo "=== Step 4: Create macOS dynamic framework ==="
rm -rf "$FRAMEWORK_OUT"
mkdir -p "$FRAMEWORK_OUT/Headers" "$FRAMEWORK_OUT/Modules"

# Copy headers from iOS framework (same headers, platform-neutral C API)
cp "$XCFW/ios-arm64/llama.framework/Headers/"* "$FRAMEWORK_OUT/Headers/"
cp "$XCFW/ios-arm64/llama.framework/Modules/"* "$FRAMEWORK_OUT/Modules/" 2>/dev/null || true

# Link all static libs into a single dylib
clang++ -dynamiclib \
    -arch arm64 \
    -mmacosx-version-min=14.0 \
    -framework Foundation \
    -framework Metal \
    -framework MetalKit \
    -framework Accelerate \
    -Wl,-all_load $LIBS \
    -o "$FRAMEWORK_OUT/llama" \
    2>&1 | tail -5

# Write Info.plist
cat > "$FRAMEWORK_OUT/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>llama</string>
    <key>CFBundleIdentifier</key><string>com.drift.llama</string>
    <key>CFBundleName</key><string>llama</string>
    <key>CFBundlePackageType</key><string>FMWK</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>MinimumOSVersion</key><string>14.0</string>
</dict></plist>
PLIST

echo "=== Step 5: Rebuild xcframework with macOS slice ==="
cp -r "$XCFW" "$BACKUP"
echo "Backed up xcframework to $BACKUP"

MACOS_FRAMEWORK_DIR="$SRC/macos-arm64-framework"
rm -rf "$MACOS_FRAMEWORK_DIR"
mkdir -p "$MACOS_FRAMEWORK_DIR"
cp -r "$FRAMEWORK_OUT" "$MACOS_FRAMEWORK_DIR/llama.framework"

xcodebuild -create-xcframework \
    -framework "$XCFW/ios-arm64/llama.framework" \
    -framework "$XCFW/ios-arm64_x86_64-simulator/llama.framework" \
    -framework "$MACOS_FRAMEWORK_DIR/llama.framework" \
    -output "/tmp/llama-new.xcframework"

rm -rf "$XCFW"
mv "/tmp/llama-new.xcframework" "$XCFW"

echo "=== Done! xcframework now has macOS arm64 slice ==="
echo "Platforms:"
ls "$XCFW/"
