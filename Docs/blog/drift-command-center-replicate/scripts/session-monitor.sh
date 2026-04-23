#!/bin/bash
# Live session monitor for Drift Control.
# Reads the session log, summarizes via Haiku, updates a GitHub Issue.
#
# Usage: ./scripts/session-monitor.sh <session-log-path> <issue-number>

set -uo pipefail

CURRENT_LOG="$1"
ISSUE_NUM="$2"
INTERVAL=120  # 2 minutes between updates

while true; do
    sleep "$INTERVAL"

    [[ ! -f "$CURRENT_LOG" ]] && continue

    # Extract recent activity from stream-json log — structured for Haiku
    RECENT=$(tail -40 "$CURRENT_LOG" | python3 -c "
import sys, json
lines = []
for line in sys.stdin:
    try:
        d = json.loads(line)
        if d.get('type') == 'assistant':
            for c in d.get('message', {}).get('content', []):
                if c.get('type') == 'text':
                    lines.append('Said: ' + c['text'][:200])
                elif c.get('type') == 'tool_use':
                    name = c.get('name', '?')
                    inp = c.get('input', {})
                    if name == 'Bash':
                        cmd = inp.get('command', '')[:100]
                        desc = inp.get('description', '')
                        lines.append(f'Ran command: {desc or cmd}')
                    elif name == 'Read':
                        lines.append(f'Reading file: {inp.get(\"file_path\",\"\")}')
                    elif name == 'Edit':
                        lines.append(f'Editing file: {inp.get(\"file_path\",\"\")}')
                    elif name == 'Write':
                        lines.append(f'Creating file: {inp.get(\"file_path\",\"\")}')
                    elif name == 'Agent':
                        lines.append(f'Spawned agent: {inp.get(\"description\",\"\")}')
                    elif name == 'Grep':
                        lines.append(f'Searching for: {inp.get(\"pattern\",\"\")}')
                    else:
                        lines.append(f'Used tool: {name}')
    except:
        pass
# Last 10 actions
for l in lines[-10:]:
    print(l)
" 2>/dev/null)

    [[ -z "$RECENT" ]] && continue

    MODEL=$(cat ~/drift-state/last-model 2>/dev/null || echo "?")
    CYCLE=$(cat ~/drift-state/cycle-counter 2>/dev/null || echo "?")
    SESSION_TYPE=$(basename "$CURRENT_LOG" | sed 's/session_\([a-z]*\)_.*/\1/')
    LOG_LINES=$(wc -l < "$CURRENT_LOG" | tr -d ' ')

    # Summarize via Haiku with 30s timeout — fallback to raw log
    HAIKU_INPUT="This is a log of an AI coding assistant working on the Drift iOS app. The session type is '${SESSION_TYPE}' using model '${MODEL}'. Here are the last 10 actions:

${RECENT}

Write a 2-3 sentence status update for a human dashboard. Be specific: mention file names, issue numbers (#N), and what the session is doing (fixing a bug, writing tests, creating a design doc, refactoring code). Start directly with what it's doing — no preamble."

    # macOS timeout: run in background, kill after 30s
    SUMMARY=""
    TMPOUT=$(mktemp)
    (cd /tmp && echo "$HAIKU_INPUT" | claude -p --model haiku --output-format text > "$TMPOUT" 2>/dev/null) &
    HAIKU_PID=$!
    ( sleep 30 && kill "$HAIKU_PID" 2>/dev/null ) &
    TIMER_PID=$!
    wait "$HAIKU_PID" 2>/dev/null
    kill "$TIMER_PID" 2>/dev/null || true
    SUMMARY=$(cat "$TMPOUT" 2>/dev/null)
    rm -f "$TMPOUT"
    # Fallback to raw log if Haiku failed
    [[ -z "$SUMMARY" ]] && SUMMARY="$RECENT"

    MODEL_DISPLAY=$(echo "$MODEL" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')
    BODY="**${MODEL_DISPLAY}** ${SESSION_TYPE} session | Cycle ${CYCLE} | ${LOG_LINES} lines | Updated $(date '+%H:%M')

${SUMMARY}"

    gh issue edit "$ISSUE_NUM" --body "$BODY" 2>/dev/null || true
done
