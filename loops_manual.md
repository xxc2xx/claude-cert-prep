# Claude Code Loops — An Applied Coursebook

*By Derek Hobden · June 2026 · Requires Claude Code v2.1.139+*

## Preface

This is a course about a single shift: from *prompting* a coding agent to *designing the loop it runs inside*. It is written for engineers who already use Claude Code competently and want to operate it the way the people who built it do — running many agents, overnight, against conditions they can prove, with guardrails an auditor would accept.


The premise of the field, in the words of the engineer who leads Claude Code: his job is now to *write loops* rather than prompts. That sounds glib until you see what it unlocks — and what it costs when you get it wrong. A loop is leverage, and leverage points in both directions. The discipline of this book is keeping it pointed the right way.


Read it in order; the chapters build. Run the labs on a throwaway branch, not `main`. And treat every version number and billing figure as a snapshot — they are accurate to June 2026 and they move fast.


## How to use this book

Each chapter follows the same rhythm: a short orientation, numbered sections, fully *worked examples*, a *gallery* showing the range of a tool's uses, a diagram or two, the failure modes, a hands-on lab, and exercises with solutions you can reveal. The recurring devices:

Worked ExampleA complete, explained case — what you'd type, why, and what happens. Numbered per chapter (Example 1.2).GalleryA spread of distinct uses for one concept — the "what else could I do with this?" pages. Skim them for ideas.MechanismHow something works under the hood, so you can reason about it instead of memorising it.PitfallA failure mode, its cause, and the fix.Try itA short exercise to run in your own terminal right now.ExercisesEnd-of-chapter problems. Click "Show solution" to check yourself.A note on accuracy
Command syntax, version gates, execution surfaces, and especially billing change month to month. Where a fact is version- or price-specific, this book date-stamps it. Re-verify anything load-bearing against code.claude.com/docs and your own `/status` before you depend on it. The mental models are the durable part.

 ===== CHAPTER 0 ===== Chapter 00 · Part I
## Ch 0 — The shift to loop engineering

"Loop" is one word doing three jobs. Separating them is most of the clarity you need.

Learning objectives- Distinguish the three things people mean by "a loop," and how they compose.
- Explain why a continuously-running loop differs in kind, not degree, from a single agent run.
- Name the six primitives of a production loop and where each lives in Claude Code.
- Classify any task you have as goal-bounded or interval-driven.


### 0.1 Three things called "a loop"

When an engineer says "I run loops," they are usually collapsing three independent ideas. Keep them apart and the rest of this course falls into place.

- **Goal loops** run until a *verifiable condition* holds, then stop. Bounded; you don't know how many turns it takes. (`/goal`)
- **Interval / event loops** re-run on a clock or fire on a trigger. Continuous; they poll and watch. (`/loop`, `/schedule`, Routines)
- **The execution surface** is *where* the loop physically runs — your open terminal, the desktop app's scheduler, or Anthropic's cloud. It decides whether your machine must stay awake and which account is billed.


Your real questions — "does it stop on its own?", "where do I put it?", "does it cost tokens?" — are each about one of these three. And you *compose* them: a scheduled loop (surface + interval) that, each time it fires, runs a goal-bounded task.


*[Diagram: Figure 0.1 The three primitives and how they combine.]*


### 0.2 Why a loop is different in kind

A single agent run gives you *leverage*: you delegate a task and get it back. A loop gives you *compounding*: each cycle resumes from a recorded state and builds on it, so value accrues without more input from you. The unit of work changes from "a turn" to "a system that decides the next turn." This is why the framing is "loop engineering" — you are no longer the operator of each step; you are the designer of the process.


### 0.3 The six primitives

A complete production loop decomposes into six parts, and they map almost one-to-one onto Claude Code and OpenAI Codex. Each is a chapter of this book.

| Primitive | Job | In Claude Code | Chapter |
| --- | --- | --- | --- |
| Discovery / scheduling | find work on a cadence | /schedule, Routines, desktop tasks | 2–3 |
| Goal-conditioned execution | work until a stop condition holds | /goal | 1 |
| Verification | a separate agent grades the result | checker subagent, the /goal evaluator | 4 |
| Memory / state | persist across runs | CLAUDE.md, state files | 8 |
| Parallelism / isolation | many agents, no collisions | git worktrees, /batch | 6 |
| Safety / circuit-breakers | stop a runaway | turn caps, hooks, scoped permissions | 7, 12 |
Pitfall · the load-bearing warning
An unattended loop without a verifier is a machine that ships bugs with high confidence. Every chapter that follows is, in part, about keeping the leverage pointed the right way. If you remember one sentence from this book, remember that one.

Try it · classify your own work
List three recurring tasks in your codebase. For each, ask one question: *am I pushing this to a finish line, or watching for something to change?* Tag each `goal` or `interval`, and note the surface it should run on (terminal now / this machine overnight / cloud while travelling). You've just scoped three loops before writing a line.

Summary- "Loop" means three separable things: goal loops (stop on a condition), interval/event loops (re-run on a cadence), and the surface they run on.
- Loops compound where single runs only leverage; that is the whole reason to build them.
- Six primitives make a complete loop; the rest of the book is one chapter per primitive plus the practice that ties them together.

Exercises 0- Give an example of a task that is genuinely *both* — a scheduled cadence whose body is itself goal-bounded. Which primitive supplies which part?             Show solutionA nightly dependency audit: the **interval** primitive (a Routine) fires once a night; the body is a **goal** ("every outdated dependency has a PR with a green test suite"). The schedule decides *when*; the goal decides *when each run is done*.
- Why would putting a `/loop` on a "fix until tests pass" task waste money, and putting a `/goal` on a "watch the deploy" task never terminate?             Show solutionA `/loop` has no notion of done, so it re-runs the finished fix forever on the clock, burning turns. A `/goal` needs a verifiable end state; "watch the deploy" has none it can reach, so the evaluator never returns yes and the loop runs until you stop it.
- State, in one sentence each, what "compounding" buys you over "leverage," using a concrete codebase chore.             Show solution**Leverage:** "Document this module" — done once, you move on. **Compounding:** "Each night, document the next undocumented module and record progress" — the codebase's documentation coverage rises on its own over weeks, because each run resumes from recorded state.

 ===== CHAPTER 1 ===== Chapter 01 · Part I
## Ch 1 — The goal loop

Give Claude a finish line it can prove, and stop pressing enter.

Learning objectives- Describe the separate-evaluator architecture and the one constraint it imposes on every condition.
- Write conditions with all four required components, and tell a good condition from a bad one.
- Apply `/goal` across interactive, non-interactive, desktop, and Remote Control modes.
- Recognise the breadth of work a goal can target — not just "make tests pass."


### 1.1 From function call to while loop

Ordinarily Claude Code runs like a function call: you ask, it works, it stops, you check, you re-prompt. `/goal` turns that into a loop. You state a completion condition and Claude keeps taking turns until the condition holds or you interrupt.

Mechanism · the separate evaluator
After *each* turn, the transcript plus your condition go to a small, fast model — it defaults to **Haiku** — whose only job is to answer one question: is the condition met, yes or no? A "no" comes back with a short reason, and that reason becomes the next turn's instruction. A "yes" clears the goal. Crucially, the model deciding "done" is *not* the model doing the work — which is what stops Claude from quietly grading its own homework. Under the hood, `/goal` is a wrapper around a session-scoped, prompt-based `Stop` hook (Chapter 7). Requires Claude Code **v2.1.139+**.


