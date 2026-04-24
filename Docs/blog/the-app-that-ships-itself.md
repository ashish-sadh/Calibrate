# The app that ships itself

*Notes on harness engineering for a one-person autonomous dev loop.*

---

Over the seven days before I sat down to write this, a loop I built around a pair of language models pushed **409 commits** into an iOS app's repo. It closed **thirty bug issues** — most filed by real people on TestFlight — resolving the shallower ones in about eleven minutes on average. It wrote **nine product-review PRs**, studying the competition and telling me where the app was losing ground. It shipped **three TestFlight builds**.

I wrote none of that code. I read some of the reviews.

The app is called **Drift**. It's an iOS health tracker on twenty-five phones, all by word of mouth — a handful of friends, a couple of teammates, some family. Two of them traded a $20-a-month health-app subscription for a copy of this one. The app runs entirely on their phones; nothing of theirs hits my servers, because I don't have any. My cost to keep it running is zero. In return, they find the subtle bugs I miss and push back on the places where the UI lacks taste.

Two things sit side by side in this story, and it's worth naming them right now:

- **Drift** is the iOS app. The thing users touch. It lives on my friends' phones.
- **Drift Control** is the *autonomous development loop* that builds Drift. The supervisor script, the Claude Code sessions, the hooks, the personas, the dashboard — all the scaffolding I wired around the language models so that the paragraph above is a boring Tuesday. I touch this. Users don't.

Drift is the dish. Drift Control is the kitchen. This post is mostly about the kitchen.

