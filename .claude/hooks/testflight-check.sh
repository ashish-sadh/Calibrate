#!/bin/bash
# Hook: PostToolUse on Bash(git commit *)
# Checks if 3+ hours have passed since last TestFlight publish.
# If so, injects instruction to publish. Never more frequently than 3 hours.

set -e

# Only enforce on autonomous loop sessions
if [ "${DRIFT_AUTONOMOUS:-0}" != "1" ]; then
  exit 0
fi

LAST_PUBLISH_FILE="$HOME/drift-state/last-testflight-publish"
MIN_INTERVAL=10800  # 3 hours in seconds

NOW=$(date +%s)
LAST_PUBLISH=$(cat "$LAST_PUBLISH_FILE" 2>/dev/null || echo "0")
ELAPSED=$((NOW - LAST_PUBLISH))

# Check for force-release signal from Command Center (GitHub Issue)
FORCE=$(gh issue list --state open --label force-release --json number --jq '.[0].number' 2>/dev/null || echo "")
if [ -n "$FORCE" ]; then
  gh issue close "$FORCE" --comment "Force release triggered. Preflight will run before publish." 2>/dev/null || true
  ELAPSED=$MIN_INTERVAL  # Skip the timer, fall through to publish
fi

if [ "$ELAPSED" -ge "$MIN_INTERVAL" ]; then
  # Calculate hours since last publish for the message
  HOURS=$((ELAPSED / 3600))

  # Create authorization flag — guard-testflight.sh checks for this
  touch "$HOME/drift-state/testflight-publish-authorized"

  cat <<ENDJSON
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "TESTFLIGHT PUBLISH REQUIRED (${HOURS}h since last publish). This is mandatory — do it NOW before continuing feature work.\n\nSteps:\n1. Bump CURRENT_PROJECT_VERSION in project.yml (increment by 1)\n2. Run: xcodegen generate\n3. Archive: xcodebuild archive -project Drift.xcodeproj -scheme Drift -destination 'generic/platform=iOS' -archivePath /tmp/Drift.xcarchive DEVELOPMENT_TEAM=ZJ5H5XH82A CODE_SIGN_STYLE=Automatic > /tmp/drift-archive.log 2>&1 && echo 'ARCHIVE OK' || (tail -20 /tmp/drift-archive.log && echo 'ARCHIVE FAILED')\n4. Export + Upload: xcodebuild -exportArchive -archivePath /tmp/Drift.xcarchive -exportPath /tmp/DriftExport -exportOptionsPlist ExportOptions.plist -allowProvisioningUpdates -authenticationKeyPath \"/Users/ashishsadh/important-ashisadh/key for apple app/AuthKey_623N7AD6BJ.p8\" -authenticationKeyID 623N7AD6BJ -authenticationKeyIssuerID ad762446-bede-4bcd-9776-a3613c669447 > /tmp/drift-upload.log 2>&1 && echo 'UPLOAD OK' || (tail -20 /tmp/drift-upload.log && echo 'UPLOAD FAILED')\n5. If successful: echo $(date +%s) > ~/drift-state/last-testflight-publish && rm -f ~/drift-state/testflight-publish-authorized && git add project.yml ~/drift-state/last-testflight-publish && git commit -m 'chore: TestFlight build' && git push\n6. If archive/upload fails: rm -f ~/drift-state/testflight-publish-authorized, log the error, and continue — do NOT retry more than once.\n\nDo NOT skip this. Do NOT defer it to later."
  }
}
ENDJSON
else
  REMAINING=$(( (MIN_INTERVAL - ELAPSED) / 60 ))
  echo "TestFlight: ${REMAINING}min until next publish window."
fi

exit 0
