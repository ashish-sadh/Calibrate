#!/bin/bash
# Coverage check script for Drift
# Run after: xcodebuild test ... -enableCodeCoverage YES -resultBundlePath /tmp/DriftCoverage.xcresult
#
# Thresholds:
#   Services (pure logic, calculators, parsers): 80%
#   ViewModels: 50%
#   Database: 50%
#
# Usage: ./scripts/coverage-check.sh [--fail]
#   --fail: exit with code 1 if any file is below threshold

set -e

RESULT_BUNDLE="/tmp/DriftCoverage.xcresult"
FAIL_MODE=false

if [ "$1" = "--fail" ]; then
    FAIL_MODE=true
fi

if [ ! -d "$RESULT_BUNDLE" ]; then
    echo "❌ No coverage data. Run tests with -enableCodeCoverage YES first:"
    echo "   pkill -9 -f xcodebuild 2>/dev/null; sleep 2"
    echo "   rm -rf /tmp/DriftCoverage.xcresult"
    echo "   xcodebuild test -project Drift.xcodeproj -scheme Drift -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:DriftTests -enableCodeCoverage YES -resultBundlePath /tmp/DriftCoverage.xcresult"
    exit 1
fi

echo "📊 Drift Code Coverage Report"
echo "=============================="
echo ""

# Get overall coverage
OVERALL=$(xcrun xccov view --report "$RESULT_BUNDLE" --only-targets 2>/dev/null | grep "Drift.app" | awk '{print $4}')
echo "Overall: $OVERALL"
echo ""

FAILURES=0

# Pure logic / calculators — 80% threshold
echo "🔬 Pure Logic (target: 80%)"
echo "---"
for file in WeightTrendCalculator PlantPointsService AIActionExecutor AIResponseCleaner CSVParser CycleCalculations SpellCorrectService; do
    LINE=$(xcrun xccov view --report "$RESULT_BUNDLE" 2>/dev/null | grep "Services/${file}.swift\|Utilities/${file}.swift" | head -1)
    if [ -n "$LINE" ]; then
        PCT=$(echo "$LINE" | grep -oE '[0-9]+\.[0-9]+%' | head -1 | tr -d '%')
        if [ -n "$PCT" ]; then
            if (( $(echo "$PCT < 80" | bc -l) )); then
                echo "  ❌ ${file}: ${PCT}% (below 80%)"
                FAILURES=$((FAILURES + 1))
            else
                echo "  ✅ ${file}: ${PCT}%"
            fi
        fi
    fi
done
echo ""

# Services — 50% threshold
echo "🔧 Services (target: 50%)"
echo "---"
for file in FoodService WeightTrendService WeightService2 TDEEEstimator WorkoutService ToolRanker AIRuleEngine AIToolAgent IntentClassifier ToolRegistration StaticOverrides ExerciseService SupplementService; do
    LINE=$(xcrun xccov view --report "$RESULT_BUNDLE" 2>/dev/null | grep "Services/${file}.swift" | head -1)
    if [ -n "$LINE" ]; then
        PCT=$(echo "$LINE" | grep -oE '[0-9]+\.[0-9]+%' | head -1 | tr -d '%')
        if [ -n "$PCT" ]; then
            if (( $(echo "$PCT < 50" | bc -l) )); then
                echo "  ⚠️  ${file}: ${PCT}% (below 50%)"
                FAILURES=$((FAILURES + 1))
            else
                echo "  ✅ ${file}: ${PCT}%"
            fi
        fi
    fi
done
echo ""

# ViewModels — 50% threshold
echo "📱 ViewModels (target: 50%)"
echo "---"
for file in FoodLogViewModel DashboardViewModel WeightViewModel SupplementViewModel; do
    LINE=$(xcrun xccov view --report "$RESULT_BUNDLE" 2>/dev/null | grep "ViewModels/${file}.swift" | head -1)
    if [ -n "$LINE" ]; then
        PCT=$(echo "$LINE" | grep -oE '[0-9]+\.[0-9]+%' | head -1 | tr -d '%')
        if [ -n "$PCT" ]; then
            if (( $(echo "$PCT < 50" | bc -l) )); then
                echo "  ⚠️  ${file}: ${PCT}% (below 50%)"
                FAILURES=$((FAILURES + 1))
            else
                echo "  ✅ ${file}: ${PCT}%"
            fi
        fi
    fi
done
echo ""

# Database — 50% threshold
echo "💾 Database (target: 50%)"
echo "---"
for file in AppDatabase AppDatabase+FoodUsage Migrations; do
    LINE=$(xcrun xccov view --report "$RESULT_BUNDLE" 2>/dev/null | grep "Database/${file}.swift" | head -1)
    if [ -n "$LINE" ]; then
        PCT=$(echo "$LINE" | grep -oE '[0-9]+\.[0-9]+%' | head -1 | tr -d '%')
        if [ -n "$PCT" ]; then
            if (( $(echo "$PCT < 50" | bc -l) )); then
                echo "  ⚠️  ${file}: ${PCT}% (below 50%)"
                FAILURES=$((FAILURES + 1))
            else
                echo "  ✅ ${file}: ${PCT}%"
            fi
        fi
    fi
done
echo ""

if [ $FAILURES -gt 0 ]; then
    echo "⚠️  $FAILURES file(s) below coverage threshold"
    if [ "$FAIL_MODE" = true ]; then
        exit 1
    fi
else
    echo "✅ All files meet coverage thresholds"
fi
