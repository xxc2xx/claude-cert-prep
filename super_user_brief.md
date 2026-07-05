# Claude Super-User Brief

How I'd present Claude to colleagues who ask "what is this thing and why should I care."

Written for Winston (Adidas SEA+PAC retail intel). Companion to `cheatsheet.md` — the cheatsheet is the *what*, this brief is the *why* and the *how I'd say it out loud*.

Pivot date: 2026-05-30. Originally cert-prep material; reframed after the Anthropic Partner cert registration was blocked (partner-only, applications paused). Goal shifted to "be the person on my team who can confidently explain and demo Claude."

Update 2026-07-05: Exam registered. **CCAR-F — Claude Certified Architect, Foundations. Sunday 30 August 2026, 2:00 PM HKT. Candidate ID: ANTH220651.** Goal is now both: pass the exam AND be that person on the team. This brief serves the presentation side; `cheatsheet.md` and `field_manual.md` serve the exam side.

---

## How to use this doc

- Read sections aloud — if a sentence doesn't sound like *you* talking, rewrite it.
- The **3 story arcs** below are the backbone. Memorize the arc, not the words.
- Each arc has three depths: **30 sec (exec)**, **5 min (peer)**, **15 min (technical)**. Pick depth based on who's in the room.
- Anticipated Q&A at the bottom — read it before any presentation so the muscle memory is fresh.

---

## Arc 1 — "Why API/Claude Code, not chat-only"

### The hook
> "Most people use Claude like a smarter Google. We use Claude like a teammate that can be cloned, scheduled, and pointed at our actual data."

### 30-second exec version
> Claude isn't just a chatbot — it's an API we can wire into our pipelines. I built a weekly intel agent that scrapes Nike/Adidas/Puma across SEA+PAC, reads regional news, and emails me a structured brief every Monday. Same work used to take half a day of manual reading. It runs at 6am unattended.

### 5-minute peer version
The difference between **claude.ai chat** and **the Claude API** is the difference between using Excel by hand and writing a macro. Both end at the same answer, but one scales and one doesn't.

The API lets us:
1. **Loop** — Claude calls a tool (e.g. fetch a webpage), gets the result, decides what to do next, repeats until done. That loop is what makes it an *agent*, not a chatbot.
2. **Schedule** — Task Scheduler kicks `intel.py` off at 6am Monday. No one is sitting at a keyboard.
3. **Mix models** — Haiku (cheap, fast) for "extract this in one line." Sonnet (balanced) for "give me a 6-point analysis." Opus (most capable) for "write the executive narrative across all 7 markets." Different jobs, different tiers.
4. **Cache** — if I'm sending the same brand context 6 times for 6 markets, I cache it once and pay ~10% on the re-reads.

That's how a single Monday-morning email replaces what used to be a half-day of manual market reading.

### 15-minute technical version
*(Walk through `intel.py` architecture — see Demo Cheatsheet below.)*

Key points to hit:
- `MODEL_EXTRACT` / `MODEL_ANALYZE` / `MODEL_SYNTHESIZE` constants in `config.py` — model selection is **a deliberate design choice**, not a default.
- The 4-step tool-use loop: `tool_use` stop_reason → execute → return `tool_result` → repeat until `end_turn`.
- Why messages must alternate user/assistant — the API enforces conversational rhythm.
- Where prompt caching pays off: long brand context reused across markets = cache write once, read N times.

---

## Arc 2 — "How we save 70%+ on the Claude bill"

### The hook
> "The first time I built this pipeline, it cost about [FILL: $X]. After three optimizations, it's [FILL: $Y]. Same output, same quality. Here's what changed."

