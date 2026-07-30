# Design: Goal Statement — one goal, said in words, reachable from everywhere

> References: Issue #1161
> Operator conversation 2026-07-29: "I am thinking about how to talk about
> goals of people for workout and nutrition. And set it so it helps with Coach
> Me but also this summary that sets the goal via chat is also saved and shared
> with AI coach as well as human coach."

## Problem

Drift stores goal NUMBERS in three unrelated places and holds the goal itself
nowhere:

| What | Where set | Shape |
|---|---|---|
| `WeightGoal` | More → Goal (form) | target kg, months, protein/carb/fat targets |
| `CoachIntake.goal` | Coach Me interview | a free-text **string** ("build muscle") |
| `set_goal` tool | Drift Coach chat | sets **one number** (`target`, `goal_type`) |

Consequences:
- Nothing carries the WHY, the timeline in the user's own words, or the
  constraints that shape it ("around work travel", "knee is the limiter").
- Coach Me re-asks what the user already told the app, because the training
  string and the numeric goal never meet.
- A human coach cannot see the target at all. Only a derived
  `losing / gaining / none` direction crosses, added for plateau alerts.
- The AI coach re-derives intent from scratch every conversation.

## Proposal

A **`GoalStatement`**: one dated, plain-English paragraph of what the person is
working toward, plus the constraints that shape it. It is ADDITIVE — it does
not replace `WeightGoal`'s numbers, which keep driving calorie/macro targets
app-wide. The statement carries intent; `WeightGoal` carries arithmetic.

**Out of scope:** a new onboarding wizard, a goals tab, goal streaks/gamification,
or replacing the existing GoalView form (it stays as the manual editor).

### Three entry points, one object (operator decision)

Goals are cross-domain, so they must not live in one tab:

1. **Today card** — the home. Shows the statement AND the numbers it produced,
   side by side. Tap to talk about it or edit.
2. **Coach Me** — already interviews for training intent; it reads and writes
   the same statement instead of its own string, so it stops re-asking.
3. **Workout tab button** — "Your goal", next to Coach Me, for the moment
   someone is about to train and wants to re-read what they're chasing.
4. **Drift Coach chat** — `set_goal` widens from one-number to full intent, per
   the tenet that every entry is doable in conversation.

### Verifiability is load-bearing

A conversationally-set goal MUST show what the app actually stored, or a
misparse becomes a silent wrong target. The Today card renders:

```
YOUR GOAL                                    set 3 days ago
"Down to 170 by December, keep the bench moving,
 3 days a week around work travel."
────────────────────────────────────────────────────
target 170 lb   ·   1,850 kcal/day   ·   150 g protein
```

Same discipline as the coach mirror view: show the derived values next to the
words, so an error is visible in one glance rather than discovered months later.

### Versioning — the change IS the signal

When the statement changes, the previous one is kept as a dated entry. A coach
seeing "goal changed 3 weeks ago: fat loss → strength" learns more than the
current goal tells them. `CoachNotes` already has a dated log; goal changes
land there as `.observation` notes.

### Sharing (operator decision)

The statement becomes the **headline of the coach briefing**, replacing the
mechanical "3 days/week · 45 min · dumbbells" join. Consented under the
EXISTING `.history` bit — a coach cannot coach toward a target they can't see —
and that toggle's label is updated to name goals, so consent stays readable.

## Technical Approach

- **DriftCore** `Models/GoalStatement.swift`: `{ text, setAt, source
  (chat/coachMe/form), history: [DatedStatement] }`. Persisted through
  `DriftPlatform.keyValueStore` (the durable SQLite seam — UserDefaults writes
  don't survive Android process death, #1108), same pattern as `WeightGoal`.
- **AI**: widen `set_goal` to accept a statement alongside the numeric target;
  the numeric path stays exactly as-is so existing "set my goal to 160"
  utterances keep working. New Tier-0 cases in the intent gold set.
- **Coach Me**: `CoachIntake.goal` reads from the statement when present;
  writing intent updates the statement rather than only the string.
- **SharedUI**: `GoalStatementCard` (Today + Workout), one component so the two
  entry points can't drift. Briefing headline swaps to the statement.
- **Sharing**: `BriefingMetrics`/`ClientBriefing.summary` carries the statement;
  no migration needed (it's the existing `summary` text column).
- Both platforms; the card is SharedUI so Android gets it in the same commit.

## Risks

- **Misparse** — mitigated by showing derived numbers next to the words.
- **Two sources of truth for the training goal** during migration: `CoachIntake.goal`
  keeps working; the statement wins when present. Delete the string only once
  the statement has shipped and been verified in a build.
- **Statement bloat** — cap the text (≈300 chars) so it stays a goal, not a diary.