*[Diagram: Figure 1.1 The evaluator loop. The checker only ever sees what's in the transcript.]*


### 1.2 The one constraint that governs every condition

The evaluator **cannot run commands, call tools, or read files**. It judges only what Claude has already surfaced in the conversation. That single fact dictates how you write conditions: describe an *observable end state*, and make the work *print its own proof*. "All tests pass" works because the runner's output lands in the transcript. "The code is clean" fails — there's no command whose output flips from no to yes.

Worked Example 1.1 Bad conditions vs good conditions
Each "bad" condition has nothing concrete for the evaluator to point at, so the loop either spins or hallucinates completion. Each "good" one names a check whose output is unambiguous.

text · spins or fakes completioncopy
```plaintext
/goal clean up this file
/goal improve the test coverage
/goal make the auth flow better
```

text · the evaluator has something to checkcopy
```plaintext
/goal `npm test` exits 0 with no failures in test/auth, and `npm run lint` is clean
/goal pytest-cov reports >= 85% coverage on src/billing; do not edit migrations
/goal every call site of the old fetchUser() compiles against the new signature and the build exits 0
```


**What happened:** the fix wasn't the wording of the task — it was attaching a *runnable check* whose output appears in the conversation. That's the entire craft of writing a goal.


### 1.3 Anatomy of a condition

The docs recommend four components. Treat them as a checklist every time you write one.

| Component | What it is | Example |
| --- | --- | --- |
| End state | a measurable result | "all tests in test/auth pass" |
| Stated check | how to prove it | "run pytest test/auth -q and show output" |
| Constraints | what must not change | "do not touch the schema or migrations" |
| Cap | a circuit breaker | "stop after 20 turns and summarise" |
Gallery 1.1 What a goal can target
A goal is not just "make the tests pass." Any time you can name a command whose output proves done-ness, you can drive it with `/goal`. A spread, across domains:


##### Failing test → green

Drive a single broken test or a whole suite to passing.

`/goal `npm test` exits 0, no failures in test/orders`
##### Type / compile clean

Eliminate type errors after a refactor.

`/goal `tsc --noEmit` reports zero errors`
##### Coverage threshold

Raise coverage to a bar on a specific package.

`/goal pytest-cov >= 85% on src/billing; no edits to migrations`
##### Lint & format

Reach a zero-warning state across a directory.

`/goal eslint and `prettier --check` are both clean in src/lib`
##### Performance budget

Hit a latency target shown in a load-test report.

`/goal the load test shows /search p95 under 200ms`
##### Reproduce & fix a bug

Turn a red repro from an issue into a passing test.

`/goal the repro in issue #412 now passes and a regression test covers it`
##### Refactor completeness

Remove every trace of a deprecated API.

`/goal no references to the old Logger remain and the build exits 0`
##### Data / content invariant

Enforce a property over a data file.

`/goal every product in catalog.json has a non-empty description`
##### Docs in sync

Backfill documentation to a checkable standard.

`/goal every public fn in src/api has a docstring; doc-lint passes`
##### Accessibility

Drive an automated a11y scan to zero violations.

`/goal axe-core reports zero violations on the checkout page`
Notice the pattern across all ten: each pairs a target state with a command whose output the evaluator can read. If you can't name that command, the goal isn't ready.

Worked Example 1.2 A mechanical refactor, compile-gated
Renaming an API across dozens of call sites is tedious and exactly the kind of bounded, verifiable work a goal excels at. The compile is the proof; the constraint keeps it from "fixing" things by deleting them.

bashcopy
```bash
/goal every call site of `fetchUser(id)` is migrated to `getUser({ id })`,
the project compiles with `tsc --noEmit` showing zero errors, and no call site
is deleted or stubbed to achieve this; stop after 30 turns and summarise
```


**What happened:** the explicit "no deletion/stubbing" constraint closes the cheapest way for a model to make a check pass without doing the work — a recurring theme you'll see again in Chapter 4.

Worked Example 1.3 An invariant over data, not code
Goals aren't only for source. Here the "codebase" is a content file, and the loop fills gaps until a property holds for every record.

bashcopy
```bash
/goal every entry in data/authors.json has fields { name, bio, country },
bios are 2-3 sentences, and `node scripts/validate-authors.js` prints "OK";
do not invent biographical facts — mark unknowns as null; stop after 25 turns
```


**What happened:** the validation script is the evaluator's eyes, and the "don't invent facts" constraint guards against the loop satisfying the schema with plausible fabrication.


### 1.4 Where it runs

`/goal` works across four modes. In non-interactive mode it runs the whole loop to completion in a single invocation.

bashcopy
```bash
# interactive: type it in your session
/goal CHANGELOG.md has an entry for every PR merged this week; stop after 15 turns

# non-interactive: runs to completion; Ctrl+C to abort
claude -p "/goal CHANGELOG.md has an entry for every PR merged this week"

# pair with auto mode so each turn runs unattended (no per-tool prompts)
# auto mode removes per-tool confirmation; /goal removes per-turn confirmation
```


It also works in the desktop app and over Remote Control. Mind the `-p` billing caveat in Chapter 3 before wiring it into anything scheduled.

Pitfall · there is no built-in token budget
`/goal` runs until the condition is met or you interrupt with Ctrl+C (or `/goal clear`). A vague condition can loop for hours burning tokens. Put a turn cap *inside the condition itself*. And beware **compound goals** — "redesign auth, add OAuth, write tests, update docs" overwhelms the evaluator; break it into sequential goals, each with its own verifiable end state.

Try it · drive a real bug to green
On a throwaway branch with one failing test, run a goal with all four anatomy components and a hard cap:

bashcopy
```bash
/goal the test test/orders/test_refund.py::test_partial passes under `pytest -q`;
show the passing output; do not modify the test or any migration;
stop after 12 turns and summarise if not done
```


Watch the evaluator's reasons between turns. If it loops without progress, your condition is checking a proxy — restate it with a more directly checkable command.

Summary- `/goal` loops Claude until a separate fast model judges your condition met; the checker sees only the transcript.
- Every condition needs an observable end state, a stated check, constraints, and a cap — and the work must print its proof.
- Goals target far more than tests: types, coverage, performance, data invariants, docs, accessibility — anything with a runnable check.
- There's no token budget; the cap is your circuit breaker, and compound goals should be split.

Exercises 1- Rewrite this into a proper goal: "tidy up the logging in the payments service."             Show solutionSomething like: `/goal every log call in src/payments uses the structured logger (no console.log), `npm run lint:logging` is clean, and the test suite still exits 0; do not change log levels or remove logs; stop after 20 turns.` The key moves: name the observable target, attach a lint check, and constrain against lossy shortcuts.
- Your goal keeps "completing" with the bug still present. Give two distinct causes and the fix for each.             Show solution**(i) Ambiguous condition:** nothing concrete to verify, so the evaluator hallucinates yes — fix by naming a runnable check. **(ii) Proof not surfaced:** Claude claims success without showing the failing command now passing — fix by requiring the output in the condition ("show the passing output").
- Why does keeping the evaluator transcript-only (rather than letting it run commands) actually make goals *more* reliable to write, not less?             Show solutionIf the evaluator could run tools it would become a second full agent — slow, costly, and able to disagree with the worker about reality. Keeping it transcript-only makes verification cheap and deterministic and forces *you* to ensure the work emits its own evidence, which is exactly the property that makes a loop auditable.

 ===== CHAPTER 2 ===== Chapter 02 · Part I
## Ch 2 — The interval loop

When the work is happening elsewhere and you just want to be told the moment it changes.

Learning objectives- Use `/loop` for cadence-driven work, and pick the interval deliberately.
- Apply the single question that decides between a goal loop and an interval loop.
- Compose `/loop` with a goal so the agent can't cut corners.
- See the breadth of jobs that suit a clock rather than a finish line.


### 2.1 A clock, not a finish line

`/loop` re-runs a prompt on a clock. It is the opposite tool from `/goal`: it has no notion of "done," it just fires again on a cadence. Reach for it when you're *watching*, not finishing.

bashcopy
```bash
# fixed interval: fire this prompt every 5 minutes until you press Esc
/loop 5m check if the deploy to staging finished and tell me what changed

# no interval: Claude picks the gap each round (~1 min to ~1 hour) from activity
/loop watch the long build and ping me the moment it goes red or green
```


It runs until you press Esc. The classic error is pointing the two primitives at each other's jobs — the whole of Figure 2.1.


*[Diagram: Figure 2.1 The one question that picks the primitive.]*

Gallery 2.1 Jobs that suit a clock
Interval loops shine wherever the value is in *noticing* or in doing a small repeated chore — not in reaching a provable end. A spread:


##### Watch a deploy

Report status and the diff once it lands.

`/loop 3m report staging deploy status; on failure paste the first error`
##### Babysit PRs

Rebase, answer review, fix CI as it churns.

`/loop 5m /babysit`
##### Triage an inbox

Turn new feedback into labelled issues.

`/loop 30m /triage new entries in feedback/`
##### Guard a long job

Alert the instant a training run or batch finishes or errors.

`/loop 10m check the training job; ping me on completion or error`
##### Periodic smoke tests

Pull latest and run a fast health check.

`/loop 1h pull main and run the smoke suite; report only changes`
##### Prune the repo

Close stale branches and dead PRs.

`/loop 1h /pr-pruner`
##### Directory watcher

Process each new dropped file, then sleep.

`/loop 2m validate & transform any new file in inbox/, then archive it`
##### External-dep heartbeat

Re-run a flaky integration check until it stabilises.

`/loop 5m hit the partner API health route; alert on 3 consecutive failures`
##### Standup digest

Summarise overnight commits and open PRs each morning.

`/loop 24h post a one-paragraph digest of yesterday's merges to #eng`
##### Doc/site link-rot watch

Periodically scan for broken links and report.

`/loop 12h crawl docs/ for broken links; open an issue per new break`
Several of these (babysit, triage, pruner) point at custom command files — Chapter 5 shows how to write them. The cadence and the body are separate concerns.


### 2.2 Composing loop and goal

A bare `/loop` says "repeat execution." A `/loop` whose body carries a goal condition says "repeat until *this specific thing* is true" — which is how you stop the agent declaring "good enough" at 20 of 50 items. The loop supplies cadence; the goal supplies the enforceable stop.

Worked Example 2.1 Watch a build without babysitting the terminal
The point of the interval primitive is ergonomic: you stop staring at a terminal. Three fires, then you stop it.

bashcopy
```bash
/loop 2m report the CI build status in one line; if it failed, paste the first error and the failing job name
```


**What happened:** nothing exotic — but you reclaimed the attention you'd otherwise spend context-switching to check a dashboard.

Worked Example 2.2 A poll-and-act triage loop
Here each cycle does real work, so the body needs an explicit per-cycle task and a guard against hammering when there's nothing to do.

bashcopy
```bash
/loop 20m read any new files in feedback/, cluster them by theme,
open one labelled GitHub issue per distinct theme with a 2-line summary,
then move the processed files to feedback/done/. If nothing is new, say so and wait.
```


**What happened:** the "move to done/" step is the loop's memory — it prevents re-processing the same feedback next cycle, the simplest form of the state we formalise in Chapter 8.

Worked Example 2.3 A directory-watcher pipeline
An interval loop is a perfectly good lightweight data pipeline when the work is independent per file.

bashcopy
```bash
/loop 1m for each new .csv in incoming/, validate the schema, transform it to
parquet in processed/, log a line to pipeline.log with row counts, and archive the
original. Stop the cycle and alert if validation fails 3 times in a row.
```


**What happened:** the "3 failures in a row → stop and alert" clause is a circuit breaker (Chapter 7) — without it, a malformed file could make the loop spin on errors indefinitely.

Pitfall · a poll is not a worker
A bare `/loop` that only polls can spin tightly and waste turns. If the body is meant to *do* work each cycle, give it an explicit task *and* a sleep, and cap consecutive failures so a broken cycle trips a breaker rather than hammering on. For loops that must survive a closed terminal or a sleeping laptop, graduate from `/loop` to a scheduled task or Routine (Chapter 3).

Try it · watch something real
Kick off a slow build or deploy, then run `/loop 2m report the build status in one line; if it failed, paste the first error`. Let it fire three times, then Esc. That's the entire ergonomic win of the interval primitive in thirty seconds.

Summary- `/loop [interval]` re-runs on a clock until you press Esc; with no interval, Claude chooses the gap (≈1 min–1 hr).
- Use it to watch or to do small repeated chores — not to reach a provable finish line.
- Add a goal condition to enforce a real stop; add a failure cap so a broken cycle trips a breaker.

Exercises 2- You must rewrite 40 product descriptions to under 150 words each. `/loop` or `/goal`, and why is the other a money-burner?             Show solution`/goal` — there's a verifiable finish line ("all 40 under 150 words") and an unknown number of tries. A `/loop` would re-run on the clock with no idea it's finished, re-processing done items forever.
- Take the triage loop in Example 2.2 and add a guard so it never opens two issues for the same theme across cycles.             Show solutionAdd a dedup check against open issues before creating: "…before opening an issue, search existing open issues for the same theme label and skip if one exists." The move-to-done step handles file-level dedup; this handles issue-level dedup — both are state.
- Why does adding a goal condition to a `/loop` defeat the agent's tendency to declare "good enough"?             Show solutionThe goal's separate evaluator enforces the real stop condition after every turn, so the agent can't unilaterally decide it's done at 20 of 50 — it keeps going until the checker confirms the whole set meets the bar.

 ===== CHAPTER 3 ===== Chapter 03 · Part II
## Ch 3 — Surfaces & the cost model

Where a loop runs decides whether your machine must stay awake — and which account gets billed.

Learning objectives- Place any loop on one of the four execution surfaces and justify the choice.
- Trace the subscription-vs-API billing boundary, and avoid the `claude -p` trap.
- Verify your live billing route before trusting it.
- State what — if anything — genuinely requires the paid API.


### 3.1 Four surfaces, escalating in autonomy

This is the chapter that answers "does this cost tokens on my Max plan?" The short version: the high-value loops run under your subscription; only fully decoupled automation falls onto the per-token API path.


*[Diagram: Figure 3.1 The four surfaces, annotated with machine-state and billing route.]*

- **Tier 1 · In-session.**`/loop` and `/goal` in an open terminal. Machine awake; subscription. Start here to prototype.
- **Tier 2 · Desktop scheduled tasks.** In the desktop app: Schedule → New Task → New Local Task (name, prompt, frequency, permissions, working folder). Each run is an *independent session with fresh context*. Survives restarts and closed terminals, *but the machine must not be asleep*; if it is, the task won't run, and on wake Claude does one catch-up for tasks missed in the last 7 days. Subscription.
- **Tier 3 · Cloud Routines.** A saved config executed on Anthropic-managed cloud infrastructure — *runs with your laptop off.* All paid plans, beta since April 2026. Create at `claude.ai/code/routines` or with `/schedule` in the CLI; the CLI only creates *schedule* triggers, while the web adds **API** and **GitHub** triggers.
- **Tier 4 · Headless / SDK / Actions.**`claude -p`, the Claude Agent SDK, and Claude Code GitHub Actions — the genuinely per-token API path.


### 3.2 The billing boundary

*[Diagram: Figure 3.2 Billing decision tree — run /status before trusting any of it.]*

Pitfall · the `claude -p` trap (this one has cost people four figures)
Print mode has historically billed as per-token **API** usage *even with an active Max subscription and no `ANTHROPIC_API_KEY` set*. One Max subscriber who scheduled `claude -p` in agentic loops ran up over **$1,800 in two days**. Setting the key always routes to API billing. Before wiring any headless automation, run `/status` and do a one-turn test while watching where it lands. A Max subscriber who wants scheduled runs under the subscription should use Tier 2 or Tier 3 — *not* a `claude -p` cron.

Mechanism · policy in flux (date-stamp this)
On **May 14, 2026** Anthropic announced that Agent SDK + `claude -p` + GitHub Actions usage would leave subscription pools on **June 15**, moving to a separate monthly dollar credit at standard API rates (Pro $20 / Max 5× $100 / Max 20× $200, no rollover, one-time opt-in). That change was **paused** around mid-June — subscription coverage currently unchanged — but the stated direction is to meter agent compute separately. *Re-verify before building a pipeline that depends on it.*

Worked Example 3.1 Choosing a surface for a real job
"Run a dependency audit every night with my laptop closed, billed to my Max plan." Walk the tree: laptop off ⇒ not Tier 1 or 2; subscription ⇒ not Tier 4. That leaves Tier 3.

bashcopy
```bash
# in the CLI, create a scheduled Routine (then add triggers on the web if needed)
/schedule nightly at 02:00 — run /dep-audit on this repo and open a PR per outdated package

# the WRONG way for a Max subscriber (silently bills per-token API):
#   0 2 * * *  claude -p "/dep-audit"   ← cron + print mode = API path
```


**What happened:** the two lines do nearly the same work; the difference is which billing contract you land on. The surface *is* the cost decision.


Net answer to "is there anything I can't do without the API?" — **no, not for the high-value stuff.** Goal loops, interval loops, scheduled desktop tasks, and (currently) cloud Routines all run under a Max plan. The API path is only required when you decouple entirely: GitHub Actions on PR events, a bespoke Agent SDK harness, or `claude -p` from your own scheduler.

Try it · know your route
Run `/status` and read your account and route. Then run a trivial one-turn job two ways — once interactively, once with `claude -p "say hi"` — and check your subscription usage against the API console to see *which meter moved*. The cheapest insurance you'll buy this year.

Summary- Four surfaces, escalating in autonomy: in-session, desktop task, cloud Routine, headless/SDK/Actions.
- Machine-awake matters for Tiers 1–2; Routines run with the laptop off; only Tier 4 is the genuine per-token API path.
- `claude -p` can bill as API even on Max with no key set — verify with `/status` and a test run before automating.
- Nearly all loop value is covered by a subscription; reserve the API for fully-decoupled CI/SDK/cron.

Exercises 3- You want a loop triggered by every PR opened on GitHub, running even when no one is at a machine. Which surface, and which billing route?             Show solutionA GitHub-triggered **Routine** (web-configured trigger) or Claude Code GitHub Actions. A Routine currently draws from subscription; Actions is the per-token API path. Event triggers beyond a schedule are configured on the web, not the CLI.
- Why is reasoning about "dollars per run" from inside an interactive session misleading?             Show solutionA local dollar figure is an API-style per-token estimate; interactive subscription usage is metered against a window, not per token. Use `/status` for the route, the usage page for subscription, and the API console for token spend — they're different contracts.
- A teammate sets `ANTHROPIC_API_KEY` "to be safe" while on Max. What did that change?             Show solutionIt routes their usage to **API billing** regardless of surface — the opposite of "safe" for a subscriber. The key owns the bill; unset it to use the subscription, and confirm with `/status`.

 ===== CHAPTER 4 ===== Chapter 04 · Part II
## Ch 4 — Verification

The most consequential design choice in a loop is splitting the agent that writes from the agent that checks.

Learning objectives- Explain why a single model verifying itself is unreliable, and how separation fixes it.
- Define an independent checker subagent and gate a goal on its verdict.
- Choose a verification strategy with real teeth from a menu of options.
- Spot a check that verifies a *proxy* instead of the goal.


### 4.1 Why one model can't grade itself

A single instance suffers confirmation bias: it will happily declare its own work done and miss its own bugs. You saw one expression of this in `/goal` — the evaluator is a *different* model. At the orchestration level the same principle scales up: one subagent *makes*, a separate one *checks*.


*[Diagram: Figure 4.1 Maker drafts; an independent checker verifies; the checker's failures become the maker's next instructions.]*


### 4.2 What "real verification" means

A verifier is only worth something if it does what a skeptical human would. The strongest framing from the Claude Code team: let the agent *actually test what it's building as a user* — click the flow, hit the endpoint, render the page — not merely re-run the unit tests it also wrote. A checker that only replays the maker's own assertions inherits the maker's blind spots.

Gallery 4.1 Checks with teeth
"Verify it" can mean many things, and the strong ones share a property: they could fail even when the maker is convinced it's done. A menu, weakest-to-strongest:


##### Run the real suite

Execute tests independently and paste raw output — not a summary of it.

`run `pytest -q` yourself; paste the output`
##### Exercise as a user

Start the app and drive the actual path the feature claims to fix.

`start the server, POST to /refund, show the response + DB row`
##### Golden / snapshot diff

Compare output against a known-good fixture.

`diff output against fixtures/expected/*.json`
##### Property / fuzz

Assert invariants over generated inputs, not hand-picked cases.

`run the property tests with 1000 random cases`
##### Schema / contract

Validate the response against the API contract.

`validate responses against openapi.yaml`
##### Visual regression

Screenshot the page and diff against baseline.

`capture the checkout page; diff vs baseline.png`
##### Independent re-derivation

A second agent solves it differently and the two results are compared.

`second agent computes the total a different way; compare`
##### Necessary-not-sufficient gates

Lint/type/build must pass — but never as a stand-in for "correct."

`tsc + eslint clean as a floor, not the proof`
Reach for the strongest check the task can afford. The cheap ones (lint, type) are gates you keep; they are not evidence the feature works.

Worked Example 4.1 A checker subagent that trusts nothing
Define independent agents in `.claude/agents`. The checker's prompt forbids it from trusting the maker's claims and requires reproduced evidence.

markdown · .claude/agents/checker.mdcopy
```markdown
---
name: checker
description: Independently verifies a change. Trusts nothing it cannot reproduce.
---
You are a verification agent. You did not write this code and you assume it is wrong
until proven otherwise.

For the change under review:
1. Run the full test suite yourself and paste the raw output.
2. Exercise the feature as a user would (start the app, hit the route, render it)
   and describe what you observed.
3. Re-read the acceptance criteria and check each one explicitly.
4. Report PASS only if every criterion is demonstrably met in your own output;
   otherwise FAIL with the specific failing evidence.

Never report PASS based on the author's description. Confidence requires evidence.
```


**What happened:** "confidence requires evidence" is doing real work — it converts the checker from a rubber stamp into something that can actually return FAIL.

Worked Example 4.2 Gating a goal on the checker's verdict
Wrap the maker→checker exchange in a goal whose end state *is* the checker's PASS — now the loop can't terminate on the maker's say-so.

bashcopy
```bash
/goal the checker agent reports PASS, with pasted test output and a described
user-level run of the refund flow; if it reports FAIL, address the specific
reasons and re-run the checker; stop after 25 turns
```


**What happened:** the evaluator (transcript-only) reads the checker's pasted evidence, so the loop's stop signal is now grounded in an independent agent's reproduced output, not a self-assessment.

Worked Example 4.3 Two agents, explicitly separated
For higher-stakes work, run maker and checker as distinct invocations so neither shares the other's context or motivation.

bashcopy
```bash
# 1) maker implements
claude --agent=maker "implement partial refunds per docs/refunds.md"

# 2) checker verifies the working tree, told nothing about the maker's claims
claude --agent=checker
```


**What happened:** the checker forms its verdict from the artifact alone. If it passes something you'd reject, your checker prompt is too trusting — tighten the reproduce-evidence clause.

Pitfall · checking a proxy
The subtle failure is a checker that verifies something *near* the goal: "tests pass" when they don't cover the bug; "build green" when the feature is broken at runtime; "lint clean" as a stand-in for correct. Always ask: *if this check passes and the feature is still broken, what did the check miss?* Then add the check that would have caught it.

Try it · split the work
Take a small feature. Have a maker implement it, then run the checker agent above against the result *without* telling it the maker said it was done. Compare the checker's verdict to your own review.


The maker and the checker can each be a proper subagent file. Appendix A.4 gives complete, copy-paste subagent definitions — the independent `checker`, a read-only `planner`, and a `security-reviewer` — showing how the `tools:` field makes a restriction structural rather than a polite request.

Summary- A model grading itself converges on "looks done," not "is done"; an independent checker is what bounds a loop's autonomy.
- Real verification exercises the product as a user — unit replays inherit the maker's blind spots.
- Gate the goal on the checker's PASS so the loop can't stop on the maker's self-assessment.
- Watch for proxy checks; for every escape, add the check that would have caught it.

Exercises 4- Why is "a separate evaluator/checker" called the most consequential design choice in a loop?             Show solutionA loop's autonomy is bounded entirely by the trustworthiness of its stop signal. A maker grading itself decouples confidence from correctness, yielding fast, confident wrongness; an independent checker re-couples them.
- Your checker passes but production breaks. Most likely structural flaw, and the one-time fix?             Show solutionThe checker verifies a proxy (its own/the maker's tests) not user-observable behaviour. Fix structurally: add a check that exercises the real path (integration/E2E) whose output appears in the transcript, and bake it into the goal so it gates every future run.
- Give a task where "independent re-derivation" is the right verification strategy, and say why a single suite wouldn't catch the error.             Show solutionA financial calculation (e.g., proration). A second agent computing the figure by a different method catches logic errors that a test suite written by the maker would encode the same way — the suite and the code share the maker's misunderstanding; the re-derivation doesn't.

 ===== CHAPTER 5 ===== Chapter 05 · Part II
## Ch 5 — Loop bodies as skills

The `/babysit` in `/loop 5m /babysit` is a file you wrote. Here's how to write it.

Learning objectives- Separate a loop's cadence from its body, and author the body as a reusable slash command.
- Apply the assess → act → verify → repeat/stop template, with arguments.
- Promote a loop from session to desktop task to Routine as it proves out.
- Draw on a library of body patterns for common chores.


### 5.1 Cadence and body are different concerns

A loop has a *cadence* (the `/loop` or schedule) and a *body* (what runs each cycle). The body is a markdown file in `.claude/commands/` whose name becomes the command (in the modern, recommended form, a `SKILL.md` file in `.claude/skills/`; see §5.3). The maintainer's advice is explicit: turn workflows into skills, then drive them with loops. That separation is what makes loops composable instead of one-off prompts.

Worked Example 5.1 The cycle template
Most loop bodies share a shape. Encode it once; `$ARGUMENTS` receives whatever you pass after the command name.

markdown · .claude/commands/iterate.mdcopy
```markdown
---
description: Drive a task to completion with explicit verification each cycle.
---
Your task is: $ARGUMENTS

Follow this cycle:
1. Assess the current state against the objective. State what is and isn't done.
2. Identify the single next action that makes the most progress.
3. Execute that action.
4. Verify by running the relevant command and showing its output.
5. If the objective is complete, summarise what changed and STOP.
6. If not, return to step 1.

Do not stop between cycles unless you hit a genuine blocker needing a human.
After 20 cycles without completion, stop and summarise progress.
Confidence requires evidence: never claim a step succeeded without showing proof.
```


**What happened:** the same body now powers many loops — `/iterate make src/lib lint-clean`, `/iterate backfill docstrings in src/api`, `/loop 30m /iterate triage feedback/`. One file, reused everywhere.

Gallery 5.1 A library of loop bodies
Bodies worth writing once and keeping in `.claude/commands/`. Each is a small, named, version-controlled unit of work you can drive interactively, on a clock, or on a schedule:


##### /iterate

Generic assess-act-verify loop for any bounded task.

`/iterate <objective>`
##### /fix-flaky

Reproduce, hypothesise, fix, and re-run a flaky test to stability.

`/fix-flaky test/checkout/*`
##### /babysit

Rebase, address review comments, fix CI on your open PRs.

`/loop 5m /babysit`
##### /sec-sweep

Run scanners, cluster findings, open a PR per cluster.

`/sec-sweep`
##### /doc-backfill

Document the next undocumented public symbol, verify doc-lint.

`/doc-backfill src/api`
##### /triage

Turn new feedback or issues into labelled, summarised tickets.

`/loop 30m /triage feedback/`
##### /release-notes

Draft notes from merged PRs since the last tag.

`/release-notes since v2.4.0`
##### /upgrade-dep

Bump one dependency, fix breakages, run the suite, open a PR.

`/upgrade-dep react 19`
A body is just a prompt with structure — but because it's a file, it's reusable, reviewable, and improvable, and every loop that uses it gets better when you refine it.

Worked Example 5.2 A purpose-built body: stabilise a flaky testmarkdown · .claude/commands/fix-flaky.mdcopy
```markdown
---
description: Stabilise a flaky test by reproducing, root-causing, and verifying.
---
Target: $ARGUMENTS

1. Run the target 20 times in a loop. Record pass/fail counts.
2. If deterministic-pass, report STABLE and stop.
3. Otherwise form ONE hypothesis for the nondeterminism (timing, shared state,
   ordering, external dependency). State it explicitly.
4. Apply the minimal fix for that hypothesis only.
5. Re-run 20 times. If still flaky, revert and try the next hypothesis.
6. Stop when 20/20 pass on two consecutive runs, or after 8 hypotheses.
```


**What happened:** the body encodes a *method*, not just a goal — one hypothesis at a time, revert-on-failure — which is exactly the discipline a human debugger applies and an unguided agent often skips.

Worked Example 5.3 A generative body: release notesmarkdown · .claude/commands/release-notes.mdcopy
```markdown
---
description: Draft release notes from merged PRs since a tag.
---
Since: $ARGUMENTS

1. List merged PRs since the given tag with their titles and labels.
2. Group them into Features / Fixes / Internal by label, dropping noise.
3. Write one user-facing line per item — what changed for the user, not the diff.
4. Output as markdown under a "## $ARGUMENTS → HEAD" heading. Do not invent
   changes not present in the PR list.
```


**What happened:** the "user-facing line, not the diff" instruction and the "don't invent" constraint are what separate useful notes from a regurgitated changelog.


### 5.2 The promotion path

Don't reach for the cloud first. Prototype the body and cadence in a session, promote what works to a desktop task for daily use, then to a Routine when it must run independent of your terminal. This is the natural maturity curve of every loop.


*[Diagram: Figure 5.1 Session → desktop task → Routine: promote loops as they prove out.]*

Pitfall · bodies without a stop condition
A body that says "keep going" with no completion clause and no cycle ceiling is how a loop runs away. Every body needs an explicit STOP *and* a cap. Over-broad `$ARGUMENTS` ("fix the codebase") inherits all the problems of a vague goal — keep each invocation's scope tight.

Try it · build one reusable body
Write `.claude/commands/iterate.md` from Example 5.1. Run it once interactively on a small task, then again under `/loop`. You've converted a prompt you used to retype into a first-class, schedulable unit of work.


### 5.3 The modern form: SKILL.md

Everything above used the command form, `.claude/commands/<name>.md`, which still works. But as of Claude Code v2.1.101 commands and skills are **merged**, and the recommended form is a **`SKILL.md`** file in its own folder under `.claude/skills/`. The folder name becomes the command, the `description` lets Claude reach for the skill on its own, and the frontmatter adds controls a plain command never had.

Worked Example 5.4 The same body, as a skill
Here is the `/iterate` body from Example 5.1 in the modern format. Note what is new: a folder, a triggering `description`, and scoped `allowed-tools`.

markdown · .claude/skills/iterate/SKILL.mdcopy
```markdown
---
description: Drive a task to completion with explicit verification each cycle. Use
  when asked to iterate on, finish, or repeatedly fix something until it is done.
allowed-tools: Read, Edit, Bash
---
Your task is: $ARGUMENTS

1. Assess the current state against the objective. State what is and isn't done.
2. Identify the single next action that makes the most progress.
3. Execute it, then verify by running the relevant command and showing its output.
4. If the objective is complete, summarise what changed and STOP.
5. Otherwise return to step 1. After 20 cycles without completion, stop and summarise.
Confidence requires evidence: never claim a step succeeded without showing proof.
```


**What happened:** the body is identical; only the wrapper changed. You still call it with `/iterate` and drive it with `/loop 30m /iterate <task>` — but now Claude can also invoke it automatically when your request matches the description, and the toolset is scoped. Appendix A.3 is a full library of `SKILL.md` files, including background-knowledge, side-effecting, and forked-subagent skills.

Summary- A loop's body is a reusable slash command in `.claude/commands/`; cadence and body are independent.
- The assess→act→verify→repeat/stop template, plus `$ARGUMENTS`, covers most bounded work.
- Promote loops session → desktop task → Routine as they prove out; don't start in the cloud.
- Every body needs an explicit stop and a cap, and a tight per-invocation scope.

Exercises 5- Why encode the cycle in a command file rather than retyping the prompt each time?             Show solutionA command file is versioned, reusable, and composable: drivable by `/loop`, a desktop task, or a Routine without change; it travels with the repo; and refining it improves every loop that uses it.
- Write a one-paragraph `/upgrade-dep` body. Which two safety clauses must it contain?             Show solutionIt should bump the named dep, fix breakages, run the suite, and open a PR — with (i) an explicit STOP ("stop when the suite passes and a PR is open, or after N turns") and (ii) a constraint against masking failures ("do not skip or delete failing tests to make the suite pass").
- You point `/loop 10m /iterate fix the codebase` at your repo overnight. Predict the failure and name the two fixes.             Show solutionIt runs away: the scope is unbounded so it never "completes," and the clock keeps firing. Fixes: (i) tighten `$ARGUMENTS` to a specific, verifiable objective; (ii) ensure the body's cap and STOP actually trigger — and for an overnight job, prefer a goal-bounded body over a bare interval loop.

 ===== CHAPTER 6 ===== Chapter 06 · Part II
## Ch 6 — Parallelism & /batch

Many agents in one repo is chaos without isolation — the same chaos as two engineers editing one file. Worktrees fix it; `/batch` scales it.

Learning objectives- Run agents in parallel with isolated git worktrees, and say exactly what isolation prevents.
- Use `/batch` to fan one task across many worktree agents.
- Recognise the breadth of work `/batch` unlocks — and the cost it multiplies.
- Get isolation when you're not on git.


### 6.1 Each agent needs its own checkout

To run loops in parallel, each agent must have its own working copy. Git worktrees give you exactly that, and Claude Code has first-class support. A maintainer runs "dozens of Claudes at all times" this way; the isolation is what stops them overwriting each other mid-run.

bashcopy
```bash
# start a session in a fresh worktree
claude -w

# in the desktop app: tick the "worktree" checkbox when starting a session

# let a subagent run in its own checkout that cleans itself up afterwards:
#   (subagent config)  isolation: worktree
```

yaml · subagent with worktree isolationcopy
```yaml
name: migrator
description: Performs one slice of a large migration in an isolated checkout.
isolation: worktree   # spawns a clean git checkout, tears it down after the run
```


*[Diagram: Figure 6.1 Each agent gets an isolated worktree; work converges as branches and PRs.]*


### 6.2 Fan-out with /batch

For large, parallelisable work, `/batch` interviews you about the task, then fans it out across as many worktree agents as it takes — dozens, hundreds, even thousands. It is built for migrations and other embarrassingly parallel jobs, where the same operation repeats over many independent units.

Gallery 6.1`/batch` in the wild
The pattern is always "the same operation, once per unit, in its own checkout, as a PR." The unit can be a component, a file, a package, an endpoint — or a whole repository. Twelve to steal from:


##### API / component migration

Move every component off a deprecated API — the canonical case.

`/batch migrate each component from the old Button API to the new, one per worktree, PR each`
##### Test backfill at scale

Write missing tests for every file under the coverage line.

`/batch add unit tests for each file in src/ below 60% coverage, one file per agent`
##### JS → TS conversion

Convert each module to TypeScript and fix the types it surfaces.

`/batch convert each module in src/legacy to TypeScript, one module per agent`
##### i18n string extraction

Pull hardcoded UI strings into translation keys, view by view.

`/batch extract hardcoded strings to i18n keys in each view, one view per agent`
##### Dependency major bump

Upgrade each package in a monorepo and fix the fallout.

`/batch bump each package to React 19 and fix breakages, one package per agent`
##### Multi-repo policy change

Apply one change across many repositories — a different axis entirely.

`/batch add the SPDX licence header and update the CI workflow in each repo, one repo per agent`
##### Endpoint scaffolding

Generate route + handler + test for every endpoint in a spec.

`/batch scaffold a route, handler, and test for each endpoint in openapi.yaml, one per agent`
##### Docs generation

Write a README and docstrings for every package.

`/batch write a README and docstrings for each package, one package per agent`
##### Security remediation fan-out

One agent per finding drafts the fix and opens a PR.

`/batch for each finding in scan-report.json, draft the fix and open a PR, one per agent`
##### Accessibility sweep

Audit and fix a11y issues component by component.

`/batch fix axe-core violations in each component, one component per agent`
##### Performance pass

Profile each route and propose one optimisation, with numbers.

`/batch profile each route and propose one optimisation with before/after numbers, one route per agent`
##### Dead-code & dup removal

Remove unused exports and unify duplicated helpers, per module.

`/batch remove dead code and unify duplicate helpers in each module, one module per agent`
More of the same shape: roll out a new strict ESLint rule one directory at a time; migrate each test fixture to a new schema; check each docs page for link rot; or run a codemod per package and have each agent verify the build after. If your task is "do X to every Y," it's a `/batch`.

Worked Example 6.1 The canonical migration (one component per agent)
The classic fan-out: a repetitive, independent change across many files, each landing as its own reviewable PR.

bashcopy
```bash
/batch migrate every component from the old Button API to the new one,
one component per worktree agent. Each agent: update the component, update its
tests, run `npm test` for that component, and open a PR titled "[btn] <component>".
Do not change shared components used by others.
```


**What happened:** the "don't change shared components" constraint keeps parallel agents from racing on the same file — isolation handles the working tree, but the instruction handles logical overlap.

Worked Example 6.2 Test backfill, coverage-gated (one file per agent)
Here each agent's work has its own verifiable bar, so the fan-out doubles as a quality gate.

bashcopy
```bash
/batch for each file in src/ currently below 60% line coverage, one agent per file:
write meaningful unit tests (not trivial assertions), raise that file to >= 80%
coverage shown by the coverage report, keep the suite green, and open a PR.
Skip files that are pure type declarations.
```


**What happened:** "meaningful, not trivial" plus a coverage *number* each agent must show is what stops the fleet from gaming coverage with empty tests — the per-agent goal carries the same anti-proxy discipline as Chapter 4.

Worked Example 6.3 A cross-repo change (one repo per agent)
The unit of fan-out doesn't have to be a file — it can be a whole repository, which is how org-wide policy changes get done in an afternoon.

bashcopy
```bash
/batch across these 14 service repos, one agent per repo: replace the deprecated
`@acme/auth` import with `@acme/identity`, update the call sites, run the repo's
test suite, and open a PR. If a repo doesn't use the import, report "no change".
```


**What happened:** the "no change" reporting path matters at fan-out scale — without it you can't tell "done, nothing to do" from "silently skipped," and across 14 repos that ambiguity is where bugs hide.

Mechanism · isolation without git
If you're not on git, you can still get isolation by supplying your own checkout logic with a `WorktreeCreate` hook (Chapter 7). The parallelism model doesn't depend on git specifically — it depends on each agent having a private working copy.

Pitfall · isolation is not optional, and fan-out multiplies cost
Omitting worktree isolation when multiple agents touch one repo doesn't merely cause merge conflicts — it creates unpredictable state where agents overwrite each other's changes mid-execution, against a half-applied tree. And breadth is multiplicative: a thousand agents is a thousand token streams *and* a thousand PRs that still need review. Bound the fan-out, and sample the output for quality drift before trusting the whole batch.

Try it · two agents, no collisions
Pick two independent tasks in one repo. Start two sessions with `claude -w` (or two worktree-checkbox sessions in desktop). Run a task in each simultaneously and confirm neither stomps the other's files. Open both as separate branches — you've just parallelised yourself.

Beyond worktrees · agent teams
Worktrees give you many *independent* agents that you merge yourself. When the parallel work needs to *coordinate* — teammates claiming tasks from a shared list and messaging each other — Claude Code's experimental **agent teams** take it further: a lead session spawns named teammates that share a task list and a mailbox. See Appendix A.6 for how to enable it, a real spawn prompt, and the team-specific hooks.

Summary- Parallel agents need isolated checkouts; git worktrees (`claude -w`, `isolation: worktree`, the desktop checkbox) provide them.
- `/batch` fans "do X to every Y" across many worktree agents, each producing a PR — migrations, sweeps, generation, and cross-repo changes.
- The fan-out unit can be a file, package, endpoint, or whole repo; a "no change" path is essential at scale.
- Isolation prevents mid-run overwrites, not just merge conflicts; bound the breadth because cost and review load scale with it.

Exercises 6- Concretely, what goes wrong without worktree isolation when two agents edit the same package in parallel?             Show solutionThey share one working tree, so edits interleave: one agent's write clobbers another's mid-run, tests run against a half-applied mixture, and you get nondeterministic, irreproducible state — not even a clean merge conflict you could resolve.
- You fan a migration out to 200 agents with `/batch`. Name two costs you must bound and how.             Show solution(i) Token spend — 200 concurrent streams; bound by limiting batch size or running in waves. (ii) Review load and quality drift — 200 PRs each need a human gate; bound by sampling a subset for quality before merging the rest and by tightening the per-agent goal.
- Turn one of your real chores into a `/batch` command. What's the unit, the per-unit verification, and the "nothing to do" path?             Show solutionAnswers vary, but a good one names all three — e.g. unit = "each GraphQL resolver," verification = "the resolver's tests pass and the schema still validates," nothing-to-do = "report 'already migrated' rather than opening an empty PR." If you can't name the unit and its check, it's not ready to fan out.

 ===== CHAPTER 7 ===== Chapter 07 · Part II
## Ch 7 — Hooks & the lifecycle

Hooks run deterministic logic at fixed points in an agent's life — your guardrails, not the model's whims.

Learning objectives- Name the lifecycle events you can hook and what each is for.
- Write hooks to load context, audit actions, gate permissions, and control stopping.
- Explain how `/goal` is itself a Stop hook, and when to write your own.
- Avoid hooks that fail silently or strangle legitimate work.


### 7.1 Where you stop trusting and start enforcing

Everything so far trusts the model to behave. Hooks are where you stop trusting and start enforcing. They fire at lifecycle events and run your code — shell commands or prompts — to load context, log actions, gate permissions, or keep the agent going. `/goal` itself is built on one of them.


*[Diagram: Figure 7.1 The lifecycle events you can hook, and the loop that Stop closes.]*

Gallery 7.1 What each hook is for
Four events, many uses. The same hook type does context-loading, governance, or flow-control depending on what you put in it:


##### SessionStart · load standards

Inject conventions and the active ticket every session.

`echo coding standards + current ticket into context`
##### SessionStart · set env

Export the URLs and flags the agent will need.

`export STAGING_DB_URL and feature flags`
##### PreToolUse · audit log

Record every shell command with a timestamp.

`append each Bash command to .claude/audit.log`
##### PreToolUse · deny dangerous

Block destructive or prod-touching commands outright.

`block rm -rf, force-push, anything matching *prod*`
##### PreToolUse · auto-format

Run the formatter on each file the agent writes.

`run prettier on every Edit/Write target`
##### PermissionRequest · route to chat

Send approvals to a human out-of-band.

`post approval requests to #claude-approvals`
##### PermissionRequest · auto-allow safe

Approve reads and tests; require humans for the rest.

`auto-allow Read + test commands`
##### Stop · keep going until green

Refuse to finish while the suite is red.

`block stop while `npm test` fails`
##### Stop · block on uncommitted

Don't let a run end with a dirty tree.

`block stop if `git status` is not clean`
Notice the same `PreToolUse` event covers logging, blocking, and formatting; the hook type is the *when*, your command is the *what*.

Worked Example 7.1 Audit every command the agent runs
This single hook is also a governance primitive (Chapter 12): a complete, timestamped record of every shell action an autonomous agent took.

json · .claude/settings.jsoncopy
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command",
            "command": "jq -r '\"\\(now|todate) \\(.tool_input.command)\"' >> .claude/audit.log" }
        ]
      }
    ]
  }
}
```


**What happened:** the hook reads the tool input as JSON and appends a timestamped line — turning "the agent did something" into "here is exactly what the agent did, and when."

Worked Example 7.2 Deny dangerous commands deterministically
Some things shouldn't depend on the model's judgement at all. A `PreToolUse` matcher can hard-block them.

json · settings.json — block before the command runscopy
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command",
            "command": "grep -Eq 'rm -rf|git push --force|kubectl .*prod' <<< \"$CLAUDE_TOOL_INPUT\" && echo '{\"decision\":\"deny\",\"reason\":\"blocked dangerous command\"}' || true" }
        ]
      }
    ]
  }
}
```