### 30-second exec version
> Two levers: pick the right model for each subtask (don't use Opus when Haiku will do), and cache the parts of every prompt that don't change. Together those cut our token bill by roughly 70%.

### 5-minute peer version
Three optimizations, ranked by impact:

**1. Model tiering (biggest win)**
- I had been calling Opus for everything because "best is best." But Opus is ~15× the price of Haiku.
- For tasks like *"extract the headline from this article in one line"* — Haiku is identical quality and 1/15th the cost.
- I split the pipeline into three tiers (`EXTRACT` = Haiku, `ANALYZE` = Sonnet, `SYNTHESIZE` = Opus). Most calls dropped to Haiku/Sonnet. Opus is reserved for the final narrative — which is where it actually matters.

**2. Prompt caching**
- Anthropic offers an opt-in cache (`cache_control: {type: ephemeral}`). Set it once on a block of text, and any subsequent call within 5 minutes reads from cache at ~10% of the normal token price.
- For my pipeline, the *brand context* (Nike news, brand framing) is identical across all 7 markets. So I cache it on the first market and read it from cache on the next 6.
- Cache write costs 1.25× per token, cache read costs 0.10× — break-even after just 2 reads. Free money after that.

**3. Batch API**
- For non-urgent jobs (anything that doesn't need to land in <1 min), Anthropic offers a Batch API at **50% off**. SLA is 24h, almost always finishes in 1-4 hours.
- My weekly intel pipeline runs Monday morning, but the inputs are ready Sunday night. So in theory I could submit it as a batch Sunday and it'd be done by 6am Monday — at half the price. *(Haven't migrated yet — that's on the to-do.)*

### 15-minute technical version
- Show the actual `config.py` constants for `MODEL_EXTRACT`/`ANALYZE`/`SYNTHESIZE`.
- Walk through how to add `cache_control` to a content block.
- Explain TTL: **default 5 minutes**, opt into 1 hour with `"ttl": "1h"`. Pick 1h for long-horizon agents that take >5 min between calls.
- Cache write/read pricing math: at 1.25× write and 0.10× read, you break even at 2 reads. Don't cache things you'll read once.
- Batch API: same API key, different endpoint. Submit up to 100k requests, get results within 24h, 50% off.

---

## Arc 3 — "What is an agent, actually?"

### The hook
> "Everyone says 'agent' like it's magic. It's not. An agent is a `while` loop where the loop body asks an AI what to do next."

### 30-second exec version
> An agent is a chatbot that can take actions — search the web, query a database, call an API. We tell it what tools it has, and it decides when to use them. The loop runs until the AI says "I'm done." That's it. Everything else is engineering.

### 5-minute peer version
Mental model:

```
while True:
    response = claude.ask(conversation_so_far)
    
    if response.stop_reason == "end_turn":
        break                        # ← Claude says "I'm done"
    
    if response.stop_reason == "tool_use":
        result = run_the_tool(response)     # we run the actual tool
        conversation_so_far.append(result)  # feed result back
        # loop again — Claude reasons about the result
```

Three things to know:

1. **The agent is the loop, not the model.** The model is a function that takes "what's happened so far" and returns "what to do next." The loop is what makes it agentic.

2. **Tools are functions you define.** I tell Claude: "you have a tool called `fetch_url` that takes a URL string and returns webpage text." Claude doesn't run the tool — *I* do. Claude just decides when to call it. That's the safety property: Claude never touches your systems directly, your code does.

3. **MCP (Model Context Protocol)** is an open standard for exposing tools. Think of it like USB for AI — instead of writing custom tool definitions for every agent, MCP servers expose tools in a standard format. Power BI, GitHub, filesystems, browsers — they all have MCP servers. You plug them in and Claude can use them.

### 15-minute technical version
- Walk through `intel.py`'s tool-use loop concretely.
- Show the JSON structure of a `tool_use` block vs a `tool_result` block (note `is_error: true` for failures).
- Explain `stop_reason` values: `end_turn` (exit), `tool_use` (loop continues), `max_tokens` (bug — raise the cap), `pause_turn` (long tool, resumable).
- Cover the **Claude Agent SDK** — Anthropic's wrapper that handles the loop, permissions, and context management for you. You write the tools; the SDK runs the loop.
- Mention `claude-agent-sdk` is what Claude Code itself is built on — when you type a prompt to Claude Code and it edits files for you, that's exactly this loop running with file-edit tools.

---

## Anticipated Q&A

### From peers (analytics team)

**Q: Why not just use ChatGPT?**
> Both Anthropic and OpenAI ship great models. The reason I went Claude: the API surface is leaner (no `response_format`, no `function_calling`-vs-`tools` confusion), prompt caching ships first-class, and Claude Code as a CLI is the best dev experience I've used. For pure chat, either works. For pipelines I'm maintaining, Claude is easier to keep clean.

**Q: How do you handle hallucinations?**
> Two ways. (1) For factual extraction tasks, I give Claude the source document in the prompt and ask it to extract — it can't hallucinate facts it's been handed. (2) For analysis tasks, I treat Claude's output as a draft, not truth. The Monday brief I send is reviewed; if it claims a 30% market share shift, I check the source.

**Q: Doesn't this make our jobs obsolete?**
> The middle of the value stack gets compressed — boilerplate orchestration, basic summarization. The top (judgment, framing, audience) and the bottom (infra, data quality) get more valuable, not less. The person who can wire the pipeline and judge the output is who gets paid. (This is the 4-layer framework from my 1:1 doc.)

**Q: How long did it take to build?**
> First working version: a weekend. Iterating on quality (model tiering, caching, prompt engineering): about a month of evenings. Most of the time wasn't writing code — it was figuring out which model to use where, and what prompts produce reliable output.

### From execs

**Q: What's the ROI?**
> Manual version: ~3 hours/week of my time. Automated version: ~5 minutes/week of my time to skim the email. That's roughly [FILL: $X/year] in time freed, against ~[FILL: $Y/year] in API costs. The bigger win is the brief lands at 6am Monday before our standup — not Wednesday afternoon when I would have finished writing it manually.

**Q: Is the data safe?**
> Two things. (1) Anthropic doesn't train on API data by default. (2) The intel pipeline only reads public information — competitor websites, public news. No proprietary Adidas data goes into a prompt.

**Q: Could other teams use this?**
> Yes — the pattern (scheduled scrape + LLM summarize + email/Sheets output) generalizes to any team that does recurring market reading. SEA Marketing has the same Monday-morning problem. Brand could use it for franchise launch monitoring. Happy to help anyone interested.

### From technical / curious

**Q: Why model tiering and not just always use the cheapest?**
> Haiku is great for "extract this fact" but loses coherence on "write a 4-paragraph synthesis across 7 markets." You pay for quality where it matters. The art is identifying which steps actually need the bigger model.

**Q: What's the difference between Claude API and Claude Code?**
> Claude API is the raw HTTP endpoint — you write your own client code. Claude Code is a CLI built ON TOP of the API, pre-configured with file-edit tools, shell tools, and a permission system. Same model under the hood, different surface. For pipelines I use the API directly. For dev work I use Claude Code.

**Q: What's MCP again?**
> Model Context Protocol. Open standard (Anthropic published it, anyone can implement). It's a way to expose tools to AI agents in a standard format. Instead of every agent re-implementing "how to query Postgres," there's a Postgres MCP server and any MCP-aware agent can plug into it. Similar mental model to ODBC for databases or LSP for code editors.

**Q: What's prompt caching's catch?**
> Two: (1) the cache expires — 5 min default, opt into 1 hour. If your agent goes idle longer than that, you pay full price on the next call. (2) You only get 4 cache breakpoints per request, so you can't cache every block — pick the parts that change least often.

---

## Demo cheatsheet — `intel.py` walkthrough script

**Setup (30 sec):**
"This is `intel.py`. It runs every Monday at 6am via Task Scheduler. Reads brand newsrooms, regional news, and competitor coverage across 7 markets. Outputs a structured email + a row in Google Sheets."

**Walkthrough beats (3 min version):**
1. **`config.py`** — show the model tier constants. *"These are the three models I use. Notice I'm not hardcoding strings anywhere else."*
2. **`get_country_macro()`** — the macro news call. *"This uses `MODEL_EXTRACT` = Haiku. One-line summaries, doesn't need Opus."*
3. **`analyze_primary_brand()`** — the brand deep-dive. *"`MODEL_ANALYZE` = Sonnet. Structured 6-line output."*
4. **`assemble.py` → `build_market_pulse()`** — the synthesis. *"`MODEL_SYNTHESIZE` = Opus. This is where I pay for quality — the final narrative goes to my boss."*
5. **Cache demonstration** — point to where `cache_control` is set on the brand context. *"This block is identical across all 7 markets. Cache it once, read it 6 times at 10% cost."*

**Closing line:**
"Half a day's reading → 5 minutes to skim. That's the leverage."

---

## What to NOT volunteer in a presentation

- TTL gotchas (5 min default, 1 hour opt-in) — too in-the-weeds for most audiences
- Exact model ID date suffixes (`claude-haiku-4-5-20251001`)
- Cache write/read pricing math
- The 4 stop_reason values

These are in `cheatsheet.md` for when someone asks. Don't lead with them.

---

## Next time I revisit this doc

- [ ] Drop real numbers into the `[FILL: ...]` placeholders after the next monthly cost review
- [ ] Add the live "before/after Monday brief" screenshots once I'm ready to show them
- [ ] Update Arc 2 once the Batch API migration is live
