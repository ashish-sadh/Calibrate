# The app that ships itself

If you know me, you know I geek out about health metrics, whether you asked or not.

That is how Drift started: a hobby iPhone app because eight different health apps, each with its own subscription, still could not answer basic questions about my own data.

Drift keeps everything on your phone. It reads Apple Health, runs a small local model, and lets you chat with your health data. No account. No cloud. No server bill. For advanced features, you can bring your own API key for your favorite frontier model.

Free, local, open source.

But Drift is not the interesting part.

The interesting part is what built it.

I did not want to spend months sitting in a chat window vibe-coding with Claude. I wanted a loop: plan, code, test, ship, learn, repeat.

The core idea comes from the Ralph loop, popularized by [Geoffrey Huntley](https://ghuntley.com/ralph/): a tiny bash loop that keeps restarting an AI coding agent with fresh context. The model does not "remember" the project. The project remembers itself through files, issues, git commits, and trackers.

That sounds almost stupid.

That is why it works.

My version has been running for months. Not because the prompt is magical, but because the harness around the model got good.

That is the real lesson for me: **human attention is the scarce resource, and the harness is where your taste lives.**

Not in the model.
Not in the prompt.
In the scaffolding.

The gates that block bad tool calls.
The hooks that fail closed.
The issue labels that prevent ghost work.
The personas that slowly compound judgment.
The dashboard I can check from my phone.

In one recent week, the harness pushed 409 commits, closed 30 bugs, and shipped three TestFlight builds. I wrote none of that code.

Drift is the dish.
Drift Control is the kitchen.

The kitchen has a few rules:

**1. Trust durable state, not memory.**
If a session says it planned something, I do not trust the session. I check git, GitHub, and the filesystem.

**2. Hooks beat prose.**
Docs are suggestions. Hooks are law. If the agent tries to edit without claiming an issue, the tool call is denied.

**3. Claim work atomically.**
No "let me investigate" without ownership. A task is claimed and marked in progress in one locked operation.

**4. Tool calls are the heartbeat.**
Logs lie. The harness tracks actual tool activity to know whether a session is alive or wedged.

**5. The loop improves itself.**
Bugs in the process become process-improvement tickets. Product reviews feed two personas: a Product Designer and a Principal Engineer. After 50+ reviews, they do not just summarize. They argue, scope, prioritize, and hand me only the decisions that actually need human taste.

That is the part I did not expect.

The more lightly I touch it, the more the system compounds. A one-line comment on a review PR becomes a priority signal. A design-doc label becomes a branch. A P0 bug can interrupt the loop and get fixed in minutes.

Autonomy is not the point.

The point is choosing where my attention goes.

Right now, the loop is still very imperfect. It runs mostly one session at a time. Product direction still needs me. The personas are not truly independent. Beta-user reactions are not yet wired in as real evals.

But the floor has moved.

Shallow bugs close while I sleep.
The app keeps improving.
And I spend more time making product calls than babysitting code.

That feels like the future of one-person software: not replacing taste, but building a machine that protects it.

Drift is on TestFlight. Drift Control, the harness, is zipped up too.

The app is the demo.
The loop is the point.

---

- Drift public beta: [testflight.apple.com/join/NDxkRwRq](https://testflight.apple.com/join/NDxkRwRq)
- Repository: [github.com/ashish-sadh/Drift](https://github.com/ashish-sadh/Drift)
- Drift Control kit: [drift-command-center-replicate.zip](../drift-command-center-replicate.zip)
- Ralph loop, the original: [ghuntley.com/ralph](https://ghuntley.com/ralph/)
