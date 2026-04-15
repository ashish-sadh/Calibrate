# GitHub API Hygiene

Guidelines for hooks, sessions, and Command Center to stay within GitHub rate limits.

## Rate Limits

| Limit | Budget | Scope |
|-------|--------|-------|
| Primary | 5,000 requests/hour | Per PAT token |
| Secondary | 900 points/minute | GET=1pt, POST/PATCH/DELETE=5pts |
| Content-generating | 80/min, 500/hour | Issue create, PR create, comments |
| Concurrent | 100 max | Simultaneous requests |

## Rules

1. **Reads are cheap (1pt), writes are expensive (5pts).** Batch writes. Don't edit an issue 3 times when one edit suffices.
2. **Never poll GitHub in hooks.** Hooks fire frequently — use local state files (`~/drift-state/`) instead of API calls where possible.
3. **Cache API results.** Session-start queries should write to cache files with a 5-min TTL. Rapid crash-restart cycles hit the same queries repeatedly.
4. **Respect retry-after.** If `gh` returns 403 or 429, wait 60s before retrying. Never retry in a tight loop.
5. **Content-generating budget: 80/min.** Sprint planning creates ~10 issues = fine. Don't create 50 issues in rapid succession.
6. **Check rate limit before heavy operations.** Run `scripts/check-rate-limit.sh` before sprint planning or bulk issue creation.

## Point Cost Reference

| Operation | Points | Example |
|-----------|--------|---------|
| `gh issue list` | 1 | Listing open bugs |
| `gh issue view N` | 1 | Reading an issue |
| `gh pr list` | 1 | Listing PRs |
| `gh issue create` | 5 | Creating a sprint task |
| `gh issue edit N` | 5 | Adding/removing labels |
| `gh issue close N` | 5 | Closing an issue |
| `gh pr create` | 5 | Creating a PR |
| `gh pr merge` | 5 | Merging a PR |

## Hook Budget (per commit)

After optimization: ~8 points per commit from hooks. Well within the 900pts/min budget.

| Hook | API Calls | Points |
|------|-----------|--------|
| issue-check.sh | 1 GET | 1 |
| mark-in-progress.sh | 1 GET + 1 PATCH per issue | 6 |
| testflight-check.sh | 1 GET (force-release check) | 1 |
| Others | 0 (local file reads) | 0 |