**What happened:** the deny is deterministic — it fires regardless of how the agent rationalised the command, which is the whole point of a guardrail versus a prompt.

Worked Example 7.3 A custom Stop hook that runs a real check
When `/goal`'s transcript-only evaluation isn't enough, write a Stop hook that *runs a command* before allowing the agent to finish.

json · settings.json — keep going until tests passcopy
```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          { "type": "command",
            "command": "npm test --silent >/dev/null 2>&1 || echo '{\"decision\":\"block\",\"reason\":\"tests still failing — keep going\"}'" }
        ]
      }
    ]
  }
}
```


**What happened:** unlike the `/goal` evaluator, this hook executes the suite and inspects the real exit code — the right tool when "done" must be decided by running something, not by reading the transcript.

Mechanism · `/goal` is a Stop hook
`/goal` is a session-scoped, prompt-based Stop hook with a fixed shape: on each stop, the condition plus transcript go to the small fast model, which returns block ("no, here's why") or allow ("yes"). Knowing this tells you when to drop a level: if your check must *run a command* rather than read the transcript, write your own command-type Stop hook (Example 7.3) instead of relying on `/goal`.

Pitfall · hooks that fail silently or over-block
A hook that errors can wedge the agent or, worse, silently let unsafe actions through. Make blocking hooks explicit about *why* they blocked — the reason is fed back to the agent — and test the failure path. An over-eager deny-list can also strangle legitimate work; scope matchers tightly.