The inner loop of Drift Control is what Geoffrey Huntley calls a [Ralph loop](https://ghuntley.com/ralph/): a `while true` around an AI coding agent, one task per pass, progress persisted in git rather than in the model's memory. Ralph is the engine. This post is about everything you have to build *around* the engine so it keeps running honestly for weeks without you watching.

It isn't news at this point that a language model will write a pile of working code if you few-shot it hard enough. That part is easy. What I find interesting — and what I think actually took the engineering — is what happens when you let the process run unattended for *months*, not minutes. What runs out first, in that mode, isn't compute or context window. It's **human attention**, and the taste that attention encodes. Most of what follows is machinery for making that scarce resource go further — scaffolding that ends up carrying what you'd normally call product judgment.

(Claude Code is the agent runtime I happen to use. You could run the same pattern around Aider or OpenCode or Cursor's agent mode with some re-plumbing. The harness is what's load-bearing, not the runtime.)

The harness, in my experience, is the more interesting engineering.

---

## taste lives in the scaffolding

**Taste lives in the scaffolding, and human attention is what it spends.**

**Drift Control**, as I said above, is Ralph grown up. The inner loop is still a simple while-true. Around it is a layer of scaffolding — a supervisor tree, a domain-specific state machine, enforcement hooks, personas that accumulate taste, a dashboard I can read on my phone — that lets the loop run unattended not for hours, but for *weeks*. If Ralph is the engine, Drift Control is the engine plus the dashboard, the oil light, and the seatbelt.

Two observations became obvious after a few months of running this.

The first is that **the agent is not the product you own.** Models change. What persists is the harness: the queue, the hooks, the reconciliation, the dashboards, the test suite, the personas. If you pour your craft into clever prompts, you've invested in something a model update will replace. If you pour it into the harness, it compounds. The model gets swapped out; the scaffolding is what you keep.

The second is that **agents are a distributed-systems problem, not a language-model problem.** Every unglamorous distributed-systems pattern reappears the moment you let a language model run unsupervised — atomicity, idempotency, supervisor trees, and so on. These are half a century old and well understood. Most people building on agents haven't touched them since their systems-design interview. When something feels hard or weird about your agent, ask the systems question first — *"is this a race?"* — before the prompt question.

One more framing point: **offloading a task to a bigger model is lazy.** You want a smart answer, you pay for a smarter model. The harder craft is the inverse: take a model that isn't especially smart, feed it the right context at the right moment, and watch it produce work that *looks* smart because the scaffolding did the heavy lifting. That principle shows up twice in Drift — once in the app (on-device models with a tool-calling context layer) and once in the harness (hook-enforced ground-truth reconciliation that keeps ordinary Claude Code sessions honest).

A final framing point: this is deliberately **not a general-purpose personal agent**. A "do anything for me" agent has no ground truth to reconcile against and no domain-shaped state machine to run on. Drift Control has one job: ship a specific iOS app. Git, GitHub, `xcodebuild`, and TestFlight are the anchors that make every pattern below possible. Narrow beats broad, for this class of system. At least with today's models.

---

## drift, the app

If you've known me for a while, you've watched me cycle through every health tracker on the App Store and explain my HRV at dinner to people who didn't ask. Drift is the natural endpoint of that. I built it because every existing option fell short of what I wanted: an app that knew my food, my workouts, my weight, my mood, my sleep, and my glucose when I'm wearing a CGM, and that answered questions like *"when will I hit my goal weight?"* or *"does my glucose spike after rice?"* by chatting. Natural-language logging — type or speak *"log breakfast: two eggs, toast, and coffee with milk,"* have the structured record appear. And I wanted it to live on my phone, not as another subscription.

That last point matters to me more than it probably should. A lot of health apps are becoming thin clients on top of cloud LLMs, charging monthly for what's really a few pass-through calls to a frontier-model provider. I didn't want to add one more of those to my phone, and I didn't want to build one.

So Drift is a **no-"server" architecture.** No accounts. No subscriptions. No server on my end. The only backend is your phone.

That constraint meant running a language model on the phone itself — which means the model has to be **small**. Small enough to fit, small enough to stay resident, small enough to unload when you don't need it.

A small model is not a smart model, but it doesn't need to be. Small models are reliably good at one thing: **tool calling.** Give them a clear toolbox, they can read the query, pick the right tool, fill in its parameters, and return a structured result. And that's the shape of almost every query a health app needs to answer.

So I broke Drift down into roughly twenty tools. Each tool sits on top of one slice of your data — food logs, weight history, workouts, Apple Health (weight, workouts, CGM glucose), a goal-projection calculator, a cross-domain correlation query, a trend projector — and runs the analytics itself, in Swift, deterministically. The small model's job isn't to *do* the analysis; it's to read the query, pick the right tool, fill its parameters, and route the structured result back to the UI. Almost all of Drift's perceived intelligence is really the tools underneath doing the real work, with the model acting as router.

The context layer wrapping the model is four tiers deep. Tier 0 handles instant, deterministic queries — the kind a regex can answer. Tier 1 normalizes the input: synonyms, abbreviations, units. Tier 2 picks the right tool from the twenty. Tier 3 composes the answer and streams it back. Most queries get answered by tiers 0–2 without the model seeing anything. By the time the model runs, the hard work of deciding *what* to look up is already done.

That's why this works. A small model given the right five facts at the right moment behaves beautifully. A small model given twenty thousand tokens of noise does not, and no amount of clever prompting will save it. The scaffolding saves it.

One engineering problem took more effort than the model itself: getting the tool's structured result back into the UI and surfacing it for confirmation. Saying *"log coffee with milk"* in chat has to round-trip into a confirmation card in the Food tab — right serving units pre-filled, macros editable, an *Add* button the user can tweak or accept. That round-trip, from natural-language input → tool invocation → editable UI confirmation, is where most of the product polish went.

There is one place in Drift where the tradeoff favors a frontier model: **photo meal logging**. Point your camera at a plate, want macros and servings back — that's a task where a current on-device model cannot compete with Anthropic, OpenAI, or Google. So Drift offers a **bring-your-own-key** path: you plug your existing Anthropic, OpenAI, or Google API key into Settings, it's stored in iOS Keychain, and Drift talks to the provider directly from your phone. You pay them, not me. The photo is the only thing that leaves the device — everything else stays local. If you'd rather not configure a key, photo logging is simply off, and the text and voice paths still work against the local model.

---

## same pattern, dev loop edition

The harness around Claude Code is not an elaborate multi-agent orchestration with judges and tournaments. It's ordinary language-model sessions, firing sequentially on my laptop — no sandboxes, no parallel worktrees — wrapped in enough scaffolding that ordinary sessions do real work and correct themselves before the problems reach me.

The scaffolding is made of five patterns, each learned the hard way.

---

## 1 — ground truth, not memory

One Saturday I noticed the watchdog had run eleven consecutive planning sessions in four hours. Zero code shipped. The sessions kept firing *because the planning-due check was reading a stamp file that each session was supposed to write when it finished — and the sessions kept partially executing and dying before the stamp got written.* The harness was asking itself *"when did I last plan?"* and the answer was, forever, *"never."*

The rule I took from that: if a language-model-driven session wrote it, I can't trust that it stayed true. Sessions die, crash, run out of context, panic-exit. A stamp written by a session is a claim that depends on the session finishing cleanly, and sessions don't always finish cleanly.

Every gate in the watchdog loop now reconciles against an **external, durable store**. Not a local file an earlier session might have written. Not a cache. Git log or the GitHub API, every time.

| Gate | Old implementation | New implementation |
|---|---|---|
| Planning-due? | read stamp file | `git log --grep='planning complete'` |
| TestFlight-due? | read stamp file | `git log --grep='TestFlight build'` |
| What's in progress? | read local state | `gh issue list --label in-progress` |
| Report merged? | read stamp | `gh pr list --state merged --label report` |

It costs more in API calls. It's worth it. Git and GitHub are the durable store; local caches go stale; a session's memory is a guess. Pick the one you can trust.

---

## 2 — hooks are law; prose is hints

If the first pattern is about *what* you reconcile against, the second is about *how* you enforce.

The answer is: not by writing rules in a prose file the agent reads. The agent drifts from prose. Prose is a hint; the agent may or may not read it, and even if it does, "please don't do X" is one weight in a soup of many. What you want is *code that refuses to let the agent do X*. A gate that fails closed.

Drift's harness has about fifteen such hooks. The most important is `require-claim`, a `PreToolUse` gate: if a senior or junior session tries to fire `Edit` or `Write` without holding a claim on a GitHub issue, the hook returns a deny signal and the tool call never runs. It doesn't matter what the session read in the program file. It doesn't matter what it thought it was doing. The gate doesn't negotiate.

Same shape for queue cap (`sprint-cap` refuses `gh issue create --label sprint-task` when the open queue is at or above 100 — because planning quality is inverse to queue size), for read-before-edit (every `Edit` on an unread file is refused), for TestFlight publishes (a pre-publish hook verifies build number and push target). Fifteen hooks, each under thirty lines of bash, each a chokepoint the session cannot route around.

Docs are hints the agent may or may not follow; hooks are enforced. Use laws for anything you'd be upset about if the agent broke it. When something goes wrong, you don't debug by rewriting a prompt — you tighten a hook.

---

## 3 — atomic claim or nothing

Early on, I watched a senior session spend twenty minutes "investigating" a task. No `in-progress` label. No claim. No visible indication anywhere that it was working on anything. Eventually it crashed, and a second session spun up and picked up the same task from scratch. Classic **peek-without-claim** — the session had read the queue, decided what to do, but hadn't yet marked the task as taken. Between those two operations, anything can happen.

The pattern is distributed-systems 101: make the read-and-claim one atomic operation.

One script call does both — returns the next task and marks it `in-progress` on GitHub, under a single lock file:

```bash
TASK=$(scripts/sprint-service.sh next --senior --claim)
```

The caller never sees a task that wasn't already claimed. And the `require-claim` hook from the previous section finishes the job: no claim held, no `Edit` or `Write` fires. Work without a claim can't happen.

Here's what that looks like end-to-end, on an actual bug from two days before I wrote this — issue **#220**.

A beta user filed a bug from inside Drift via the "Report Issue" flow. Title: *"Not able to edit ingredient list when I edit a recipe or meal from food diary."* Body, verbatim:

> *"Just lists down ingredients but no option to edit. Show the same view when it was added."*

Screenshot attached. Filed at `13:24:57` UTC with a `P0` label.

The watchdog, which ticks every thirty seconds and reconciles against GitHub, noticed the new `P0-bug` on its next pass. Within a minute, a senior session spawned. It ran atomic `next --senior --claim`, got issue #220 back already marked `in-progress`. It read the full issue, screenshot included. It posted a plan comment first — a `PostToolUse` hook requires a plan comment before the first `Edit` — diagnosed the affected view, patched it, ran the unit tests, watched them pass, committed, pushed.

Eleven minutes and nineteen seconds after the issue was filed, at `13:36:16` UTC, GitHub's timeline shows the fix commit and the `in-progress → closed` transition, in that order.

I was walking the dog.

That kind of close happens three to ten times a week on shallow bugs. The ones that don't close that fast need a design call or a product judgment — i.e., places where the bottleneck is me, not the loop. When I have an opinion, the harness waits for my comment. When I don't, it ships.

---

## 4 — tool calls are the pulse

Before I had a proper liveness signal, I was using log-file modification time as the check for *"is this session still alive?"*. It lied. During long generation bursts — the model thinking for ninety-plus seconds before producing any tool call — the log file didn't move. The watchdog kept concluding the session was stalled, killing it mid-thought, and wasting its work. I lost real progress that way more than once.

The fix is obvious in retrospect: don't infer liveness, measure it. A dedicated heartbeat that updates whenever the agent is actually doing something.

In Drift's harness, the heartbeat is three lines of bash, wired to both the `PreToolUse` and `PostToolUse` hooks — so it fires on every tool call, before and after:

```bash
#!/usr/bin/env bash
date +%s > ~/drift-state/session-heartbeat
echo "$(date +%s) $CLAUDE_TOOL_NAME" >> ~/drift-state/session-heartbeat.log
```

That's the entire signal. The watchdog reads that first file — not the log, not the process table — to decide whether the session is alive. Stale threshold: thirty minutes without a tool call. Tool calls are the pulse. They're also the only meaningful indicator of activity in a language-model agent: reasoning without a tool call is invisible by design, and a session that has gone silent for thirty minutes has gotten stuck in a thinking loop rather than doing useful work.

Every ten minutes, a snapshot script bucketizes `session-heartbeat.log` into a JSON file, commits it, and pushes. The Command Center — a static HTML page on GitHub Pages — renders that JSON as an ECG strip:

```
Session heartbeat (last 4h)           Peak burst: 34 calls / 5 min
  ▁▁▁▂▂▃▄▅▅▆▇▇▆▅▄▃▂▁▁▁▂▃▄▅▆▇█▇▆▅▃▂▁▁▁▂
  │       senior start    senior done    │   planning
```

When I glance at my phone at 11 pm and the line is flat, I know. When it's moving, I go to bed. The liveness channel isn't for the harness — it's for the human. Its job is to let me *not* pay attention most of the time, and to make it cheap to pay attention when I want to.

One additional piece: **every supervisor needs a supervisor.** A session can crash; the watchdog restarts it. The watchdog itself can crash; nothing restarts it without help. So I wrap the watchdog in a `launchd` plist — the thing macOS uses to keep daemons up — with `KeepAlive=true` and `ThrottleInterval=30`. If the watchdog exits for any reason — shell panic, Mac reboot, OOM — launchd brings it back within thirty seconds. The supervisor tree goes all the way up until it hits the OS, which is the one thing I trust to stay up.

---

## 5 — the loop that fixes itself

The first four patterns make it possible to run the loop unattended for long stretches. This one is what makes the loop actually get *better* while it runs — and it's where the work starts to feel like it has a mind.

The version of the harness I started with did not close its own feedback loop. When autopilot hit a systemic problem — a rate limit, a flaky test, a pattern the model kept repeating — I had to notice and fix it manually. That scales to roughly a weekend. Past a weekend, the harness itself needs to be learning.

The version in this repo does. Every planning session, as its first step, runs `issue-service.sh drain-feedback`: it reads issues labeled `process-feedback`, and if they describe systemic problems, converts them into `infra-improvement` tasks on the harness's own backlog. The harness fixes itself over time.

But the sharper expression of this pattern is in the **personas**. Two of them: a Product Designer and a Principal Engineer. They started as seed files I wrote in an afternoon. They have now been through fifty-four full product reviews, and every review ends with an appended block titled *"What I Learned — Review #N."* Those blocks stack up and become the context for every subsequent cycle. The personas develop taste. They remember past mistakes. They start pushing back on me when I'm wrong.

You can watch it happen. Here's the Designer in Review #11, about two hundred cycles ago, at the level of a fresh observation:

> *"Spent too many cycles on blanket code refactoring (code-improvement loop) instead of user-facing features. Merged into single autopilot loop."*

Useful, but surface-level. By Review #17 (cycle 620), the same persona is generalizing:

> *"Systematic bug hunting (running an analysis agent across pipeline files) found 4 silent data-accuracy bugs. This should be a quarterly ritual, not just reactive."*

By Review #54, last week, the Designer is making executive-level calls and quoting competitive intel back at me:

> *"Review #53 named them P0 for the very next senior session. They're still in queue. Whoop is now demonstrating exactly this pattern (Behavior Trends) to their 4M+ users. We built `cross_domain_insight` first — we have the pattern, the schema, and the service layer. Not shipping these two tools is a competitive mistake that compounds every cycle."*

The Engineer persona tracks the same arc, ending Review #54 with what is effectively a mini-RFC:

> *"For `supplement_insight` and `food_timing_insight`: the AnalyticsService infrastructure from `cross_domain_insight` is already there — implementation is 1–2 new service query methods plus schema. This can ship in a single senior session if scoped correctly."*

That's not a lessons-learned bullet. It knows the codebase. It scopes the work. It predicts what will ship in one session. And it got there not because I wrote a better prompt — I have never hand-edited the Engineer persona — but because every review stacks another paragraph of taste onto the file, and each subsequent cycle reads the accumulated file as context.

There's a minor governance structure inside these reviews worth naming: **a two-persona deliberation pattern.** They don't write the review jointly. Each one writes a *My Recommendation* block. Then there's a *The Debate* block where they argue — on the page, in the PR — and converge on an *Agreed Direction*. If they can't agree, the review ends with numbered *Decisions for Human* questions pinned to me. Here's a representative exchange from Review #54:

> **Designer:** *"The queue-cap was the right call six cycles ago and it's still right. We're at 101. Every new task added today is a task that will be 2,000 cycles old before it ships. I'm going to advocate for a hard rule: this planning session creates ≤4 new tasks — P0 bugs, mandatory eval run, and State.md refresh only."*
>
> **Engineer:** *"I support the spirit, but `program.md` requires 8+ tasks as DOD for this session. I don't want to create tasks for the sake of it — but there are two legitimate gaps that aren't in the current queue…"*
>
> **Agreed Direction:** *"Queue cap of 70 is re-affirmed — planning sessions creating >8 tasks when queue exceeds 70 are blocked. Senior execution drain rate is the only lever that matters for product velocity."*

Neither persona has unilateral authority. Neither one is me. And the point isn't the specific debate — it's that the harness has an opinion of its own, developed across fifty-four reviews, that converges before asking for my time. When it does ask, it asks three sharp questions in a block called *Decisions for Human*. I read that block in bed on my phone, tap approve on one, reply *"defer"* on another. The harness picks up my replies on the next planning cycle and adjusts.

That is what I mean when I say the feedback loop is the architecture. The harness isn't just shipping features — it is studying the market, taking a position, defending the product, and educating me about what to prioritize.

I first heard about MyFitnessPal adding GLP-1 medication tracking in a product-review PR from my own autopilot, not from the tech press. That still sits oddly with me.

The direction this is all pointing — and the part still half-built — is a voting system with more than two voters. The personas are two. The LLM eval harness is a small handful of golden prompts. Beta-user reactions on issues and exec-report PRs are a few dozen signals a week, and unlike the personas those *are* independent signal. The next lever against the human-attention bottleneck is to let a handful of A/B-tested beta-user votes become the real eval, so the harness can fix its own taste from users without me having to ratify every change. More on that below.

---

## a week in the life, at a glance

Every pattern above is distilled from actual traces the harness left behind. The seven-day trace from the week before I wrote this, as a single picture:

```
  Drift Control · last 7 days
  ─────────────────────────────────────────────
    409   commits pushed (0 written by me)
      9   features shipped
     30   distinct bug issues closed (most from beta users)
      9   product reviews (competitor studies)
      3   TestFlight builds published

  Session activity (tool-call heartbeat)
  ─────────────────────────────────────────────
  Mon  ▂▃▅▆▅▄▃▂▂▃▄▅▅▆▇▇▆▅▄▃▂▂▁▁
  Tue  ▁▂▃▄▅▆▇█▇▆▅▄▃▂▂▃▄▅▅▆▇▆▅▄
  Wed  ▂▃▄▅▆▆▅▄▃▂▂▃▄▅▆▇▇▆▅▄▃▂▁▁
  Thu  ▁▂▃▅▆▇▇▆▅▄▃▃▄▅▆▆▅▄▃▂▂▁▁▁
  Fri  ▂▃▄▅▆▆▅▄▃▃▄▅▆▇▇▆▅▄▃▂▂▁▁▁
  Sat  ▁▁▂▃▄▅▆▆▅▄▃▂▂▃▄▄▃▃▂▂▁▁▁▁
  Sun  ▁▂▃▄▅▅▄▃▂▂▁▁▂▃▄▅▆▆▅▄▃▂▁▁
       0   4   8  12  16  20  24  (UTC hours)

  Notable events
  ─────────────────────────────────────────────
  Mon  bug #220 filed by a beta user → closed 11m19s later
  Tue  TestFlight build 170 auto-published
  Wed  product review #54 — Designer flags two queued features
       as a compounding competitive risk vs Whoop
  Thu  five-bug bundle from photo-log screenshots (single commit)
  Sat  eleven planning sessions fire in four hours
       (the failure that became pattern #1)
```

I did no code work that week. I read five of the exec reports, approved one design, and left two comments on the product review. The rest ran itself.

---

## the dial I actually turn

One question I keep getting: *how do you steer this thing, exactly?*

The answer isn't one lever. It's a dial with roughly six settings, from *"don't touch it"* to *"take the wheel."* Most days I use the light ones.

| Setting | What I do | What the harness does |
|---|---|---|
| **0. Nothing** | Close the laptop. | Reads the roadmap, runs product reviews, learns from past cycles, picks the next thing from its own backlog. **Comes up with features on its own taste** — the one that accumulated across fifty-four reviews — and ships them. Defaults are usually fine. |
| **1. Strategic nudge** | One-line comment on a product-review PR: *"focus on food-DB coverage this week."* | Next planning session treats it as a priority signal. No rewrite of anything. |
| **2. Design-review request** | Add a `design-doc` label to an issue. | Senior session writes a design doc on a branch, PRs it, waits for my comment. Implementation only starts after I approve. |
| **3. Feature request** | File a GitHub issue with `feature-request` + one paragraph of intent. | Planning triages it into the sprint as P0/P1 or labels it `deferred`. I don't pre-specify files or approach. |
| **4. P0 bug** | Filed with a `P0` label, usually from a beta user. | Interrupts on the next tick, picks it up on the senior session. The eleven-minute flow from pattern #3. |
| **5. Take the wheel** | `echo PAUSE > ~/drift-control.txt`, open Claude Code in human-shepherded mode, type. | Stops spawning sessions. Session-start hook detects human mode and suppresses auto-publish. `echo RUN` resumes the loop. |

The counterintuitive part: the lighter the intervention, the more the personas compound. Setting 2 — design-review request — has become what I use most often for anything I care about shaping. Most of my product decisions now happen by reading a design PR and leaving two comments.

The harness isn't really about autonomy. It's about choosing where to spend attention.

---

## what remains unresolved

A few pieces are open problems. I'm writing about them because the essay would be dishonest without them.

**Parallelism.** Sessions fire sequentially on one laptop. I looked at parallel agents — separate git worktrees, isolated simulators, a scheduler — and concluded the reliability tax was not worth it for an app Drift's size. `xcodebuild` and the simulator are hostile to concurrency. Sequential is simpler, observable, and good enough. That conclusion will probably invert once throughput becomes the bottleneck, and I don't have a good design for the parallel version yet.

**Multi-repo generalization.** The whole harness is Drift-specific in small ways — the testing cadence assumes Xcode, the TestFlight hook assumes an iOS build, the persona files assume a health app. I think most of it generalizes, but I haven't ported it to a second project, so I don't know which pieces are portable and which are load-bearing in ways I haven't noticed.

**The voting system.** The personas already act as a two-voter body (Designer and Engineer, debating and converging). But two samples from the same model aren't independent votes. The LLM eval harness is another small body of voters — a handful of golden prompts a release has to pass. Beta users, via thumbs-up reactions on issues, via direct bug reports, via a small number of in-app prompts asking *"is this answer right?"*, are yet another body — and unlike the personas, those *are* independent signal. Today those feed back informally: I read reactions and nudge the harness with a comment. The direction I want to push this is to formalize it — a handful of A/B-tested changes per cycle, scored by real beta-user votes, fed back into the planning signal as ground truth. The premise is the same as the rest of the essay: human attention and taste are the bottleneck, and the fastest way to loosen that bottleneck is to let real users' A/B votes become the actual eval, so the harness can fix its taste from users rather than from me. It is in the plan. It is not yet in the repo.

**The class of work the loop still can't do.** Shallow bugs, yes. Scoped refactors, yes. Product direction calls, no. Anything that requires taste I haven't externalized into a persona or a hook still falls on me, and the bottleneck is exactly there. The harness has raised the floor — more ships while I'm not looking. It hasn't raised the ceiling of what I can design when I am.

---

## the actual hooks

If you want the whole zip, see *replicate it* below. If you just want to know what these patterns look like in code, here are two of the load-bearing pieces.

**The heartbeat**, wired as both `PreToolUse` and `PostToolUse`. Fires on every tool call, before and after. Three lines:

```bash
#!/usr/bin/env bash
date +%s > ~/drift-state/session-heartbeat
echo "$(date +%s) $CLAUDE_TOOL_NAME" >> ~/drift-state/session-heartbeat.log
```

**The claim-required gate.** `PreToolUse` on `Edit|Write`. If the session isn't holding at least one `in-progress` issue on GitHub (or isn't on a review / report / design-doc branch), the hook denies and the tool call never fires. The harness literally cannot do ghost work:

