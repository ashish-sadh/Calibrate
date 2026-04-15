# Compliance Enforcement Pattern

## Principle

All compliance enforcement in Drift Control follows this pattern:

1. **Watchdog writes cache files** — queries GitHub API every 5 min, writes to `~/drift-state/cache-*`
2. **PreToolUse hook reads local files** — fires every Bash command, reads cache files only, zero API calls
3. **Cache files are model-aware** — senior gets more checks than junior

## Why This Pattern

| Approach | Frequency | API Cost | Session Impact |
|----------|-----------|----------|----------------|
| PreToolUse with API calls | Every command | HIGH (killed sessions) | None |
| PostToolUse on commit | Per commit | Low | Too infrequent |
| Watchdog kills sessions | Every 5 min | Low | Loses context |
| **Local cache (this pattern)** | **Every command** | **Zero** | **None** |

## Adding New Compliance

To add a new compliance requirement:

1. **Watchdog** (`scripts/self-improve-watchdog.sh`): add a `gh` query in `refresh_compliance_cache()` that writes to `~/drift-state/cache-YOUR-ITEM`
2. **Hook** (`.claude/hooks/compliance-check.sh`): add a section that reads the cache file and injects context
3. **Model-aware**: wrap in `if [ "$MODEL" = "opus" ]` for senior-only, or `if [ "$SESSION_TYPE" = "planning" ]` for planning-only

## Cache Files

| File | Written by | Read by | Who sees it |
|------|-----------|---------|-------------|
| `cache-p0-bugs` | Watchdog | compliance-check | All |
| `cache-product-focus` | Session-start | compliance-check | All |
| `cache-design-reviews` | Watchdog | compliance-check | Senior |
| `cache-pending-designs` | Watchdog | compliance-check | Senior |
| `cache-admin-feedback` | Watchdog | compliance-check | Senior |
| `cache-p0-features` | Watchdog | compliance-check | Senior |
| `cache-session-type` | Watchdog | compliance-check | All |
| `last-testflight-publish` | TestFlight hook | compliance-check | Autonomous |
| `last-model` | Watchdog | compliance-check | All |