Try it · add an audit trail
Drop the `PreToolUse` audit hook into `.claude/settings.json`, run any task that shells out, and inspect `.claude/audit.log`. You now have a reviewable record of agent actions — the foundation of Chapter 12.


Two more broadly useful hooks — loading standing context at `SessionStart` and formatting every file on `PostToolUse` — are in Appendix A.5. Agent teams add their own lifecycle hooks (`TeammateIdle`, `TaskCreated`, `TaskCompleted`) for governing a fleet; see Appendix A.6.

Summary- Hooks fire deterministic logic at lifecycle events: SessionStart, PreToolUse, PermissionRequest, Stop.
- The same event serves context-loading, governance, or flow-control depending on the command you attach.
- `/goal` is a prompt-based Stop hook; write a command-type Stop hook when completion must be decided by running something.
- Make blocks explain themselves and scope matchers tightly, or hooks become their own failure mode.

Exercises 7- How does `/goal` relate to the Stop hook, and when would you write your own instead?             Show solution`/goal`*is* a prompt-based Stop hook that judges the transcript. Write your own when completion must be decided by running a command (tests, build, a script) and inspecting real exit codes rather than reading what's printed.
- Which hook turns autonomy from a liability into something an auditor can accept, and why?             Show solutionA `PreToolUse` audit hook: it produces a complete, timestamped, tamper-evident record of every action, converting "trust the agent" into "here is the traceable log" — exactly what change-management review demands.
- Your deny-list Stop/PreToolUse hook starts blocking valid commands and the agent stalls. Diagnose and fix.             Show solutionThe matcher or pattern is too broad (e.g., blocking all `git push` rather than `--force`). Narrow the regex/matcher, and ensure the block emits a clear reason so the agent can adapt rather than silently stall. Test both the allow and deny paths.

 ===== CHAPTER 8 ===== Chapter 08 · Part II