```bash
#!/usr/bin/env bash
# require-claim.sh — blocks Edit/Write unless this session holds a claim
BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null)
if [[ "$BRANCH" =~ ^(review/cycle-|report/exec-|design-doc/) ]]; then exit 0; fi
COUNT=$(gh issue list --label in-progress --json number --jq 'length' 2>/dev/null || echo 0)
if [[ "$COUNT" -lt 1 ]]; then
  echo "BLOCKED: this session is not holding a claim on a sprint-task issue." >&2
  exit 2
fi
exit 0
```

Two files. Maybe forty lines together. They do most of the load-bearing work in this essay.

---

## replicate it

Everything is zipped at [`drift-command-center-replicate.zip`](./drift-command-center-replicate.zip) in this folder:

- `program.md` — the autopilot program the watchdog drives
- `.claude/settings.json` + `.claude/hooks/*.sh` — every enforcement hook (`require-claim`, `sprint-cap`, `session-heartbeat`, `guard-testflight`, `pause-gate`, …)
- `scripts/self-improve-watchdog.sh` — the watchdog
- `scripts/sprint-service.sh`, `planning-service.sh`, `issue-service.sh`, `design-service.sh`, `report-service.sh` — the state-machine CLIs the sessions call
- `scripts/session-monitor.sh` — live summaries via a smaller model
- `scripts/heartbeat-snapshot.sh` — log → JSON for the dashboard
- `scripts/install-watchdog.sh` + `com.drift.watchdog.plist` — launchd supervision
- `command-center/` — the dashboard (static HTML/JS)
- `REPLICATE.md` — one-page quickstart for adapting it to a different repo

It isn't a framework. It's a kit. Cut and paste what you need, replace the Drift-specific bits, keep the shape.

---

## ps. links

- Repository: [github.com/ashish-sadh/Drift](https://github.com/ashish-sadh/Drift)
- Ralph loop, the original: [ghuntley.com/ralph](https://ghuntley.com/ralph/) — go read this, it's where the engine comes from
- Dashboard (currently live): the Command Center page in the repo
- The next bug report came from one of those same friends. Drift is on twenty-five phones. The harness built most of it while I slept. If you have a small app and a spare laptop, yours could ship the same way.
