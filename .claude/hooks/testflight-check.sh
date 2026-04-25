#!/bin/bash

# Silent for non-autonomous (human) sessions — these hooks are autopilot-only.
[[ "${DRIFT_AUTONOMOUS:-0}" != "1" ]] && exit 0
# Hook: PostToolUse on Bash(git commit *)
# Publishes TestFlight when watchdog has marked it due (every 3h).
# Watchdog writes ~/drift-state/testflight-due in its heartbeat loop.
# Hook fires on next commit after that marker appears.

set -e

# Only enforce on watchdog-managed sessions (DRIFT_CONTROL=RUN)
DRIFT_CONTROL=$(cat "$HOME/drift-control.txt" 2>/dev/null | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')
if [ "$DRIFT_CONTROL" != "RUN" ]; then
  exit 0
fi

# Check for force-release signal from Command Center (GitHub Issue)
FORCE=$(gh issue list --state open --label force-release --json number --jq '.[0].number' 2>/dev/null || echo "")
FORCE_ISSUE_NUM=""
DUE_FILE="$HOME/drift-state/testflight-due"

if [ -n "$FORCE" ]; then
  FORCE_ISSUE_NUM="$FORCE"
elif [ ! -f "$DUE_FILE" ]; then
  # Not due yet — show time remaining
  LAST_PUBLISH=$(cat "$HOME/drift-state/last-testflight-publish" 2>/dev/null || echo "0")
  ELAPSED=$(( $(date +%s) - LAST_PUBLISH ))
  REMAINING=$(( (10800 - ELAPSED) / 60 ))
  if [ "$REMAINING" -gt 0 ]; then
    echo "TestFlight: ${REMAINING}min until next publish window."
  fi
  exit 0
fi

LAST_PUBLISH=$(cat "$HOME/drift-state/last-testflight-publish" 2>/dev/null || echo "0")
ELAPSED=$(( $(date +%s) - LAST_PUBLISH ))
HOURS=$(( ELAPSED / 3600 ))

touch "$HOME/drift-state/testflight-publish-authorized"

FORCE_STEP=""
if [ -n "$FORCE_ISSUE_NUM" ]; then
  FORCE_STEP="\\n7. Close force-release issue: gh issue close ${FORCE_ISSUE_NUM} --comment 'Published successfully.'"
fi

cat <<ENDJSON
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "TESTFLIGHT PUBLISH REQUIRED (${HOURS}h since last publish${FORCE_ISSUE_NUM:+ — FORCED via issue #$FORCE_ISSUE_NUM}). This is mandatory — do it NOW before continuing feature work.\n\nSteps:\n1. Bump CURRENT_PROJECT_VERSION in project.yml (increment by 1)\n2. Run: xcodegen generate\n3. Archive: xcodebuild archive -project Drift.xcodeproj -scheme Drift -destination 'generic/platform=iOS' -archivePath /tmp/Drift.xcarchive DEVELOPMENT_TEAM=ZJ5H5XH82A CODE_SIGN_STYLE=Automatic > /tmp/drift-archive.log 2>&1 && echo 'ARCHIVE OK' || (tail -20 /tmp/drift-archive.log && echo 'ARCHIVE FAILED')\n4. Export + Upload: xcodebuild -exportArchive -archivePath /tmp/Drift.xcarchive -exportPath /tmp/DriftExport -exportOptionsPlist ExportOptions.plist -allowProvisioningUpdates -authenticationKeyPath \"/Users/ashishsadh/important-ashisadh/key for apple app/AuthKey_623N7AD6BJ.p8\" -authenticationKeyID 623N7AD6BJ -authenticationKeyIssuerID ad762446-bede-4bcd-9776-a3613c669447 > /tmp/drift-upload.log 2>&1 && echo 'UPLOAD OK' || (tail -20 /tmp/drift-upload.log && echo 'UPLOAD FAILED')\n5. If successful:\n   a. echo \$(date +%s) > ~/drift-state/last-testflight-publish && rm -f ~/drift-state/testflight-due && rm -f ~/drift-state/testflight-publish-authorized\n   b. Update command-center/releases.json: read the file, append a new entry with {build: N, date: ISO date, description: commit summary, features: [user-visible changes since last build], fixes: [bugs fixed since last build]}. Get changes from git log since last TestFlight commit.\n   c. git add project.yml command-center/releases.json && git commit -m 'chore: TestFlight build' && git push\n6. If archive/upload fails: rm -f ~/drift-state/testflight-due ~/drift-state/testflight-publish-authorized, log the error, and continue — do NOT retry more than once.${FORCE_STEP}\n\nDo NOT skip this. Do NOT defer it to later."
  }
}
ENDJSON

exit 0