## Ch 8 — Memory & state

A loop that forgets repeats its mistakes forever. Persistence is what makes cycles compound.

Learning objectives- Use `CLAUDE.md` to propagate lessons and conventions across every session.
- Make a long loop resumable with an explicit state file.
- Apply context minimalism — and load context explicitly for non-interactive runs.
- Know the range of things worth recording in project memory.


### 8.1 Bridging sessions that don't share context

Loops run across sessions, and sessions don't share context by default. Two mechanisms bridge the gap: `CLAUDE.md` for durable lessons and conventions, and explicit state files for resumable progress.


*[Diagram: Figure 8.1 Lessons propagate through CLAUDE.md; progress resumes through state files.]*


### 8.2 CLAUDE.md, the propagating memory

`CLAUDE.md` is a project-level file Claude Code reads automatically at the start of every session. The maintainer's rule: when the agent makes a repeated mistake, don't just correct it in chat — have it *write the lesson into `CLAUDE.md`*, so the correction propagates to every future session and every parallel agent instead of dying with that conversation.

Gallery 8.1 What belongs in `CLAUDE.md`
More than a style guide — it's the standing context every agent inherits. The useful categories:


##### Conventions

The non-negotiables of how this codebase is written.

`"UTC everywhere; structured logger; no default exports"`
##### Lessons (append-only)

Rules earned from past mistakes; agents add here when corrected.

`"never edit supabase/migrations directly — generate a new one"`
##### Architecture map

Where the major modules live and how they talk.

`"auth in packages/identity; billing reads it via the gateway"`
##### Do-not-touch list

Generated, vendored, or legacy code agents must leave alone.

`"never modify gen/, vendor/, or the legacy/ tree"`
##### Runbook

How to actually run the app, the tests, the smoke suite.

`"dev: pnpm dev (needs Redis); e2e needs a seeded DB"`
##### Domain glossary

What ambiguous terms mean *here*.

`"'binder' = a bound quote, not a file; 'broker' = our customer"`
##### Real commands

The exact test/lint/build invocations, so agents don't guess.

`"test: pnpm test; lint: pnpm lint; build: pnpm build"`
##### Known gotchas

The traps that waste a fresh agent's first ten minutes.

`"the dev server fails silently without env from .env.local"`
Keep it curated, not exhaustive — see the context-minimalism note below. A bloated `CLAUDE.md` is itself a problem.

Worked Example 8.1 Make a correction stick
After the agent gets something wrong, don't just fix it — have it record the rule so the next session inherits it.

markdown · CLAUDE.md (excerpt)copy
```markdown
#### *Example: Lessons log (append-only)*
- Never edit files under `supabase/migrations/` directly — generate a new migration.
- `npm test` must pass before any commit; if flaky, run `npm run test:retry` and quote the result.
- Dates are UTC everywhere; never construct local Date objects in `src/billing`.
```

bash · the instruction that writes itcopy
```bash
append a one-line lesson to the "## Lessons" section of CLAUDE.md describing
the mistake just made and the rule that prevents it, then continue
```


**What happened:** the fix outlives the conversation. Start a fresh session and the agent already respects the rule it wrote — a correction became a permanent capability.

Worked Example 8.2 A resumable loop with a state file
A long loop should write its own progress so tomorrow's run resumes where today's stopped — the difference between a loop and a script that restarts from scratch.

markdown · loop body pattern with statecopy
```markdown
1. Read .loop-state.json. If absent, initialise it with the full work queue.
2. Take the next unprocessed item. Do the work. Verify it.
3. Mark the item done in .loop-state.json with a timestamp and the result.
4. If the queue is empty, report COMPLETE and stop. Otherwise continue.
```


**What happened:** the state file gives the loop memory of its own progress, so a nightly job chips away at a thousand-item queue over a week instead of re-starting each run.

Worked Example 8.3 Load context explicitly for headless runs
Non-interactive runs (`-p`, the SDK) scan local `CLAUDE.md`, settings, and MCPs by default. When you want tight, predictable context instead, load only what the task needs.

bashcopy
```bash
# default headless run picks up the local CLAUDE.md / settings / MCPs
claude -p "/iterate make src/lib lint-clean"

# --bare: don't auto-load; you supply exactly the context the task needs
claude --bare -p "fix the failing test in test/refund.spec.ts; here is the file: ..."
```


**What happened:**`--bare` trades convenience for control — useful when the ambient context would bloat the run or pull in rules irrelevant to a narrow task.

Mechanism · context minimalism
More context is not better. The maintainer keeps context "lean enough that the model can still think." A bloated context degrades reasoning and inflates cost, and it compounds in a loop because every cycle re-sends it. Curate `CLAUDE.md`, and for non-interactive runs prefer loading exactly what's needed over dragging everything in.

Pitfall · lessons that never get written back
If your loop corrects the agent in conversation but never updates `CLAUDE.md`, the next cycle repeats the mistake — you've built a goldfish. Make "record the lesson" an explicit step in any body that runs unattended.

