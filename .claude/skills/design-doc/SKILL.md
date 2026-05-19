---
name: design-doc
description: "Sub-skill invoked by /senior when claimed task is design-doc-labeled. State machine — pending → write doc; in-review → respond to comments (lightweight or delegated to /autofix-pr for substantive); ready-to-close → verify all impl tasks closed + close parent. Never claims independently; always called from /senior."
---

<role>
You handle Drift's design-doc lifecycle. The state is read from issue/PR labels:
- `design-doc` + no `doc-ready` → **pending** (no doc written yet)
- `design-doc` + `doc-ready` (on the PR) → **in-review** (awaiting admin approval)
- `design-doc` + `doc-ready` + `approved` + `implementing` → impl tasks filed; NOT this skill's concern (senior works the impl tasks normally; planning step 5 files them)
- All `design-impl-{N}` closed → **ready-to-close** (parent design issue ready for closure)

You are invoked by `/senior` with the issue number. You do NOT claim or release the claim — `/senior` owns that.
</role>

<context_rules>
- File-based handoff: when reading PR comments, dump to a workdir file (`/tmp/design-pr-{N}-comments.txt`) and read from there. Never re-feed the entire thread back through the context.
- For substantive admin-comment threads, delegate continuous watching to a `/autofix-pr` web session.
- Never `/compact`.
</context_rules>

<steps>

### Identify state
```
gh issue view <N> --json labels --jq '.labels[].name'
```
+ if there's an associated PR (search by branch name `design/{N}-*`):
```
gh pr list --search "head:design/{N}" --json number,labels
```

### Branch by state:

#### Pending (no PR yet)
1. Research: invoke `principal-engineer` + `product-designer` subagents in parallel via `debate-moderator`:
   ```
   Use Agent: debate-moderator
     participants: principal-engineer, product-designer
     artifact: <issue body — the design-doc request>
     goal: "Research input: what alternatives should the doc consider? What's the user problem? What's the architectural risk?"
   ```
2. Create branch: `git checkout -b design/{N}-<slug>`
3. Write the doc: `Docs/designs/{N}-<slug>.md`. Sections: Context, Goal/Non-goals, Considered Alternatives, Recommended Approach, Trade-offs, Implementation Plan (the impl-tasks-to-be-filed list), Open Questions.
4. Invoke `debate-moderator` again on the *draft*:
   ```
   Use Agent: debate-moderator
     participants: principal-engineer, product-designer
     artifact: <full draft doc>
     goal: "KEEP/DROP/ADD on this design draft"
   ```
5. Revise per the verdict.
6. Open PR: `gh pr create --label "design-doc" --title "Design #{N}: ..." --body "..."`
7. After PR is open + visible, add `doc-ready` label.

#### In-review (PR has unaddressed comments)
1. Dump all comment surfaces to a workdir file:
   ```
   design_address_pr(pr=<PR_N>) via drift-mcp → /tmp/design-pr-{N}-comments.txt
   ```
2. Read the file. Classify each comment:
   - **Lightweight** (typo, clarification, "please link to X", minor revision): respond inline via `gh api repos/{owner}/{repo}/pulls/{N}/comments/{comment_id}/replies` (or top-level via `gh pr comment <PR_N>`). Edit the doc on the branch, push.
   - **Substantive** (admin proposes a different approach, expands scope, raises architectural concern): invoke `/autofix-pr` to delegate continuous watching:
     ```
     /autofix-pr address admin comments on PR <PR_N>; revise the design doc per the comment threads; do not merge — push commits and let next planning cycle re-evaluate
     ```
     Then exit `/design-doc` and return control to `/senior`. The /autofix-pr web session handles the remainder asynchronously.

#### Ready-to-close (all impl tasks closed)
1. Verify:
   ```
   design_check_complete(design_n=<N>) via drift-mcp
   ```
   Returns `{complete: bool, open_impl_tasks: [...]}`.
2. If `complete: false`, do nothing — the remaining impl tasks need work first. Return control to `/senior` who can proceed with one of them.
3. If `complete: true`: close the parent design issue with a summary comment:
   ```
   gh issue close <N> --comment "All design-impl-{N} tasks closed. Design fully shipped: <one-paragraph summary>."
   ```

</steps>

<failure_modes>
- **Reading the PR thread into parent context** — token-pollution risk; always dump to file first.
- **Trying to merge a design-doc PR yourself** — the autopilot NEVER merges design docs. Admin merges after `approved` label.
- **Writing the doc without research** — engineering + design debate first; doc second. Single-perspective design docs miss the activation angle or the architectural concern.
- **Filing impl tasks here** — that's `/planning` step 5's job (`approved-not-started` state). This skill writes the doc; planning files the impl tasks once the doc is approved.
</failure_modes>
