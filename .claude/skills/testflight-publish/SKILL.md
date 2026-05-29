---
name: testflight-publish
description: TestFlight publish recipe. Invoked by the watchdog as its next-session slot when ≥3h since last publish AND is-clean-state passes (NOT by launchd cron — the watchdog already serializes one claude -p at a time, so slotting TF into that queue gives zero concurrency with senior/junior xcodebuild or main-branch commits). Skips quietly if not clean or <3h since last publish, otherwise bumps build, archives, uploads, stamps state, updates releases.json. Haiku model — recipe is deterministic.
---

<role>
You are the TestFlight publish skill. You are invoked by the watchdog as a next-session slot when ≥3h since last publish AND state is clean. The watchdog already wrote `~/drift-state/testflight-publish-authorized` before spawning you (the `guard-testflight.sh` hook requires this flag for `xcodebuild archive` in autonomous sessions).

Your job is a deterministic shell recipe gated on cleanliness. You do NOT make judgment calls.

Because the watchdog only runs one claude session at a time, there is zero risk of colliding with a senior `xcodebuild test` or a junior commit-to-main: those sessions are not running concurrently with you. You inherit a fully clean state at spawn.

You exit `0` in three cases:
1. State is not clean (skip quietly; cron fires again in 3h)
2. Less than 3h since last publish (skip quietly)
3. No new commits to main since last publish (skip quietly)
4. Successful publish

You exit `1` on archive/upload failure (stamps `~/drift-state/testflight-archive-failed`; next 24h of cron firings will skip the bump until cleared).
</role>

<context_rules>
- Haiku model (cheaper, faster, fine for deterministic shell steps).
- Never `/compact`.
- Single source of truth for the recipe: this skill body. The old hook `testflight-check.sh` is being deleted.
</context_rules>

<steps>

### 1. Check cleanliness
```
state_is_clean() via drift-mcp
```
If `clean: false`, append to `~/drift-state/testflight-skip.log` with timestamp + reasons. After 5 consecutive skips (count from the log), additionally write a `## TestFlight starved` note to the latest exec report PR.

Exit 0 if not clean.

### 2. Check staleness
```
LAST=$(cat ~/drift-state/last-testflight-publish 2>/dev/null || echo 0)
NOW=$(date +%s)
[ $((NOW - LAST)) -lt 10800 ] && exit 0  # <3h since last
```

### 3. Check there's anything new to publish
```
testflight_unpublished_commits() via drift-mcp
```
If `count: 0`, exit 0 quietly.

### 4. Check archive-failed cooldown
If `~/drift-state/testflight-archive-failed` exists AND its mtime is within last 24h, exit 0 (cooldown active).

### 5. Bump CURRENT_PROJECT_VERSION (ALL targets, in lockstep)
`project.yml` has TWO `CURRENT_PROJECT_VERSION` lines — the `Drift` app
target AND the `DriftWidget` extension. App Store Connect requires an
embedded extension's build number to MATCH the containing app's. Bump BOTH
to the same value or the upload warns (observed 2026-05-29: `count=1` left
DriftWidget stranded at 267 while the app climbed to 278; every publish
logged a "widget bundle version mismatch" warning AND the commit message
derived the wrong build number from the stale widget line).
```
python3 -c "
import re, pathlib
p = pathlib.Path('project.yml')
text = p.read_text()
nums = [int(n) for n in re.findall(r'CURRENT_PROJECT_VERSION:\s*(\d+)', text)]
target = max(nums) + 1  # bump from the highest existing so no target regresses
new = re.sub(r'CURRENT_PROJECT_VERSION:\s*\d+', f'CURRENT_PROJECT_VERSION: {target}', text)
p.write_text(new)
print('bumped ALL targets to', target)
"
```
Use the printed `target` value for the commit message ("chore: TestFlight
build <target>") — do NOT re-grep project.yml for it (all lines are now
equal, but reading the printed value is the source of truth).

### 6. Regenerate Xcode project
```
xcodegen generate
```

### 7. Archive
```
xcodebuild archive \
  -project Drift.xcodeproj \
  -scheme Drift \
  -destination 'generic/platform=iOS' \
  -archivePath /tmp/Drift.xcarchive \
  DEVELOPMENT_TEAM=ZJ5H5XH82A \
  CODE_SIGN_STYLE=Automatic \
  > /tmp/drift-archive.log 2>&1
```
If exit !=0 → stamp archive-failed and exit:
```
date +%s > ~/drift-state/testflight-archive-failed
tail -20 /tmp/drift-archive.log
exit 1
```

### 8. Export + Upload
```
xcodebuild -exportArchive \
  -archivePath /tmp/Drift.xcarchive \
  -exportPath /tmp/DriftExport \
  -exportOptionsPlist ExportOptions.plist \
  -allowProvisioningUpdates \
  -authenticationKeyPath "/Users/ashishsadh/important-ashisadh/key for apple app/AuthKey_623N7AD6BJ.p8" \
  -authenticationKeyID 623N7AD6BJ \
  -authenticationKeyIssuerID ad762446-bede-4bcd-9776-a3613c669447 \
  > /tmp/drift-upload.log 2>&1
```
Same failure handling as archive.

### 9. Stamp success + update releases.json + clear auth flag
```
NOW=$(date +%s)
echo "$NOW" > ~/drift-state/last-testflight-publish
git rev-parse HEAD > ~/drift-state/last-testflight-publish-sha
rm -f ~/drift-state/testflight-archive-failed
rm -f ~/drift-state/testflight-due  # legacy file from old hook flow
rm -f ~/drift-state/testflight-publish-authorized  # one-shot auth; watchdog re-writes on next slot
```

Update `command-center/releases.json` — append a new entry. Use the script if present:
```
scripts/gen-releases.sh
```
Else manually: parse last published-sha + git log since → build entry with {build, date_iso, description, features, fixes}.

### 10. Commit + push
```
git add project.yml Drift.xcodeproj/project.pbxproj command-center/releases.json
git commit -m "chore: TestFlight build $NEW_BUILD"
git push
```
**Important:** `project.pbxproj` MUST be in the same commit. xcodegen
regenerates it in Step 6, and the repo's convention (CLAUDE.md: "Run
xcodegen generate after changing project.yml or adding new files")
requires both files version-controlled together. Omitting pbxproj
leaves the working tree dirty after the publish and the Stop hook
blocks the next session's exit.

Note: this commit has no associated issue (so `require-qa-verdict.sh` shouldn't enforce — it only enforces on issue-referencing commits). Verify.

### 11. Exit 0

</steps>

<failure_modes>
- **Archive on a dirty working tree** — step 1 cleanliness gate prevents this. If somehow bypassed, archive will include dirty changes.
- **Publishing the same build twice** — step 2 staleness check prevents this. If timestamp file is missing/stale, conservative behavior is to skip (cron will retry).
- **Publishing despite failing tier-0 tests** — step 1 includes the test cache check.
- **Retry-loop on archive failure** — step 4 cooldown prevents repeated archive attempts within 24h. Cleared by human or watchdog.
- **CURRENT_PROJECT_VERSION bumped despite archive failure** — re-read after step 7 fails: if bumped, decrement back. (TODO if observed in practice.)
</failure_modes>
