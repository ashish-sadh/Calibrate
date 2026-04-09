#!/bin/bash
# Run tests with code coverage and enforce minimum threshold.
# Usage: ./scripts/coverage.sh [threshold]
#   threshold: minimum coverage % (default: 40)
#
# Examples:
#   ./scripts/coverage.sh        # enforce 40% minimum
#   ./scripts/coverage.sh 60     # enforce 60% minimum

set -euo pipefail

THRESHOLD=${1:-40}
PROJECT="Drift.xcodeproj"
SCHEME="Drift"
DESTINATION="platform=iOS Simulator,name=iPhone 17 Pro"
RESULT_PATH="/tmp/DriftCoverage.xcresult"

echo "=== Drift Code Coverage ==="
echo "Threshold: ${THRESHOLD}%"
echo ""

# Clean previous result bundle
rm -rf "$RESULT_PATH"

# Kill stale xcodebuild processes
pkill -9 -f xcodebuild 2>/dev/null || true
sleep 2

# Run tests with coverage enabled
echo "Running tests with coverage..."
xcodebuild test \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -only-testing:DriftTests \
    -enableCodeCoverage YES \
    -resultBundlePath "$RESULT_PATH" \
    2>&1 | tail -5

echo ""

# Check if result bundle exists
if [ ! -d "$RESULT_PATH" ]; then
    echo "ERROR: No result bundle found at $RESULT_PATH"
    echo "Tests may have failed to run."
    exit 1
fi

# Extract coverage report
echo "=== Coverage Report ==="
echo ""

# Get overall coverage percentage for the Drift target
COVERAGE_JSON=$(xcrun xccov view --report --json "$RESULT_PATH" 2>/dev/null)

if [ -z "$COVERAGE_JSON" ]; then
    echo "ERROR: Could not extract coverage report"
    exit 1
fi

# Extract Drift.app target coverage (lineCoverage is 0.0-1.0)
DRIFT_COVERAGE=$(echo "$COVERAGE_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for target in data.get('targets', []):
    if 'Drift.app' in target.get('name', ''):
        pct = target['lineCoverage'] * 100
        print(f'{pct:.1f}')
        break
else:
    print('0.0')
")

echo "Drift.app line coverage: ${DRIFT_COVERAGE}%"
echo ""

# Per-directory breakdown
echo "--- Per-file breakdown (top uncovered) ---"
echo "$COVERAGE_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
files = []
for target in data.get('targets', []):
    if 'Drift.app' not in target.get('name', ''):
        continue
    for f in target.get('files', []):
        name = f.get('name', '')
        cov = f['lineCoverage'] * 100
        lines = f.get('executableLines', 0)
        if lines > 10:  # skip tiny files
            files.append((cov, lines, name))

files.sort()
print(f'{'File':<45} {'Coverage':>8}  {'Lines':>5}')
print('-' * 65)
for cov, lines, name in files[:20]:
    print(f'{name:<45} {cov:>7.1f}%  {lines:>5}')
"

echo ""

# Enforce threshold
PASS=$(python3 -c "print('yes' if float('$DRIFT_COVERAGE') >= float('$THRESHOLD') else 'no')")

if [ "$PASS" = "yes" ]; then
    echo "PASS: Coverage ${DRIFT_COVERAGE}% >= ${THRESHOLD}% threshold"
    exit 0
else
    echo "FAIL: Coverage ${DRIFT_COVERAGE}% < ${THRESHOLD}% threshold"
    exit 1
fi
