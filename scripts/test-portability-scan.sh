#!/bin/bash
# Scan DriftTests/*.swift to classify each file as portable to DriftCore/Tests/DriftCoreTests
# (pure-logic, only needs @testable import DriftCore) vs non-portable (references iOS-only symbols).
#
# Output:
#   /tmp/portable.txt          — file paths, one per line
#   /tmp/non-portable.txt      — "<file>\t<reason>"
#   /tmp/no-driftcore.txt      — files that don't @testable import DriftCore
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# iOS-only symbols/imports: presence of any of these means the file references the Drift iOS shell
IOS_ONLY_RE='HealthKitService|FoodLogViewModel|WeightViewModel|AIChatViewModel|WorkoutViewModel|WidgetCenterRefresher|WidgetDataProvider|NotificationService|SpeechRecognitionService|BodySpecPDFParser|LabReportOCR|NutritionLabelOCR|PhotoLogTool|UIImage|UIView|DriftApp\b|ContentView|HomeView|DashboardView|import UIKit|import SwiftUI|import HealthKit|import WidgetKit|import AVFoundation|import Speech|import Photos|import AppIntents'

> /tmp/portable.txt
> /tmp/non-portable.txt
> /tmp/no-driftcore.txt

for f in DriftTests/*.swift; do
  if ! grep -q '@testable import DriftCore' "$f"; then
    echo "$f" >> /tmp/no-driftcore.txt
    continue
  fi
  hit=$(grep -E "$IOS_ONLY_RE" "$f" | head -1 || true)
  if [ -n "$hit" ]; then
    # Reason: first matching token
    reason=$(echo "$hit" | grep -oE "$IOS_ONLY_RE" | head -1)
    printf "%s\t%s\n" "$f" "$reason" >> /tmp/non-portable.txt
  else
    echo "$f" >> /tmp/portable.txt
  fi
done

echo "Portable (candidates to move): $(wc -l < /tmp/portable.txt)"
echo "Non-portable (stay in DriftTests): $(wc -l < /tmp/non-portable.txt)"
echo "No DriftCore import (untouched): $(wc -l < /tmp/no-driftcore.txt)"
