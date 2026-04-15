#!/bin/bash
# Live session monitor for Drift Control.
# Reads the session log, summarizes via Haiku (from /tmp to avoid loading project),
# updates a GitHub Issue.
#
# Usage: ./scripts/session-monitor.sh <session-log-path> <issue-number>

set -uo pipefail

CURRENT_LOG="$1"
ISSUE_NUM="$2"
INTERVAL=120  # 2 minutes between updates

while true; do
    sleep "$INTERVAL"

    [[ ! -f "$CURRENT_LOG" ]] && continue

    # Extract recent activity from stream-json log
    RECENT=$(tail -30 "$CURRENT_LOG" | python3 -c "
import sys, json
lines = []
for line in sys.stdin:
    try:
        d = json.loads(line)
        if d.get('type') == 'assistant':
            for c in d.get('message', {}).get('content', []):
                if c.get('type') == 'text':
                    lines.append('AI: ' + c['text'][:150])
                elif c.get('type') == 'tool_use':
                    name = c.get('name', '?')
                    inp = c.get('input', {})
                    if name == 'Bash':
                        lines.append(f'Bash: {inp.get(\"command\",\"\")[:80]}')
                    elif name == 'Read':
                        lines.append(f'Read: {inp.get(\"file_path\",\"\").split(\"/\")[-1]}')
                    elif name == 'Edit':
                        lines.append(f'Edit: {inp.get(\"file_path\",\"\").split(\"/\")[-1]}')
                    elif name == 'Agent':
                        lines.append(f'Agent: {inp.get(\"description\",\"\")[:60]}')
                    else:
                        lines.append(f'{name}')
    except:
        pass
for l in lines[-8:]:
    print(l)
" 2>/dev/null)

    [[ -z "$RECENT" ]] && continue

    MODEL=$(cat ~/drift-state/last-model 2>/dev/null || echo "?")
    CYCLE=$(cat ~/drift-state/cycle-counter 2>/dev/null || echo "?")
    SESSION_TYPE=$(basename "$CURRENT_LOG" | sed 's/session_\([a-z]*\)_.*/\1/')
    LOG_LINES=$(wc -l < "$CURRENT_LOG" | tr -d ' ')

    # Summarize via Haiku — run from /tmp so it doesn't load CLAUDE.md
    SUMMARY=$(cd /tmp && echo "$RECENT" | claude -p \
        "Summarize in 2-3 sentences what this AI coding session is doing right now. Be specific: mention issue numbers, file names, and what kind of work (bug fix, design doc, test writing, refactoring). No preamble, just the summary." \
        --model haiku --output-format text 2>/dev/null || echo "$RECENT")

    BODY="**Model:** ${MODEL} | **Type:** ${SESSION_TYPE} | **Cycle:** ${CYCLE} | **Log:** ${LOG_LINES} lines | **Updated:** $(date '+%H:%M:%S')

${SUMMARY}"

    gh issue edit "$ISSUE_NUM" --body "$BODY" 2>/dev/null || true
done