Try it · teach the agent once
Trigger a known mistake (the agent touches a file it shouldn't). Correct it and have it append the rule to `CLAUDE.md`. Start a fresh session, attempt the same task, and confirm the agent now respects the rule it wrote.

Summary- `CLAUDE.md` is read at every session start; write lessons back so corrections propagate to all future and parallel runs.
- State files make long loops resumable — each cycle continues from recorded progress instead of restarting.
- Keep context lean; for headless runs, load context explicitly (`--bare`) when the ambient default would bloat or mislead.
- An unattended body that never records lessons is a goldfish; make recording an explicit step.

Exercises 8- Why does writing a lesson to `CLAUDE.md` beat correcting the agent in-session?             Show solutionAn in-session correction is local to one conversation and evaporates when it ends; a `CLAUDE.md` entry is read at every future SessionStart, so the fix reaches all subsequent runs and all parallel agents.
- What distinguishes a loop with a state file from a script that re-runs on a schedule?             Show solutionThe state file gives the loop memory of its own progress: each cycle resumes from recorded state and builds on it (compounding), whereas a stateless scheduled script restarts from zero and can re-do or skip work.
- When is `--bare` the right call, and what do you give up?             Show solutionWhen a narrow headless task would otherwise pull in a large ambient context (bloated `CLAUDE.md`, irrelevant MCPs) that degrades reasoning or inflates cost. You give up the convenience of auto-loaded conventions — so you must supply exactly the context the task needs.

 ===== CHAPTER 9 ===== Chapter 09 · Part II
## Ch 9 — Self-improving loops

A loop that edits its own instructions to do better next time — and how to keep that from quietly turning into self-corruption.

Learning objectives- Explain the mechanism that lets a loop improve across runs, given that the model's weights never change.
- Choose where an improvement should persist: `CLAUDE.md`, the skill body, or a sidecar heuristics file.
- Write a self-amending command that appends a generalised lesson each run.
- Add a fitness function so a self-edit is kept only when a measured score improves.
- Recognise wrong-lesson lock-in, bloat, and reward hacking — and guard against them.


### 9.1 Persistence plus reflection — the whole trick

"The loop adjusts itself to be better next time" sounds like the model is learning between runs. It isn't — the weights are frozen and identical on every call. What changes is the *instructions the model reads at the start of the next run*. Any text the agent writes to a file that gets re-read next run becomes part of that run's prompt. So a self-improving loop is just an ordinary loop with one extra step: at the end, reflect on how the run went and write a *generalised* lesson to a file the next run will read.


The improvement is durable for one reason — it lives on disk, not in the volatile context that's discarded when the run ends. That's the entire mechanism. Two files get re-read automatically: `CLAUDE.md` (every session, Chapter 8) and a command or skill body (whenever that command runs). Write to either and the next run starts smarter.

Mechanism · this has a name
In the literature it's *Reflexion* and *Self-Refine*: an agent critiques its own output and feeds the critique back as input. The practitioner version is the rule from Chapter 8 — when the agent makes a repeated mistake, have it write the lesson into `CLAUDE.md` rather than correcting it in chat. A self-improving loop generalises that: reflection becomes a standing step, not a one-off correction. The compounding loops in Chapter 13 are the same idea pointed at the *codebase*; here it's pointed at the loop's own instructions.


*[Diagram: Figure 9.1 The improvement survives because it's written to a re-read file — not because the model remembers anything.]*


### 9.2 Where the improvement should persist

You have three places to write a lesson, trading breadth against blast radius.

| Target | What it improves | Scope | Main risk |
| --- | --- | --- | --- |
| CLAUDE.md | shared conventions & lessons | every loop in the repo | coarse; bloats; one bad rule affects everything |
| the skill / command body | the loop's own playbook | that one task | most directly "self-improving" — and can corrupt the playbook it runs on |
| a sidecar heuristics file | accumulated run learning | that one loop | lowest; the body stays stable and the file is easy to cap, curate, or reset |

Default to the **sidecar file** (the body reads it first, appends to it last), and promote a lesson to `CLAUDE.md` only when it's genuinely cross-cutting. Edit the body itself only with the tight guards in Worked Example 9.2 — a file that rewrites the very instructions it's executing is the easiest one to wreck.

Gallery 9.1 What a loop can learn to improve
The lessons worth keeping are *general and reusable* — a rule for next time, never "I fixed file X." A spread of the kinds of thing a loop teaches itself:


##### Project gotchas

Environment quirks that wasted the first ten minutes.

`"the dev server needs Redis running before tests"`
##### Faster root-cause paths

Where the real cause usually hides for a class of bug.

`"for flaky checkout tests, check shared fixtures first"`
##### Sharper test patterns

A stronger assertion the loop now knows to write.

`"assert on the response body, not just the status code"`
##### Tightening its own checks

A gap its verification missed last run.

`"the lint gate misses unused exports — run knip too"`
##### Codebase navigation

Where things live, so it stops re-discovering them.

`"auth lives in packages/identity, not src/auth"`
##### Dead ends to avoid

An approach that reliably fails here.

`"don't codemod migrations by hand — generate them"`
Each is one line a run could append to its heuristics file. Notice none of them name a specific fix — generality is what makes a lesson worth re-reading.


### 9.3 A self-amending command

The minimal self-improving loop adds two bookends to any body: read the heuristics first, append one general rule last.

Worked Example 9.1`/iterate` that teaches itself, via a sidecar file
The body reads `.claude/heuristics.md` at step 0 and writes back at the final step. The body itself never changes — only the sidecar grows — which keeps the loop stable and the learning easy to audit.

markdown · .claude/commands/iterate.mdcopy
```markdown
---
description: Iterate to completion, then teach yourself one general lesson.
---
Task: $ARGUMENTS

0. Read .claude/heuristics.md if it exists and follow every rule in it.
1. Assess -> act -> verify each cycle: run the relevant check and show its output.
   Stop when the objective is met, or after 20 cycles.
2. Reflection (one step, only after finishing): what cost time or caused a wrong
   turn THIS run? Append ONE general, reusable rule that prevents it to the
   "## Heuristics" section of .claude/heuristics.md. One line. A rule for next
   time, not "I fixed file X." Keep existing rules unless one is now wrong.
```


**What happened:** the "one general rule, not 'I fixed file X'" instruction is load-bearing. Without it the file fills with run-specific noise that helps nobody; with it, the loop accumulates transferable judgement.

Worked Example 9.2 A skill that edits its own body (the direct, riskier form)
If you want the loop to rewrite its *own* playbook, fence the self-editable region with a marker and forbid edits anywhere else. The agent may only touch lines under `## Learned heuristics`.

markdown · .claude/commands/migrate.mdcopy
```markdown
---
description: Self-amending migration playbook. Improves THIS file each run.
---
Task: $ARGUMENTS

Apply the steps under "## Playbook". Then reflect once: if you learned a general
improvement, edit THIS file by adding or revising exactly ONE line under the
"## Learned heuristics" marker. Never modify anything above that marker. Keep
existing heuristics unless one is now demonstrably wrong.

#### *Example: Playbook structure*
1. ... your stable migration steps ...

#### *Example: Learned heuristics*
- (the loop appends its own one-line rules below this marker)
```


**What happened:** the marker turns "the agent can edit its instructions" from a foot-gun into a bounded operation. The stable playbook is protected; only the append-only region evolves.


### 9.4 The strong version: a fitness function

Reflection alone drifts. With no objective signal, a loop can "learn" a wrong lesson from a fluky run and confidently bake it in — and self-improving quietly becomes self-corrupting. The fix that converts drift into actual hill-climbing is a **fitness function**: a number that scores a run. Keep a self-edit only when the score improves; otherwise revert it.


Anything measurable works as the score — coverage percentage, test pass rate, an eval suite's pass count, time-to-green, a benchmark figure. The rule is the same: a candidate heuristic is an experiment, and you keep it only if the metric moved the right way.

Worked Example 9.3 Keep the edit only if the score went up
This body makes self-improvement an accept/reject experiment — the loop proposes a heuristic, measures, and keeps it only on improvement.

markdown · .claude/commands/improve.mdcopy
```markdown
---
description: Improve a heuristic only if it raises the score. Hill-climb, don't drift.
---
Task: $ARGUMENTS          # e.g. "raise line coverage on src/billing"

1. Baseline: run the scorer and record the number (e.g. `pytest-cov` total %).
   Do NOT modify the scorer, the tests, or the metric definition.
2. Propose exactly ONE candidate rule and append it to .claude/heuristics.md.
3. Run the task using the new rule. Run the scorer again and record the number.
4. If the new score is higher, keep the rule. If it is equal or lower, delete
   that line and report the experiment as rejected.
5. Report: old score, new score, kept or reverted.
```


**What happened:** step 4 is the difference between learning and accumulating. The loop now climbs a measurable gradient instead of trusting its own narration that a change "felt better."

Mechanism · this is hill-climbing
Fitness-gated self-improvement is ordinary hill-climbing (or, across many candidates, evolutionary selection): propose a mutation, evaluate against a fixed fitness function, keep it only if it scores higher. The score is the entire reason it converges on *better* rather than merely *different*. Without it, you have mutation with no selection — which is just drift wearing a lab coat.


### 9.5 When self-improvement becomes self-corruption

This pattern fails in specific, predictable ways. Each has a guard, and most of the guards are lessons from earlier chapters.

| Failure | What happens | Guard |
| --- | --- | --- |
| Wrong-lesson lock-in | a fluke run teaches a bad rule that then biases every future run | require generality + evidence; fitness-gate edits; tag lessons so you can prune them |
| Heuristic bloat | the file grows until context is sludge and reasoning degrades | cap the rule count; periodically consolidate and dedupe; lean context (Ch 8) |
| Reward hacking | the loop "improves" the score by editing the thing that scores it | the fitness function must be external and un-editable by the loop (Ch 4) |
| Spec drift | self-edits wander off the original objective over many runs | keep the objective/spec human-owned, outside the self-editable region |
Pitfall · the loop that games its own grader
The most dangerous failure is reward hacking. If a loop can edit *both* the work and the test that grades it, it will discover that weakening the test is the cheapest way to raise the score — and it will do so confidently. The scorer must live outside the loop's reach: it cannot edit the tests it's graded on, the coverage config, or the metric definition. This is the maker/checker separation of Chapter 4, restated for self-improvement — the maker must never also be the judge.

Try it · grow a heuristics file, then gate it
Take your `/iterate` from Chapter 5 and add the two bookends from Worked Example 9.1. Run it on two similar tasks and read `.claude/heuristics.md` — are the rules general and correct, or run-specific noise? Then add a trivial fitness gate: keep a new heuristic only if the test count didn't drop. You've just turned reflection into selection.

Summary- Self-improvement is persistence + reflection: the weights never change; the loop writes a generalised lesson to a re-read file, so the next run starts smarter.
- Persist to a sidecar file by default, `CLAUDE.md` for cross-cutting lessons, the body itself only behind a fenced marker.
- Reflection alone drifts; a fitness function makes self-edits an accept-only-if-better experiment — actual hill-climbing.
- Guard against wrong-lesson lock-in, bloat, and especially reward hacking: the scorer must be external and un-editable by the loop.

Exercises 9- The model's weights don't change between runs. So where does the "improvement" actually live, and what does that imply about writing it down?             Show solutionIt lives in a file that gets re-read at the start of the next run — `CLAUDE.md`, the command/skill body, or a sidecar heuristics file. Context is volatile and discarded each run, so a lesson only carries forward if it's persisted to disk; "reflect and remember" must mean "reflect and write to a re-read file."
- Why is a fitness function the line between self-improving and self-corrupting?             Show solutionWithout an objective score you keep edits by the loop's own say-so, so noise from a fluke run gets baked in as a rule and biases everything after it. A score lets you keep only edits that measurably help and revert the rest — mutation plus selection (hill-climbing) instead of mutation alone (drift).
- What must be true of the scorer for fitness-gated self-improvement to resist gaming, and which earlier chapter is this?             Show solutionThe scorer must be external to and un-editable by the loop — it can't modify the tests, coverage config, or metric it's judged on. Otherwise it optimises the metric rather than the work (reward hacking). This is the maker/checker separation from Chapter 4: the agent doing the work must never also be the one grading it.

 ===== CHAPTER 10 ===== Chapter 10 · Part III
## Ch 10 — A catalogue of loops

Ten loops you can adapt today. Each names its condition or signal, its body, its surface, and its guardrails.

Learning objectives- Read each pattern as a complete loop: condition/signal, body, surface, guardrail.
- Pick the right surface and stop-mechanism for a given chore.
- Assemble one pattern end to end on a sandbox.


### 10.1 The working library

The shape is always the same — a verifiable condition or a watched signal, a reusable body, the right surface, and a circuit breaker. Adapt the specifics to your stack; the structure carries over.

Gallery 10.1 Patterns worth keeping
Each card is a whole loop in miniature. Read the command as the body; the note names type, surface, and the guardrail that keeps it safe.


##### PR babysitting

Interval · in-session. Guard: human merge gate, never auto-merge.

`/loop 5m /babysit  → rebase, answer review, fix CI`
##### Flaky-test remediation

Goal. Guard: cap hypotheses; revert on regression.

`/fix-flaky test/checkout/* → 20/20 on two runs`
##### Security-scan triage

Scheduled Routine (laptop off). Guard: findings → PRs, not edits to main.

`nightly Routine: /sec-sweep`
##### Dependency audit

Scheduled. Guard: one PR per dep; tests gate each.

`/upgrade-dep per outdated package, PR each`
##### Docstring backfill

Goal. Guard: doc-lint passes; no logic edits.

`/goal every public fn in src/ has a docstring; doc-lint clean`
##### Large migration

Goal + parallel. Guard: worktree isolation; bounded fan-out; PR each.

`/batch one unit per agent → all call sites compile`
##### Data pipeline

Interval. Guard: log each op; cap consecutive failures.

`/loop 1m validate→transform→archive each new file`
##### Feedback triage

Interval or Routine. Guard: create issues, never reply externally.

`/loop 30m /triage feedback/ → labelled issues`
##### Release notes

Event (on tag) or scheduled. Guard: don't invent changes.

`/release-notes since the last tag → grouped markdown`
##### On-call triage

Event (on alert). Guard: summarise + propose, never auto-remediate prod.

`on alert: cluster logs, propose the runbook step, page a human`Worked Example 10.1 The security-sweep body, end to end
A body you'd attach to a nightly Routine. Note that every escape from "fix only" to "touch main" is closed by instruction.

markdown · .claude/commands/sec-sweep.mdcopy
```markdown
---
description: Nightly security sweep — scan, triage, propose fixes as PRs only.
---
1. Run the scanners: semgrep, gitleaks, checkov, trivy. Collect all findings.
2. Deduplicate and cluster by root cause. Drop anything already in an open issue.
3. For each distinct cluster, draft the minimal remediation on a new branch and
   open a PR titled "[sec] <cluster>" with the finding and the fix rationale.
4. NEVER push to main and NEVER auto-merge. Stop when every cluster has a PR or
   an existing issue. Summarise the counts.
```


**What happened:** the loop's autonomy is bounded by "propose, don't merge" — exactly the constraint Chapter 12 formalises as a governance control.

Worked Example 10.2 Assembling a pattern from its four parts
Take "keep the changelog current." Name the four parts and the loop writes itself.

text · the four-part recipecopy
```plaintext
Signal/condition: a new tag is pushed (event) — or "CHANGELOG has an entry per merged PR" (goal)
Body:             /release-notes since the previous tag
Surface:          a GitHub-triggered Routine (runs with laptop off)
Guardrail:        open a PR with the notes; a human merges; never invent entries
```


**What happened:** naming the four parts *is* the design step — once they're filled, choosing the command and surface is mechanical.

Try it · ship one pattern
Pick the pattern closest to a real chore. Write its body, run it once interactively to validate the cycle and guardrails, then promote it to the right surface. Watch the *first full cycle* before walking away — the rule for every new loop.

Summary- Every production loop reduces to four parts: a condition or signal, a body, a surface, and a guardrail.
- Goal-bounded patterns (flaky, docstrings, migration) have provable end states; interval/event patterns (babysit, triage, pipeline) watch a signal or drain a queue.
- Anything that must run while you're away belongs on a Routine; anything touching prod stays behind a human gate.

Exercises 10- Why does the security-sweep loop deliberately *not* have a "fix main" condition?             Show solutionUnattended changes to production code from a scanner are exactly what must be gated behind human review. Stopping at "every finding has a PR" keeps the loop's autonomy on the safe side of the merge gate.
- Which patterns belong on a Routine rather than in-session, and what's the deciding factor?             Show solutionAnything that must fire while you're off-machine — sec-sweep, dependency audit, overnight pipelines, release notes on a tag. The deciding factor is whether the cadence/trigger needs to run independent of an open terminal and an awake machine.
- For the flaky-test pattern, state the exact verifiable stop condition and one guardrail.             Show solutionStop: "20/20 passes on two consecutive runs." Guardrail: "cap at N hypotheses and revert on any regression," so it can't thrash forever or 'fix' flakiness by weakening the test.

 ===== CHAPTER 11 ===== Chapter 11 · Part III
## Ch 11 — Anti-patterns

Loops fail in recognisable ways. Learn the symptom, the cause, and the one fix.

Learning objectives- Recognise the seven common loop failures by their symptoms.
- Apply the specific fix for each.
- Explain why loop costs compound, and how caching and lean context counter it.


### 11.1 The catalogue of failure

Every failure below is the flip side of leverage. The skeptics are right that an unattended loop can become "a very confident conveyor belt for bad work" — costs vary wildly, quality can drop, and slop accumulates. Here is the catalogue.

| Anti-pattern | Symptom | The fix |
| --- | --- | --- |
| Runaway loop | hours pass, tokens burn, no convergence | turn/time cap in the condition; a consecutive-failure breaker |
| Confident conveyor belt | green checks, broken feature, merged anyway | independent checker that exercises as a user (Ch 4); human merge gate |
| Un-verifiable goal | loop "completes" with the work undone | condition as observable output with a runnable check (Ch 1) |
| Primitive mismatch | /loop on finish-line work, or /goal that never ends | the "push vs watch" test (Ch 2) |
| Cost blowout | surprise four-figure API bill | verify route with /status; avoid the -p trap; cache repeated context |
| Skill decay | you no longer understand your own codebase | review the PRs; keep design and acceptance criteria in human hands |
| Ungated prod access | an agent ships to production unilaterally | scoped permissions; keep agents off auto-deploy (Ch 12) |
Mechanism · cost compounds through re-sent context
Loops re-send context every cycle, so token costs compound faster than developers expect. The lever is caching: cached input tokens bill at a fraction of the base rate, so any loop that repeatedly re-sends a large system prompt or file context should be structured to hit the cache. For headless runs, prefer loading exactly what's needed (the `--bare` direction) over dragging everything in each invocation.

Pitfall · the "dark factory" temptation
The end state everyone imagines — code generated, reviewed, and merged with zero human involvement — is precisely the configuration that ships confident bugs at scale. Resist building it. Keep a human at the merge gate and on the spec, and let the loop own the toil in between.

Try it · audit a loop you've built
Take any loop from Chapter 10 and run it against the table. Does it have a cap? An independent checker? A verifiable condition? The right primitive? A billing-verified surface? A merge gate? Fix the first gap before it runs unattended again.

Summary- Seven failures recur: runaway, confident conveyor belt, un-verifiable goal, primitive mismatch, cost blowout, skill decay, ungated prod.
- Each has a specific fix already covered in earlier chapters — the anti-patterns are those chapters' lessons stated as warnings.
- Cost compounds through re-sent context; caching and lean context are the counters.

Exercises 11- Which anti-pattern is most dangerous in a regulated or financial context, and why?             Show solutionUngated prod access combined with the confident conveyor belt: an autonomous agent shipping unverified changes to production violates change-management controls and can cause material, auditable harm — and the failure is silent because the checks were green.
- "My loop is cheap and fast." Why might that be a warning sign rather than a success metric?             Show solutionCheap-and-fast often means the loop isn't really verifying — no user-level checks, no real reproduction — so it converges on "looks done" quickly while quality drops. Real verification costs turns; suspicious efficiency can mean the checker has no teeth.
- Map each row of the table back to the chapter that prevents it.             Show solutionRunaway → Ch 1/5 (caps); conveyor belt → Ch 4 (verification); un-verifiable goal → Ch 1; primitive mismatch → Ch 2; cost blowout → Ch 3 (+ caching here); skill decay → Ch 13/governance; ungated prod → Ch 12.

 ===== CHAPTER 12 ===== Chapter 12 · Part III
## Ch 12 — Governance & safety

Autonomy is acceptable to an auditor only when it's bounded, scoped, and traceable.

Learning objectives- State the four controls that make autonomous loops safe and auditable.
- Write a scoped, audited agent configuration.
- Answer the questions a technical-due-diligence reviewer will actually ask.


### 12.1 The controls that satisfy a reviewer

If you operate in a regulated domain — or you're heading into technical due diligence — autonomous agents opening PRs and touching infrastructure are exactly what a reviewer will probe under AI governance and change management. The good news: the controls that satisfy an auditor are the same ones that make loops safe.


*[Diagram: Figure 12.1 The agent proposes; CI and a human dispose; the path to production is closed to the agent.]*

- **Human merge gate** — agents open PRs; humans merge. No auto-merge to a protected branch, ever.
- **Scoped permissions** — least privilege. Allow-list the tools and directories an agent can touch; deny the rest.
- **Audit logging** — a `PreToolUse` hook recording every command (Ch 7) gives the traceable record reviewers ask for.
- **No prod credentials** — agents never hold deploy/production secrets; the path to production is gated by humans and CI, structurally closed to the agent.

Worked Example 12.1 A scoped, audited agent configjson · .claude/settings.json — least privilege + auditcopy
```json
{
  "permissions": {
    "allow": ["Read", "Edit", "Bash(npm test:*)", "Bash(npm run lint:*)", "Bash(git*)"],
    "deny": ["Bash(rm -rf*)", "Bash(*deploy*)", "Bash(*prod*)", "Bash(curl*)"],
    "additionalDirectories": ["./packages/app"]
  },
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash",
        "hooks": [{ "type": "command",
          "command": "jq -r '\"\\(now|todate) \\(.tool_input.command)\"' >> .claude/audit.log" }] }
    ]
  }
}
```


**What happened:** the allow/deny scoping and the audit hook together are a control you can *show* a reviewer — not an assurance that the agent will behave, but a mechanism that holds when it doesn't.

Mechanism · what a DD reviewer actually asks
Expect questions shaped like: *Who or what can change production? Show the controls.* · *How do you trace what an autonomous agent did?* · *What stops an agent shipping unreviewed code?* · *How are agent permissions scoped and rotated?* Your answers: a human merge gate on protected branches, a per-action audit log, allow/deny scoping, and agents holding no production credentials. Demonstrating these *is* the deliverable.

Pitfall · convenience that defeats the control
The fastest way to undo all of this is to grant broad permissions "just for now," wire a loop straight into a deploy step, or run it under credentials that can reach prod. Each is a single config line that converts a governed system into an ungoverned one. Review permission scopes the way you review code.

Try it · write the allow-list
For one real agent, write the `permissions` allow/deny block above tailored to its job, plus the audit hook. Then try to make the agent do something outside its scope and confirm it's blocked and logged — you've produced a control you could show a reviewer.

Summary- Four controls make autonomy auditable: human merge gate, scoped permissions, audit logging, no prod credentials.
- They are the same controls that make loops safe — governance and safety are one problem here.
- A reviewer wants mechanisms, not assurances; "we trust the model" is not an answer.

Exercises 12- How do you demonstrate that an autonomous agent *cannot* unilaterally ship to production?             Show solutionShow structural controls: protected branches with required human approval, agents holding no deploy/prod credentials, CI gates the agent can't bypass, and an audit log of every action. The agent can only ever *propose*; merge and deploy are gated by humans and CI.
- Why is "we trust the model" not an acceptable governance answer, regardless of how good the model is?             Show solutionGovernance requires bounded, verifiable, traceable behaviour independent of intent or capability. "Trust" is unfalsifiable and unauditable; a control is a mechanism that holds even when the model is wrong — which, given confident-wrong failure modes, it sometimes will be.
- Your audit log exists but no one reads it. Is the control satisfied? Explain.             Show solutionPartly: the log provides traceability after the fact, which is necessary for review and incident response. But a control is only complete with a process that uses it — periodic review, alerting on denied actions, retention. The artifact plus the procedure is the control.

 ===== CHAPTER 13 ===== Chapter 13 · Part III
## Ch 13 — The frontier

Where this is heading, and the questions no one has answered yet.

Learning objectives- Describe the patterns already in use at the frontier: agent trees and compounding loops.
- State the open problems that bound full autonomy.
- Identify the one job you must not hand to a loop.


### 13.1 Better systems, not a better model

The people who built these tools describe their daily work as managing "armies of agents," with agents prompting agents in trees that fan out to thousands. The frontier isn't a better model — it's better systems around the model, and the honest unknowns are mostly about verification and judgment, not capability.


*[Diagram: Figure 13.1 The human designs loops; loops run trees and compounding cycles; verification is the ceiling.]*

Gallery 13.1 Compounding loops people are already running
These run continuously in the background, each making the codebase a little better unattended. An agent that runs once gives leverage; a loop that runs continuously gives compounding.


##### Architecture improver

Nightly, proposes one structural simplification with a rationale and a PR.

`improve one architectural seam per night, PR + reasoning`
##### Duplicate hunter

Finds duplicated abstractions and unifies them behind one helper.

`detect duplicated logic; unify behind a shared util, PR`
##### Dead-code remover

Continuously prunes unused exports and unreachable branches.

`remove provably-unused code; keep the build green`
##### Performance watchdog

Watches benchmarks and opens a PR when a regression appears.

`on benchmark regression, bisect and propose a fix`
##### Dependency-freshness loop

Keeps deps current with one tested PR at a time.

`nightly: bump one dep, run suite, PR`
##### Docs-freshness loop

Re-checks that docs match code and files drift as issues.

`flag docs that no longer match the API they describe`
Each shares the same skeleton from this book: a goal-bounded action, an independent verifier, a budget, a surface that runs unattended, and a human merge gate.


### 13.2 The open problems

Be honest about these — they're where your judgment stays load-bearing.

- **The verification ceiling.** A loop is only as good as its checker, and we don't have general, cheap verifiers for "is this *correct* and *well-designed*," only for "does it pass these checks." Autonomy is bounded by what you can verify, not by what the model can generate.
- **The cost/quality frontier.** Token costs compound and quality can drift; there's no free lunch where more autonomy is strictly better, and the economics shift under your feet (Chapter 3).
- **Slop accumulation.** Confident, plausible, subtly-wrong output compounds in a loop just as fast as good output. Volume is not value.
- **Skill atrophy.** If the loops write all the code and you stop reading it, your ability to specify, review, and course-correct decays — and that ability is the thing the whole system depends on.

Mechanism · what actually moved
The jump from source code to agents was a step up in abstraction; loops are framed as an equally large step — from operating a tool to designing the system the tool runs inside. The person running loops compounds faster than the person running agents, not by working harder but by building better feedback systems. The leverage is real. So is the failure mode. The whole discipline is keeping the first without the second.

Try it · design an overnight loop on paper
Spec (don't build) a nightly self-improvement loop for your codebase. Name: the discovery step, the goal-bounded action, the *independent* verifier, the budget/turn cap, the surface (a Routine), and the human gate. Then find the single point where, if the verifier is wrong, the loop does damage — and add the control that catches it. That artifact is the synthesis of this whole course.

Summary- The frontier is agent trees and always-on compounding loops — better systems around the model, not a bigger model.
- Full autonomy is bounded by verification, cost/quality, slop, and skill atrophy — mostly epistemic limits.
- The compounding loops people run all reuse this book's skeleton: goal + independent verifier + budget + unattended surface + human gate.

Exercises 13 · the final questions- What is the limiting factor on fully autonomous "dark factory" coding — technical or epistemic?             Show solutionEpistemic, primarily. Generation is largely there; what's missing is general, trustworthy, cheap *verification* of correctness and design quality. Until a checker can be as right as a good senior engineer, full autonomy ships confident bugs — the bottleneck is knowing the work is right, not producing it.
- You've automated your toil into loops. What is the one job you must *not* hand off, and why?             Show solutionOwning the spec and the merge decision — the definition of "done" and the judgment that a change is acceptable. The loops are leverage on execution; the moment you outsource judgment, you've removed the only thing standing between compounding value and a confident conveyor belt for bad work.

 ===== APPENDIX A ===== Appendix A · Reference
## App — A field guide of prompts, skills & subagents

The part that only clicks when you can see the actual thing an expert types or commits. Everything here is complete and copy-paste ready.

How to use this appendix- Steal the prompts in A.2 verbatim and swap in your specifics — they encode the discipline, not just the request.
- Drop the `SKILL.md` files in A.3 into `.claude/skills/` and adapt the commands to your stack.
- Use the subagents in A.4 to separate the agent that writes from the one that checks.
- Read each *Expert notes* line — the value is in *why* a clause is there, not just that it is.


### A.1 Three ways to package a workflow

Before the artifacts, the formats — because an expert reaches for a different one depending on whether *they* trigger it, *Claude* triggers it, or it needs its own clean context. As of Claude Code v2.1.101 (April 2026) slash commands and skills are **merged**: both create a `/command`, and skills are the recommended, portable (Agent Skills open standard) format.

| Format | Lives in | Triggered by | Reach for it when |
| --- | --- | --- | --- |
| Skill | .claude/skills/<name>/SKILL.md | /name or Claude auto-invokes when the description matches | a reusable workflow or standing expertise; supports bundled files, dynamic injection, and invocation control |
| Command (legacy) | .claude/commands/<name>.md | /name | a simple single-file macro; still works, but a same-named skill wins |
| Subagent | .claude/agents/<name>.md | a skill's agent: field, or the Task tool | verification, parallelism, or any work that needs an isolated context and its own tools |
Mechanism · the frontmatter that changes behaviour
A single `SKILL.md` covers every case by its frontmatter: `description` is the trigger (loaded at session start; the full body loads only when invoked — "progressive disclosure"). `disable-model-invocation: true` makes a skill manual-only — use it for anything with side effects (you don't want Claude deciding to deploy). `user-invocable: false` makes it background knowledge Claude applies automatically — for conventions. `allowed-tools` restricts the toolset. `context: fork` runs it in an isolated subagent, and `agent:` picks which. Inside the body, `$ARGUMENTS` (or `$1`, `$2`) takes input, and `!`some command`` injects that command's live output before Claude reads the skill. The command files shown earlier in this book still work unchanged; the `SKILL.md` versions below are simply the modern form.


### A.2 Expert prompts you'd actually type

These go straight into a session (or wrap one in `/goal`). What separates them from "fix the bug" is that they encode the reflexes an expert applies without thinking.

Prompt A.1 Fix a bug properly, not just to greentext · paste into a session, or wrap in /goalcopy
```plaintext
A test is failing: <test path / observed behaviour>. Fix it properly, not just to green.

1. Reproduce: run the failing test and paste the exact failure. State in one line
   what is observed vs expected.
2. Isolate: find the smallest code path that triggers it. Change nothing yet —
   show me where the defect lives and why.
3. Root cause: explain the actual cause in one or two sentences. If you are not
   certain, say so and gather more evidence before editing. Confidence requires evidence.
4. Minimal fix: make the smallest change that addresses the root cause. No
   unrelated refactors, no reformatting.
5. Prove it: run the test and show it passing, then run the affected module's full
   suite and show it green.
6. Regression test: add a test that fails without your fix and passes with it.
   Show both states.
7. Prevention: if this class of bug can recur, append one line to CLAUDE.md
   describing the rule that prevents it.

Do not declare done until steps 5 and 6 both show output.
```


**Expert notes:** reproduce before theorising, isolate before editing, and prove with output you can see. "Confidence requires evidence" and "show both states" are the two lines that stop a plausible-but-wrong fix from sailing through.

Prompt A.2 Plan first, touch nothingtext · plan mode (Shift+Tab)copy
```plaintext
Enter plan mode. Do NOT edit any files.

Goal: <feature>.
- Read the relevant code and the spec at <path>.
- Produce a step-by-step implementation plan: files to change, new modules, the
  data flow, and the tests you'll write for each step.
- Call out risks, unknowns, and anything that needs a decision from me.
- List what you will NOT do (out of scope).

Stop after the plan. I will review and approve before any code is written.
```


**Expert notes:** plan mode makes the model design before it commits. "Files to change + tests per step + out-of-scope" turns a vague plan into a contract you can actually review and approve.

Prompt A.3 Harden a module for productiontext · a goal with a checkable readiness listcopy
```plaintext
/goal the <module> is production-ready by these checks, all shown passing:
(1) every external input is validated and every error path is handled — no unhandled
    rejections; (2) no secrets or credentials in code or logs; (3) `npm test` and
    `npm run lint` are clean; (4) the happy path and at least one failure path are
    covered by tests; (5) structured logging on the error paths.
Do not weaken or delete any existing test to make this pass. Stop after 30 turns
and summarise what remains.
```


**Expert notes:** "production-ready" becomes a concrete checklist where each item is observable in output, so the evaluator can actually judge it. "Don't weaken any test" closes the cheapest cheat — the same anti-proxy move as Chapter 4.

Prompt A.4 Review like the person who'll be on calltextcopy
```plaintext
Review the diff on this branch as a senior engineer who will be on call for this
code. Run `git diff main...HEAD` first.

Organise findings by severity:
- Blocking: correctness bugs, security issues, data loss, missing error handling.
- Should-fix: unclear logic, missing tests, performance traps.
- Nits: style, naming.

For each finding, quote the file and line and give the concrete change. If a choice
is well-made, say so briefly. Do not rewrite the code — tell me what to change and why.
```


**Expert notes:** "who will be on call" sets the bar at correctness, not taste. Severity buckets plus file/line plus "don't rewrite, tell me what to change" make the output a review you can act on, not a wall of edits to untangle.

Prompt A.5 Fan a migration across worktreestext · /batchcopy
```plaintext
/batch migrate every component from <old API> to <new API>, one component per
worktree agent. Each agent: update the component and its tests, run that
component's tests, and open a PR titled "[migrate] <component>".
Constraints: do not modify shared components used by others; if a component does
not use the old API, report "no change" instead of opening a PR.
Stop when every component has a PR or a "no change".
```


**Expert notes:** the unit of fan-out is one component; the per-agent check is its own tests; the "no change" path is what lets you tell "done, nothing to do" from "silently skipped" across dozens of PRs. Worktrees handle the isolation.

Prompt A.6 Explore a codebase, read-onlytext · pair with the Explore agent / context: forkcopy
```plaintext
Explore this codebase and explain it to me. Do NOT edit anything.
- Map the top 3 directory levels and the main entry points.
- Trace one full request from entry to response.
- List the external dependencies and what each is for.
- Flag the two or three areas that look riskiest or least understood.
Present a short structured brief, not a file dump.
```


**Expert notes:** run this through a forked Explore agent (next section) so the verbose reading never lands in your main context — only the brief comes back. "A brief, not a file dump" forces synthesis over regurgitation.

Prompt A.7 Build a safety net before a risky refactortext · characterization tests firstcopy
```plaintext
Before refactoring <module>, build a safety net. Do NOT change behaviour yet.

1. Read <module> and list the externally observable behaviours — inputs, outputs,
   and side effects — that callers depend on.
2. Write characterization tests that pin the CURRENT behaviour exactly, quirks
   included. Run them and show them green against the existing code.
3. Only now refactor. After each step, re-run those tests; they must stay green.
   If one goes red you changed behaviour — stop and tell me.
4. At the end, show the full suite green and summarise what changed structurally
   (and confirm nothing changed behaviourally).
```


**Expert notes:** characterization tests pin behaviour *before* you touch it, so the refactor has a tripwire. "If one goes red you changed behaviour — stop" turns the suite into the contract a refactor may not break.

Prompt A.8 Triage from a stack tracetextcopy
```plaintext
Here is a production error: <paste stack trace / log>.

1. Read the trace and name the exact failing call and the most likely cause in one
   line. Do not speculate beyond what the trace supports.
2. Find the code at the top of our own stack frames and show me the relevant lines.
3. Write a failing test that reproduces this error locally. Show it failing.
4. Propose the minimal fix and its blast radius (what else calls this path).
Stop there — I will decide whether to apply the fix.
```


**Expert notes:** it starts from evidence (the trace), forces a local reproduction before any fix, and surfaces blast radius — the exact sequence an on-call engineer runs before touching production code.

Prompt A.9 Simplify without changing behaviourtext · the built-in /simplify does this toocopy
```plaintext
Simplify <file> without changing its behaviour.

- Keep the public interface and all observable behaviour identical.
- Reduce nesting, remove dead code and needless abstraction, clarify names.
- Do NOT add features, change error handling, or "improve" the logic.
- After each change, run the tests and show them green. If a behaviour you're
  touching has no test, write one first.
Show a short before/after summary of what got simpler and why.
```


**Expert notes:** "behaviour identical, tests green after each change" is what keeps a cleanup from quietly becoming a rewrite; "write a test first if none exists" closes the gap where simplification silently breaks an untested path.

Prompt A.10 Investigate performance before optimisingtextcopy
```plaintext
The <operation> is too slow. Investigate properly before optimising.

1. Measure: run the profiler or add timing and show me where the time actually
   goes. State the current number.
2. Form ONE hypothesis for the dominant cost, backed by that measurement.
3. Make the smallest change that tests the hypothesis. Re-measure; show the new number.
4. If it didn't help, revert and try the next hypothesis. Do not stack speculative
   optimisations.
Report the before/after numbers and what actually mattered.
```


**Expert notes:** measure first, one hypothesis at a time, re-measure, revert what doesn't help. The before/after number is the only proof that counts — it's what separates real optimisation from cargo-culting.


### A.3 Skills · real SKILL.md files

Each lives in its own folder under `.claude/skills/`; the folder name is the command. The frontmatter is doing real work in every one — read the notes.

Skill A.1 · auto-invoked, live diff commit messagesmarkdown · .claude/skills/commit/SKILL.mdcopy
```markdown
---
description: Write a Conventional Commits message from the staged diff. Use when the
  user asks to commit, wants a commit message, or asks to review staged changes.
allowed-tools: Bash(git*)
---