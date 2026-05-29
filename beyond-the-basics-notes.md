# Beyond the basics with Claude Code — Slide Notes

Source: YouTube (Anthropic / Claude channel)
Watched: 28 May 2026

---

## SECTION 1 — Why customize

### Slide 1: The thesis
> "If Claude can't do everything you can do, it can't do your job with you."
- The whole point of customizing Claude Code is to remove the gap between *your* working surface and Claude's reach.
- If Claude has fewer tools/access than you do, it stays a junior helper instead of a real collaborator.

### Slide 2: Where your work actually lives
- Real work happens in **Team chat (Slack/Teams/email)**, **CI/CD**, **Dashboards**, **Internal docs** — not just in the code editor.
- **TIP:** try doing a full day inside the Claude Code TUI. Every time you reach for another tool, that's a missing connection — give Claude that access.

### Slide 3: "In-context learning" (Knowledge)
- **Model weights = frozen** (Anthropic's job): internet-scale pretraining, knows *nothing* about your codebase.
- **Context window = live** (your job): CLAUDE.md, skills, tools, files just read, conversation so far — this is where you teach Claude *your* job each turn.

### Slide 4: What does an "IDE for Claude" look like?
- We build tools for *humans* to write code better. We should build tools *for agents* to write code better.
- Today's `Edit` tool is roughly `ed(1)` — humans got VS Code; agents have not yet. **That gap is the opportunity.**

### Slide 5: Two kinds of tools
- **Compensates for lack of intelligence** — rigid templates, guardrails, "don't let it touch X" → gets *less* useful as models improve.
- **Scales with intelligence** — more access, more context, faster feedback loops → gets *more* useful as models improve. **Build the second kind.**

---

## SECTION 2 — Context as a box

### Slide 6: Everything you give Claude has to fit
- The prompt is a fixed-size box: system + tool defs + CLAUDE.md + skills + conversation + room to work.
- Every customization on the left **competes** with the actual work on the right. Your whole codebase doesn't fit. Neither does your wiki.

### Slide 7: The software-packaging analogy
- Packaging *code* — disk + RAM are roomy, "just vendor it" is fine.
- Packaging *context* — space is *very* constrained, every token competes. **"Don't pay for what you don't use" is the whole game.**

### Slide 8: The KV cache is a second constraint
- Looks like an LRU cache problem; it isn't. Change one byte near the front → everything after it must be **recomputed** (lose the ~90% cache discount).
- Rule: **stable, shared stuff goes up front; volatile, per-task stuff goes at the end.**

---

## SECTION 3 — Plugin abstractions (Four primitives)

### Slide 9: Four plugin primitives
- **MCP** (new tools) · **Skills** (new procedures) · **Hooks** (run your code on Claude's events) · **Agents** (more Claudes).
- Not exhaustive, but these four carry most of the weight.

### Slide 10: What is MCP?
- A **protocol** for exposing tools/resources/prompts to any client — server says "here are my tools + JSON schemas," client hands them to the model.
- **Transport-agnostic** — stdio, HTTP, in-process.

### Slide 11: MCP — When is it the right tool?
- Designed so *any* client can use it (even ones with no shell, no filesystem) — that's the **portability win**.
- In Claude Code you *have* a shell, so if there's already a CLI, a **skill that drives the CLI is usually less code and fewer moving parts than standing up an MCP server**.

### Slide 12: MCP — Does it scale?
- Every tool's **name + description + schema** sits in the system prompt. 20 servers × 15 tools each → a prompt that's mostly tool definitions.
- **`tool search`** helps (load names up front, fetch schemas on demand) but doesn't fix the auth/process-lifecycle work — that's what you weigh against a CLI+skill.

### Slide 13: Skills are just files
- A skill is a folder: `SKILL.md` (the procedure), `scripts/`, `fixtures/…` — pure files Claude reads.
- **One-line description always loaded → cheap. Full SKILL.md + assets loaded only when invoked → don't pay for what you don't use.**

### Slide 14: Skills — Does it scale?
- Body is pay-per-use (good). Description is always loaded — and **reliable triggering takes a paragraph, not a line** ("use when the user says X, or Y, or asks about Z…").
- **No hierarchy yet** — a skill can't lazily expose sub-skills (the speakers want this).

### Slide 15: Hooks — Does it scale?
- Cost is in *your* process, not the prompt — hook code runs on Claude's events (file write, tool call, etc.).
- **Only injects tokens when it fires → true pay-per-use.** This is where "red squigglies" (linter-style feedback) lives.

### Slide 16: Subagents — more Claudes
- A subagent is a **named role with its own system prompt and tool set**; spawned with a task, returns a result, **its transcript does *not* come back**.
- **Skills are in-context. Agents are out-of-context. That difference is fundamental.**

### Slide 17: Agents — Does it scale?
- Each agent's **description still sits in the parent prompt** — same one-liner tax as skills.
- The **work** is fully off-box, but **coordination cost grows with fan-out** (prompts in, summaries out). Verdict: *kind of* scales.

### Slide 18: What isn't in this list? (CLAUDE.md and Memory)
- **CLAUDE.md** — you pay for *all of it, every turn*, even the 90% irrelevant to this task. Doesn't compose (1000 plugins × CLAUDE.md = 1000 files in box). Fine for the handful of rules that truly apply everywhere.
- **Memory** — model-curated, not human-curated. The "plugin line" is drawn at **human-authored, human-reviewed**. Memory is downstream — useful, but a different contract.

---

## SECTION 4 — Workflows

### Slide 19: Worktrees are critical (Multiclauding)
- **One repo · N worktrees · N Claudes, each on its own branch** — no more "hold on, the other Claude is mid-edit."
- Use `/rename` and `/color` so you can tell terminals apart at a glance.

### Slide 20: My actual setup
- The speaker keeps `~/code/claude-code-{1..9, a..f}` — 16 permanent worktrees of the same repo, each parked on a different daisy/* branch.
- Plus 4 worktrees for `anthropic/`, 9 for `apps/`, 3 for `cc-marketplace-*/`. **Always have a parking spot ready — never wait to create a worktree.**

### Slide 21: Different names, same upstream
- All worktree branches `daisy/main-*` track the same `origin/main`.
- After every PR merge → **reset the worktree to origin/main and reuse it**. No cherry-picking, no branch sprawl.

### Slide 22: Agent teams (experimental) — Claudes that talk to each other
- Spawn **long-lived teammates**, not one-shot subagents.
- `SendMessage` tool lets any Claude DM any other by name; team-lead delegates, teammates report back, you watch the transcript.

### Slide 23: PR babysitting on autopilot (`/loop`)
- `/loop 10m check my open PRs — fix red CI, address review, rebase if behind` → every 10 min, spawn a worktree agent → fix → push → comment.
- **`/loop` = recurring autonomy with a budget.** Used for PR babysitting, CI gardening, feedback triage.

### Slide 24: Auto mode — Stop asking, start doing
- `claude --permission-mode auto` (or Shift+Tab to cycle in-session) → no permission prompts, Claude **executes instead of proposing**.
- Still won't take destructive actions or post externally without asking. **CAVEAT: expensive** — unblocked agents do far more reads/retries/verification. Budget accordingly; treat as a different cost class than interactive use.

### Slide 25: Agent view — one place to manage all sessions
- Every session — bg jobs, `/loop` runs, overnight teams — appears in one list, grouped by state.
- Lightweight classifier keeps the headline current: **working / blocked / done.** Triage 20 sessions in 10 seconds. `Space` to peek, `Enter` to attach, type to dispatch.

---

## RECAP — Three things to take home

1. **Give it access.** If Claude can't reach it, Claude can't help with it.
2. **Mind the box.** Package context the way you'd package code for an embedded target.
3. **Pick abstractions that scale.** Prompt-cost axis: **hooks > skills > agents > MCP.** Pick by what you're optimizing for — and build for the **next** model, not the last one.

---

## TOP 2 — What I should focus on / implement in my work

These are picked specifically for the adidas SEA+PAC retail-intel pipeline (`external/`) and the Fabric/Power-BI analytics work (`internal/`):

### 1. Give Claude access to *where my work actually lives* — not just code

My current pipeline already touches Sheets, Gmail, scraped HTML, and Claude APIs, but on the analytics side Claude has **no direct reach** into Fabric semantic models, Power BI, SharePoint, or the Adobe Analytics dashboards I rely on every week. That gap means I'm still the human relay between dashboards and the brief.

**Action:** stand up at least one skill (or MCP server, only if portability matters) that lets Claude pull a Fabric/PBI semantic-model query result or an Adobe Analytics report directly — even read-only. Goal: one full weekly KPI brief produced without me ever copy-pasting numbers out of a dashboard. This is the single biggest unlock for the *Head-of-Analytics-with-AI-tilt* career direction.

### 2. Mind the box — repackage `CLAUDE.md` and prefer **hooks / skills** over stuffing context

My repo-root and `internal/CLAUDE.md` are already long, and the per-workspace files duplicate quite a bit. Per the talk, **CLAUDE.md is paid for every turn, even the 90% irrelevant to the current task, and doesn't compose**. On the prompt-cost axis the cheap-and-scalable spots are **hooks > skills > agents > MCP** — and right now I'm doing almost none of those.

**Action:**
- (a) Audit `CLAUDE.md` files: keep only rules that *truly apply everywhere* (credentials gate, no bare `except:`, model-tier constants). Move task-specific procedures (e.g., "how to build the EM traffic brief", "how to refresh market-share model") into **Skills** so they only load when invoked.
- (b) Add a **hook** for the two things I keep forgetting: (1) auto-run `python -m py_compile` after any Python edit, (2) block any commit that contains a hardcoded model string like `claude-sonnet-4-5` (must reference `config.MODEL_*`). This enforces my own CLAUDE.md rules without paying tokens for them every turn.

---

*Notes file at `~/claude-cert-prep/beyond-the-basics-notes.md` — paste into the Apple Notes "Claude" folder note as needed.*
