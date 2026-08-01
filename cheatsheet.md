# Claude Builder Cert — Cheatsheet

Started 2026-05-24. Built up live during prep sessions. Companion quiz at `quiz.html`.

---

## Block 0 — Exam-Day Quick Reference ⭐⭐⭐

*From Partner Specialization assessment post-mortem. These are the exact distinctions the exam tests.*

### Cluster 1: Permission, Policy, Enforcement

```
Deny → Ask → Allow  (evaluation order)
Deny wins in conflicts — an ask rule cannot bypass a deny rule

Permission model  = which actions Claude will take (allow/ask/deny)
Sandbox           = what the process can technically reach
Dev container     = stronger OS-level environmental boundary
Context isolation = what information an agent sees  ← NOT the same as sandbox
```

### Cluster 2: MCP Governance, Distribution, Access

| Need | Mechanism |
|---|---|
| Review a new MCP server | Standing MCP governance process (applies throughout activation, not just at kickoff) |
| Approve specific servers | `allowedMcpServers` — allowlist only |
| Prevent self-installed servers | `allowManagedMcpServersOnly` |
| Distribute approved MCP configs to all | **Plugin** |
| Give only to specific teams | Plugin + SCIM group + RBAC assignment |

**Allowlist = what is permitted. Plugin + RBAC = what is delivered and to whom.**

### Cluster 3: Enterprise Operational Architecture

| Component | Purpose |
|---|---|
| Hooks | Intercept, log, or react to Claude Code events. **Cannot select model.** |
| GitHub Actions Secrets | Secure CI credential storage → deliver via env var at runtime |
| TLS inspection proxy | Intercepts encrypted corporate traffic → "self-signed cert" error |
| OpenTelemetry | Usage and operational measurement |
| Gateway session headers | Attach stable team/cost-centre identity to traffic at scale |
| SIEM | Search, alert, and audit on telemetry |

`.env` file = local configuration, NOT an enterprise CI secret store.

### Cluster 4: Activation and Consulting Judgement

| Situation | Correct response |
|---|---|
| Developer stuck 45 min | Assess task scope + skill fit first — don't immediately intervene or escalate |
| Engagement close | Transfer reusable assets + sponsor readout + named champion. SLA is separate commercial arrangement. |
| Baseline measurement | Establishes the "before" **denominator** for ROI calculation — not success criteria (those come before kickoff) |

### Cluster 5: Configuration Asset Boundaries

| Asset | What goes in it |
|---|---|
| Slash-command Markdown + YAML | Repeatable task instructions |
| Project CLAUDE.md | Durable codebase context and conventions |
| Org instructions | Enterprise policy and safety guardrails — NOT tone/bullets/word limits |
| User settings | Personal preferences |
| managed-settings.json | Enforceable technical controls (non-overridable) |

### Cluster 6: Deployment-Path Capabilities

```
Claude for Enterprise direct → Anthropic contractual ZDR
Bedrock / Vertex             → provider-specific data handling (not Anthropic ZDR)

No Training ≠ no retention
Custom Retention ≠ ZDR
All three are separate controls
```

---

### Compact Exam Cheat Sheet

```
PERMISSIONS:   Deny → Ask → Allow

MCP:           Review process = governance throughout activation
               allowedMcpServers = approved server allowlist
               allowManagedMcpServersOnly = block self-installed
               Plugin = package + distribute MCP configs
               SCIM + RBAC = who receives access

IDENTITY:      SSO = authenticate
               forceLoginMethod = require approved login method
               forceLoginOrgUUID = require correct org
               JIT = create user at first login
               SCIM = joiner/mover/leaver lifecycle

ISOLATION:     Context isolation ≠ sandbox
               Permissions = which actions allowed
               Sandbox = what process can reach
               Dev container = stronger environmental boundary

AUTOMATION:    Hooks = block / notify / validate / log events
               Hooks do NOT select the model

SECRETS:       GitHub Actions Secret = secure storage
               Env var = runtime delivery
               .env file = local only, not CI secret store
               Never in CLI args, YAML, or CLAUDE.md

OBSERVABILITY: OTel = metrics and events
               Resource attributes = business labels (per-team)
               Gateway headers = centralized team/cost-centre attribution at scale
               SIEM = query, alert, audit

ENGAGEMENT:    Baseline = denominator for ROI (not success criteria)
               Pilot cohort = determines data quality
               Closeout = assets + sponsor readout + champion
               SLA = separate commercial arrangement

INSTRUCTIONS:  Org level = policy + guardrails (NOT tone/bullets/word limits)
               Project CLAUDE.md = codebase context
               User scope = personal preferences

DATA CONTROLS: No Training ≠ Custom Retention ≠ ZDR (3 separate controls)
               ZDR = Enterprise direct only
```

---

## Block 1 — Foundations

### Model family

| Model ID | Tier | When to pick |
|---|---|---|
| `claude-opus-4-7` | Most capable | Hard reasoning, synthesis, long-horizon agents, anything where quality dominates cost. 1M-context variant available. |
| `claude-sonnet-4-6` | Balanced | Production workhorse — most app use cases, structured analysis, tool use. |
| `claude-haiku-4-5-20251001` | Fast & cheap | High-volume extraction, classification, simple summarization, latency-sensitive UX. |

**Exam trap:** know exact strings, including Haiku's `-20251001` date suffix.

### Messages API anatomy

```python
from anthropic import Anthropic
client = Anthropic()

response = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=1024,                    # REQUIRED
    system="You are a code reviewer.",  # top-level, NOT in messages
    messages=[
        {"role": "user", "content": "Review this diff: ..."},
    ],
    temperature=1.0,                    # default 1.0; 0.0 = near-deterministic
)
print(response.content[0].text)
```

**Top 5 traps:**
1. `system` is a **top-level field**, not a message with `role: "system"` (that's OpenAI).
2. `max_tokens` is **required** — no default.
3. Messages must **alternate** user/assistant. No two same-role in a row.
4. First message must be `user`. (You CAN end with `assistant` — that's **prefill**.)
5. `content` can be a string OR a list of content blocks (`text`, `image`, `tool_use`, `tool_result`, `document`, `thinking`).

### Response shape

```python
response.content                       # list of content blocks
response.content[0].text               # text block payload
response.stop_reason                   # "end_turn" | "max_tokens" | "stop_sequence" | "tool_use" | "pause_turn"
response.stop_sequence                 # which stop string matched (if any)
response.usage.input_tokens            # non-cached input
response.usage.cache_read_input_tokens # served from cache (~10% cost)
response.usage.cache_creation_input_tokens  # written to cache (~125% cost)
response.usage.output_tokens
response.model                         # echo
response.id
```

| stop_reason | Meaning | Action |
|---|---|---|
| `end_turn` | Claude finished naturally | Done |
| `max_tokens` | Hit your output cap | Usually a bug — raise `max_tokens` |
| `stop_sequence` | Output emitted a string from `stop_sequences` | Check `response.stop_sequence` |
| `tool_use` | Claude wants to call a tool | Execute tool, return `tool_result`, loop |
| `pause_turn` | Long-running tool use paused | Resume with continuation |

### Streaming

```python
with client.messages.stream(model="claude-sonnet-4-6", max_tokens=1024,
                            messages=[{"role": "user", "content": "Hi"}]) as stream:
    for text in stream.text_stream:
        print(text, end="", flush=True)
    final = stream.get_final_message()  # full Message after stream completes
```

Raw stream events: `message_start`, `content_block_start`, `content_block_delta`, `content_block_stop`, `message_delta`, `message_stop`, plus `ping` keepalives.

### Sampling params quick ref

| Param | Range | Use |
|---|---|---|
| `temperature` | 0.0–1.0 | 0.0 = deterministic-ish; 1.0 = default; higher = more varied |
| `top_p` | 0.0–1.0 | Nucleus sampling. Use either temp OR top_p, not both. |
| `top_k` | int | Only sample from top-K tokens. Rarely needed. |
| `stop_sequences` | list[str] | Up to 4 strings that halt generation when emitted |

### Mistakes & gotchas (Block 1)

From the 2026-05-24 first-pass quiz — these are the traps that bit me. Re-read before the exam.

#### Gotcha 1 — `system` is top-level, not a message *(Q1 + Q7)*

OpenAI puts the system prompt as the first item in `messages` with `role: "system"`. **Anthropic does NOT.**

```python
# WRONG — OpenAI muscle memory
messages=[
    {"role": "system",    "content": "You are X."},  # ← invalid
    {"role": "user",      "content": "..."},
]

# CORRECT — Anthropic
system="You are X.",                                  # ← top-level
messages=[
    {"role": "user",      "content": "..."},          # ← messages starts with user
]
```

The `messages` array is a chronological transcript of human ↔ AI turns. A system instruction is metadata about the whole conversation, so it's lifted out.

**Exception:** the last message CAN be `role: "assistant"` — that's **prefill**, used to force JSON output or a specific tone. But never *start* with assistant.

#### Gotcha 2 — three cache token fields, no `cached_tokens` *(Q3)*

`cached_tokens` is an OpenAI field. Anthropic uses three explicit fields because billing differs:

| Field | What | Billing |
|---|---|---|
| `input_tokens` | Non-cached input | 1.0× |
| `cache_creation_input_tokens` | Written **into** cache on a miss | ~1.25× |
| `cache_read_input_tokens` | Served **from** cache on a hit | ~0.10× |

**Mnemonic:** creation = wrote, read = hit. Drop the word "cached_" from vocabulary.

#### Gotcha 3 — determinism is `temperature=0`, not `top_p=0` *(Q5)*

- `temperature=0` → greedy sampling (always pick highest-probability token). Near-deterministic.
- `top_p=0` is **degenerate** — "sample from top 0% of mass" is undefined. Don't use.
- Default temperature is `1.0`. Use either temperature OR top_p, never both.
- "Near"-deterministic because GPU floating-point isn't bit-exact across batches. Fine for classifiers.

#### Gotcha 4 — model IDs use dashes, Haiku has a date suffix *(Q6)*

```
claude-opus-4-7              # NOT claude-opus-4.7
claude-sonnet-4-6            # NOT claude-sonnet-4.6
claude-haiku-4-5-20251001    # NOT claude-haiku-4-5 (no date = invalid)
```

Dashes everywhere, never dots. Typos cause `404 model_not_found`, not silent fallback. The date suffix on Haiku pins to a specific snapshot — required for current Haiku.

---

## Block 2 — Prompting techniques

### XML tags

Claude's preferred structure for delimiting sections. Lowercase, descriptive names. Use whenever the prompt has more than one component.

```
<document>...</document>
<examples>
  <example><input>...</input><output>...</output></example>
</examples>
<question>...</question>
<format>...</format>
```

Why: Claude parses tags semantically — `<document>` tells it "reference, not instruction." Custom tag names are fine.

### Few-shot examples

The highest-leverage technique. **3-5 examples** in the sweet spot. Cover edge cases. The format of examples becomes the output format.

### Chain of thought — two flavors

| | Prompted CoT | Extended thinking |
|---|---|---|
| How | Add "think step-by-step" or `<thinking>` tags in prompt | `thinking={"type": "enabled", "budget_tokens": 10000}` param |
| Cost | Output tokens only | Thinking tokens (separate billing) |
| Models | Any model | Opus 4.x / Sonnet 4.x only |
| Visibility | In the prompt + response | Hidden `thinking` content block in response |

Use prompted for cheap tasks; extended for hard reasoning, agentic loops, math.

### Role assignment (system prompt)

Specific roles outperform vague ones. Use adjectives — "thorough", "skeptical", "concise" actually change behavior.

```python
system="You are a senior security engineer reviewing for OWASP Top 10. Thorough, skeptical, assumes nothing."
```

### Output format — the prefill trick

End `messages` with an `assistant` turn that starts the desired format. Claude continues from there.

```python
messages=[
    {"role": "user",      "content": "Extract name/age from: ..."},
    {"role": "assistant", "content": "{"},                           # forces JSON
]
# remember to prepend "{" back when parsing
```

Combine with `stop_sequences=["</answer>"]` for clean truncation.

### Long-context positioning

**Documents at TOP, instructions at BOTTOM.** Claude has recency bias — keep the ask fresh.

```
[system]
[<document>...long content...</document>]
[<examples>...</examples>]
[<instructions>...</instructions>]
[<question>...</question>]   ← last thing before generation
```

## FAQ — concept questions from prep

### Block 1 — Surfaces

#### Claude.ai vs Claude Code vs API — fundamentals

Mental model: the API is the engine. Claude.ai and Claude Code are products built on top of it.

```
                Anthropic API (the engine)
                          │
        ┌─────────────────┼─────────────────┐
   Claude.ai          Claude Code        Your code
   (website)            (CLI)         (Python/JS app)
```

| | Claude.ai | Claude Code | API |
|---|---|---|---|
| Surface | Web/mobile app | Terminal | Your own code |
| System prompt | Hidden (or via Projects) | `CLAUDE.md` | `system="..."` param |
| Model choice | UI dropdown | Auto/configurable | `model="..."` param |
| `max_tokens` | Hidden | Hidden | YOU set |
| Tool use | Built-in only | Built-in (Read, Edit, Bash...) | YOU define + handle |
| Files | Paperclip upload | Reads local FS | Base64 / Files API |
| Prompt caching | Automatic | Automatic | YOU control breakpoints |
| Cost | Subscription | Subscription | Pay per token |

**Why this matters for the Builder cert:** the cert tests the **API mindset**. `max_tokens`, prefill, tool use, caching — all hidden in Claude.ai/Claude Code. A "builder" drops one level down and writes code calling `client.messages.create(...)`.

Analogy from BI work: Claude.ai ≈ published Power BI report (polished UI). Claude Code ≈ Power BI Desktop (technical user). API ≈ Fabric semantic model / DAX underneath (programmatic engine).

### Block 2 — Prompting

#### What's an XML tag vs JSON?

XML = markup that wraps free-form text in named tags. JSON = structured data (keys/values/arrays).

```xml
<document>Raw text with "quotes" and newlines.</document>
```

```json
{"document": "Raw text with \"quotes\" and newlines."}
```

Use **XML for prompt input** (Claude reads it). Use **JSON for output** (your code parses it). XML wins for input because (a) no escaping required, (b) visually scannable, (c) Claude was heavily trained on it.

#### Is the XML-tags preference Claude-specific?

All major LLMs (Claude, GPT, Gemini) parse both XML and JSON. But:

| | Claude | GPT | Gemini |
|---|---|---|---|
| **Recommended structure** | XML tags | Markdown headers | Markdown/XML |
| **Specifically tuned for** | XML | Mixed | Mixed |

**Why XML wins for prompt input:**
1. **No escaping.** Wrapping `She said "hi"` in `<document>` needs zero escapes. JSON would force `\"hi\"`.
2. **Semantic boundaries.** `<document>` tells Claude "reference material, not instruction."
3. **Anthropic specifically tuned Claude on XML.** It's not just "easier to read" — it's a model-training choice.

Use XML to **wrap text input**. Use JSON to **structure data input/output**. They aren't competing — different jobs.

#### Do I have to write the "assistant" prefill every time?

Only in API code, and only once. Not in Claude.ai, not in Claude Code.

| Surface | Prefill? |
|---|---|
| Claude.ai web/app | Never — not exposed |
| Claude Code CLI | Never — not exposed |
| API | Once per request as a single line in `messages` — written once in a reusable function |

#### Do I have to upload the document for every question?

Depends on surface:

| Surface | Doc lifecycle |
|---|---|
| Claude.ai | Attach once via paperclip at start of conversation; follow-ups see it free |
| Claude Code | File lives in repo; Claude reads on demand via `Read` tool |
| API | Sent every request — UNLESS you use **prompt caching** (mark doc with cache breakpoint once → 10% cost on reads) |

The "doc top, question bottom" rule is about ORDER **within one prompt**, not how often you upload.

#### Where do I set a persona/system prompt so I don't retype it?

| Surface | Where persona lives |
|---|---|
| Claude.ai | **Projects → Custom instructions.** One project = one persona, applies to every chat in it. |
| Claude Code | **`CLAUDE.md`** in repo root. Auto-loaded every session. |
| API | The `system="..."` field in your code, written once in your client wrapper |

Good persona prompts are specific: role + behavioral adjectives + output structure.

> "You are a meticulous debugging assistant. For every code change you propose: (1) re-read affected functions, (2) state assumptions about the data, (3) list one thing that could go wrong with your fix."

Bad: "You are a helpful AI."

### Block 3 — Advanced features

#### What's a "tool" and a "cache"? (TTL, breakpoint plain English)

**Tool** = a function you let Claude call. You describe what it does + what inputs it takes. Claude itself never runs code — it requests the call, your code executes, you return the result. Examples: `get_weather`, `search_database`, `fetch_brand_pricing`.

**Cache** = saved copy of input tokens Claude already processed.

| Term | Plain English |
|---|---|
| Cache | "Don't re-process these tokens, you already saw them" |
| **TTL** (Time To Live) | How long the cache lasts before forgetting. Default 5 min, optional 1 hour |
| **Breakpoint** | A bookmark in the prompt: "everything up to here should be cached" |

Analogy: cache = Claude memorising a textbook chapter. First read = expensive. Recall = 10% cost. TTL = how long until the memory fades.

#### "Tools" on Claude desktop vs "tool use" in the API — same thing?

Same concept, different sides of the table:

| | Builder side (cert topic) | User side (Claude.ai / desktop) |
|---|---|---|
| Who configures | You write tool definitions in code | You toggle on/off in Settings |
| Examples | `get_weather()`, `query_db()` | Notion, Figma, Adobe, Amplitude |
| Who runs them | Your app | Anthropic (hidden) |

The cert wants you on the Builder side: writing definitions in code.

#### `tool_choice` — who uses `none`?

| Value | Claude can... |
|---|---|
| `auto` (default) | Use a tool OR respond with text — Claude picks |
| `any` | MUST use some tool — no plain text |
| `tool: X` | MUST use tool X specifically |
| `none` | CANNOT use any tool — text only |

**`none` is for:** the final "now write the summary" step of an agent loop where you want prose, not more tool calls. Or A/B testing same prompt with/without tools.

#### Why does Claude.ai burn capacity so fast on long chats?

Two facts:
1. Every new message reprocesses the **entire conversation history**. Message 30 reads ~30× the tokens of message 1.
2. Claude.ai uses caching internally (you don't see it), but each message still counts as 1 against your subscription's limit.

**Fix:** start new chats for new topics. Don't pile 30 unrelated requests in one thread.

(Cache pricing — 1.25× write / 0.10× read — is API-only. Claude.ai bills by message count, not tokens.)

#### Citations — relevant to me?

- **As a user of Claude.ai:** not directly. Web-search source links are managed by Anthropic, you can't configure them.
- **As a Builder:** very relevant when building RAG systems or any tool where users need to see "where exactly did this answer come from" — e.g., chat-with-our-quarterly-reports, legal review, compliance bots.

#### Batch API — did I purchase it? When use it?

Probably not separately purchased. Your account likely has:

| Thing | What it is | Cost |
|---|---|---|
| Claude Pro/Max subscription | Claude.ai web + Claude Code | $20-$200/mo |
| Claude API account | Pay-per-token, your `intel.py` uses this | per-token |
| **Batch API** | A feature OF the API, same key | per-token but **50% off** |

**Use Batch when** there's no human waiting (overnight backfills, bulk classification, large evals). **Use regular API when** latency matters (live chat, scheduled deliveries).

In your pipeline: weekly brief → regular API. Re-analyzing 26 weeks of historical brand data → Batch.

### Block 4 — Agents

#### What's a "loop"? Why is an agent a loop?

A **loop** = repeat steps until a condition is met. `while not done: do_thing()`.

**Agent = loop because Claude can't do everything in one shot.** It thinks → requests a tool → waits for result → thinks again → maybe more tools → finishes. Each iteration is one Claude API call. The loop is YOUR code's job — Claude can't loop itself.

Start: user question. End: Claude returns `stop_reason: "end_turn"`.

#### `role` field — can I set it to "head of marketing"?

**No.** Three roles only:

| | |
|---|---|
| `user` | Human side of conversation |
| `assistant` | Claude's side |
| (`system` as top-level field, not a role inside `messages`) | Conversation-wide instructions |

`role` is structural metadata (who's speaking), not persona. For personas, put it in the content:
```python
system="You're advising a Head of Marketing at Adidas. Use KPIs, skip technical jargon."
```

#### Where does `tool_use_id` come from?

**Claude generates it.** When Claude returns a `tool_use` content block, it has an `id` field like `toolu_01A9bC2dE...`. You copy it back into your `tool_result` as `tool_use_id`. This pairs "I asked for X" with "here's X's result" — critical for parallel tool calls.

#### `is_error: true` — what is it really?

Not "data missing." It means **tool execution FAILED**. The error message itself goes in `content`, and `is_error: true` flags it as a failure. Claude reads the message and decides: retry, try a different tool, ask the user, give up.

"Errors as data" = the failure is information Claude can act on, not a crash. Always wrap tools in try/except.

#### JSON-RPC, MCP, and the Power BI semantic-layer analogy

**JSON-RPC** = a standardized wire format for "call this function on a remote server." JSON message in, JSON message out.

**MCP ≈ Power BI semantic layer for LLMs:**

| | Power BI semantic layer | MCP |
|---|---|---|
| What it abstracts | Data sources | Tools/data for LLMs |
| Consumers | Power BI, Excel, Tableau (XMLA) | Claude.ai, Claude Code, Cursor, any LLM client |
| Producer writes... | One semantic model | One MCP server |
| Benefit | Decouple BI tools from raw data | Decouple LLMs from raw integrations |

Write the MCP server once; all MCP-aware clients can use it.

#### User memory vs workspace memory

| | User memory | Workspace memory |
|---|---|---|
| Scope | YOU, across all conversations/projects | One project only |
| Example | "I work at Adidas EM" | "This project is the SEA+PAC intel pipeline" |
| Where to view | Claude.ai: Settings → Personalization. API: `memory.list`/`memory.search`. Claude Code: `~/.claude/projects/<proj>/memory/` |

### Career & conceptual

#### Does prompting replace Python? (the "is the gap filled" question)

**The middle two layers compressed. The top and bottom didn't.**

```
Human judgment (what to build, what's true)     ← always human
Business logic (extract, classify, summarize)   ← NEW: prompts replaced code here
Orchestration (error handling, glue, state)     ← still code (Claude writes it)
Infrastructure (DBs, networks, APIs)            ← still engineers
```

**Tasks where prompts replaced Python:** extraction from documents, classification, summarization, analysis briefs, structured generation. Pre-LLM these needed regex + pandas + spaCy + sklearn.

**Tasks where code still wins:**
1. **Reliability/determinism** — finance, healthcare, compliance need tested deterministic logic
2. **Scale/cost** — millions of calls = real money; regex is free
3. **Speed** — API = seconds; code = microseconds
4. **Evaluation** — you still need domain expertise to recognize good output

**Career framing (for Head-of-Analytics-with-AI-tilt pitch):** the syntax barrier is gone, so domain expertise (e.g. SEA+PAC retail) gates the work, not coding ability. Compete with analysts who can't yet think in prompts/APIs, not with engineers.

---

## Block 3 — Advanced features

### Tool use — the 4-step loop

1. **Define** tools with `name`, `description`, `input_schema` (JSON Schema).
2. **Call** Claude with `tools=[...]`. If Claude wants to use one, `stop_reason="tool_use"` and content has `tool_use` block (id, name, input).
3. **Execute** the tool yourself (Claude never runs code). Get a result.
4. **Return** result as `tool_result` content block in next `user` message, referencing `tool_use_id`.

Loop until `stop_reason="end_turn"`.

```python
{"role": "user", "content": [
    {"type": "tool_result", "tool_use_id": "<id from claude>", "content": "<result>"}
]}
```

#### `tool_choice` options
| Value | Behavior |
|---|---|
| `{"type": "auto"}` (default) | Claude decides whether to use any tool |
| `{"type": "any"}` | Must use SOME tool |
| `{"type": "tool", "name": "X"}` | Must use tool X |
| `{"type": "none"}` | No tools this turn |

#### Parallel tool use
Multiple `tool_use` blocks in one response → execute all → return all `tool_result` blocks in ONE user message.

#### Tool use gotchas
- `tool_result` is a **content block** with role `user`, not a top-level role.
- `tool_use_id` must match exactly.
- Errors: return `{"type": "tool_result", "tool_use_id": "...", "content": "Error: ...", "is_error": true}`.
- Send back **full assistant content**, not just the tool_use block.

### Prompt caching

Mark a chunk with `"cache_control": {"type": "ephemeral"}`. Same prefix on next call within TTL → read at ~10% cost.

```python
system=[{
    "type": "text",
    "text": LONG_INSTRUCTIONS,
    "cache_control": {"type": "ephemeral"}            # 5 min default
    # or: "cache_control": {"type": "ephemeral", "ttl": "1h"}
}]
```

| Concern | Value |
|---|---|
| Default TTL | 5 minutes |
| Extended TTL | 1 hour (`"ttl": "1h"`) |
| Min cacheable | ~1024 tokens (Opus/Sonnet), ~2048 (Haiku) |
| Breakpoints per request | Max 4 |
| Cache key | Full prefix up to & including the breakpoint |
| Write cost | ~1.25× input |
| Read cost | ~0.10× input |
| Track hits | `response.usage.cache_read_input_tokens` |

**What to cache:** system prompt, tool defs, long documents, few-shot examples. **Not** the user's question.

### Extended thinking — beyond basics

- `thinking={"type": "enabled", "budget_tokens": N}` — N is a MAX, not a target.
- Models can think *between* tool calls in agent loops (**interleaved thinking**).
- Response content includes `thinking` blocks before text/tool_use blocks.
- Only Opus 4.x / Sonnet 4.x.

### Vision

```python
{"type": "image", "source": {
    "type": "base64",
    "media_type": "image/png",
    "data": "<base64-encoded>"
}}
```

| Constraint | Value |
|---|---|
| Formats | JPEG, PNG, GIF, WebP |
| Max size | 5 MB per image |
| Max per request | 100 images (1M context); fewer for smaller contexts |
| Optimal resolution | Long edge ≤ 1568 px |
| URL source | `{"source": {"type": "url", "url": "..."}}` also supported |

### Citations

Add `"citations": {"enabled": true}` to a `document` content block. Response text blocks get a `citations` field with char-range references back into the doc.

```python
{
    "type": "document",
    "source": {"type": "text", "media_type": "text/plain", "data": DOC},
    "citations": {"enabled": True},
}
```

### Batch API

- Endpoint: `client.messages.batches.create(requests=[...])`
- Up to **100,000 requests/batch**
- Returns within **24h** (often much faster)
- **50% discount** on tokens
- Each request needs a `custom_id` for matching results
- Use for: evals, backfills, bulk processing. NOT for low-latency.

### Files API (beta)

Upload once, reference by ID across many requests. `client.files.upload(...)` → `{"source": {"type": "file", "file_id": "..."}}`. Saves re-uploading large PDFs/images.

### Mistakes & gotchas (Block 3)

From the Block 3 first-pass quiz — these are the traps that bit me.

#### Gotcha 1 — Claude does NOT execute tools

`stop_reason: "tool_use"` means Claude *requested* a tool call. Your code runs the actual function, then sends a `tool_result` content block back in a user message. Mental anchor: Claude is a consultant on the phone — they tell you to look up the weather, you look it up, you report back.

#### Gotcha 2 — Cache works on CONTENT BLOCKS, not requests

You don't "cache a request." You plant a `cache_control: {"type": "ephemeral"}` bookmark on a specific content block. Everything from the start of the prompt up to and including that block is the cache key. Max 4 breakpoints per request.

#### Gotcha 3 — Cache is about REUSE, not size

Cache savings = (number of times the prefix repeats) × (size of cached prefix). A huge document used once saves nothing. A small system prompt reused 50 times saves a lot. The user's question is the WORST candidate — it changes every call.

#### Gotcha 4 — `budget_tokens` is a ceiling, not a target

Extended thinking uses less than the budget for easy problems. You pay for actual usage, not the cap. So set budgets generously (10000-32000 for hard reasoning) — you only spend if Claude needs it.

#### Gotcha 5 — Vision resolution caps at 1568px

Claude internally resizes images to ~1568px long edge. Anything bigger wastes bandwidth + tokens with zero quality gain. Like uploading 4K to a 1080p streaming site.

#### Gotcha 6 — Batch API is the SAME API, async + bulk

Same key, same endpoint family, different request shape. 50% discount in exchange for up to 24h latency (often much less). Use when there's no human waiting.

### Two cases from the SEA+PAC intel pipeline

#### Case 1 — Weekly Mon 3am run (current state)

7 markets × ~4 brands = ~28 calls, all with same system prompt. Sequential, ~45 min, email at 9:20am.

| Concept | Verdict | Why |
|---|---|---|
| Cache | ⚠ BAD | Same 2000-token system prompt processed 28×. Easy fix. |
| TTL | — | 5-min default would work if cache enabled (back-to-back calls) |
| Breakpoint | 💡 ADD | One breakpoint after system prompt + analysis template |
| Tool use | ✓ CORRECT | Content pre-scraped by Python — tools would be over-engineering |
| Write/read pricing | ⚠ BAD | Full price 28× today. With cache: 1.25× ×1 + 0.10× ×27 = **~15% of cost** |
| Citations | ✗ N/A | Exec HTML brief, not RAG, no source-traceability need |
| Batch API | ⚠ MARGINAL | Email goes out 6h after run — 24h Batch SLA too risky |

**One-line cache fix:** `system=[{"type": "text", "text": SYSTEM, "cache_control": {"type": "ephemeral"}}]`

#### Case 2 — Hypothetical 12-week backfill

Boss asks for last quarter's brand-pricing trend. 12 weeks × 7 markets × 4 brands ≈ 336 analyses. No one waiting in real-time. Want it tomorrow morning.

| Concept | Verdict | Why |
|---|---|---|
| Cache | ✓ STRONG WIN | One write, 335 reads |
| TTL | ✓ 1-hour | Run exceeds 5 min — use `"ttl": "1h"` |
| Breakpoint | ✓ After system + template, before per-article content | Article text stays uncached (varies) |
| Tool use | 💡 OPPORTUNITY | `fetch_article(brand, market, week)` lets Claude decide which weeks to compare |
| Write/read pricing | ✓ MASSIVE WIN | 1.25× ×1 + 0.10× ×335 ≈ 11% of full-price cost |
| Citations | ✓ STRONG WIN | "Where exactly did Adidas raise prices?" → citation points to the paragraph |
| Batch API | ✓ PERFECT FIT | Overnight, no one waiting → another **50% off** on top of cache savings |

**Cumulative savings:** Regular+no-cache (1.00×) → Regular+cache (0.15×) → **Batch+cache (0.075×, ~13× cheaper).**

### Memorization rule of thumb

| Situation | Tool |
|---|---|
| Same prompt prefix repeats > 2× within 5 min | Cache |
| Same prefix repeats across hours | Cache + 1-hour TTL |
| You wrote a Python scraper to feed Claude | Probably DON'T need tool use |
| You want Claude to dynamically decide what data to fetch | Tool use |
| "Chat with our PDFs" feature | Citations |
| Bulk run, no human waiting, OK in 24h | Batch API |
| Live chat, exec waiting | Regular API |

**Hierarchy of savings (least → most impactful):**
1. Switch model to Haiku where Sonnet/Opus is overkill
2. Add prompt caching — easy ~80% savings on repeated prefixes
3. Move bulk non-urgent work to Batch — another 50% on top

---

## Block 4 — Agents

### What IS an agent?

**Agent = a loop**, written by you, around the Messages API + tool use.

```
1. Get user goal
2. Call Claude with tools available
3. Check stop_reason:
   - "end_turn" → DONE
   - "tool_use" → run the tool, send result back → go to 2
4. Safety: bail after N iterations
```

That's the whole concept. The Agent SDK, MCP, memory tool — all extensions of this loop.

### The minimal agent loop

```python
def run_agent(user_goal, tools, max_iters=10):
    messages = [{"role": "user", "content": user_goal}]
    for _ in range(max_iters):
        r = client.messages.create(
            model="claude-sonnet-4-6",
            max_tokens=4096,
            tools=tools,
            messages=messages,
        )
        if r.stop_reason == "end_turn":
            return r
        if r.stop_reason == "tool_use":
            messages.append({"role": "assistant", "content": r.content})
            tool_results = []
            for block in r.content:
                if block.type == "tool_use":
                    result = execute_tool(block.name, block.input)
                    tool_results.append({
                        "type": "tool_result",
                        "tool_use_id": block.id,
                        "content": str(result),
                    })
            messages.append({"role": "user", "content": tool_results})
    raise Exception("Hit max iterations")
```

### Loop gotchas

1. **Always send Claude its own prior response** (the assistant message with `tool_use` blocks) when returning `tool_result`. Forgetting this confuses the model.
2. **Parallel tool_results go in ONE user message**, not multiple.
3. **`tool_use_id` must match exactly** between request and result.
4. **Errors as data**: return `is_error: True` in the tool_result, don't crash. Lets Claude decide how to recover.
5. **`pause_turn`** = long-running tool paused. Continue with partial state. Rare, but on the exam.

### Claude Agent SDK

Higher-level wrapper that writes the loop for you. Adds: loop management, tool execution + permissions, context window auto-management, error recovery, streaming events, memory integration.

```python
from claude_agent_sdk import ClaudeAgentClient
async with ClaudeAgentClient(options=...) as client:
    async for message in client.query("Help me debug this"):
        print(message)
```

Prototype → write the loop yourself. Production → use the SDK.

### MCP — Model Context Protocol

Open standard for connecting LLMs to external tools/data. Anthropic-driven, broadly adopted (Claude.ai, Claude Code, Cursor, etc.).

```
MCP Client ◄─── JSON-RPC ───► MCP Server
(Claude.ai,     (stdio or       (your tool,
 Claude Code,    HTTP+SSE)       third-party)
 your app)
```

**Three capabilities an MCP server exposes:**

| | What | Example |
|---|---|---|
| **Tools** | Functions Claude can call | `query_postgres(sql)` |
| **Resources** | Data Claude can read | A file, calendar, URL |
| **Prompts** | Reusable templates | "Code review prompt" |

**Transports:** `stdio` for local processes, `HTTP+SSE` for remote services.

**Why it matters:** before MCP, every LLM client had its own integration format. Now write a server once → all MCP clients can use it.

### Memory tool

Anthropic-managed tool giving Claude persistent memory across conversations.

| Scope | What sticks |
|---|---|
| **User memory** | Across all conversations for a user |
| **Workspace memory** | Scoped to a project |

Used via the Agent SDK. Claude autonomously calls `memory.read`, `memory.write`, `memory.search`, `memory.delete`.

**Key insight:** memory is a tool — same pattern as any other tool, not a separate API.

### Context window management for long agent runs

| Strategy | When |
|---|---|
| Prompt caching on system + tools | Always (cheapest move) |
| Truncate old turns | Recency matters more than history |
| Summarize and compress mid-run | Long-horizon agents |
| 1M context window (Opus 4.7) | When you genuinely need it; expensive |
| Extended thinking between tool calls | Heavy reasoning required |

---

## Block 5 — Claude Code CLI (slash commands & shortcuts)

The 20 commands worth keeping in muscle memory. Each Claude Code session (terminal tab, VS Code extension) is its own isolated process — there is no global "show me everything running across all my sessions" view.

### Session control
| Command | What it does |
|---|---|
| `/help` | List all slash commands |
| `/clear` | Wipe conversation, start fresh |
| `/compact` | Manually compact long context |
| `/resume` | Resume a prior session |
| `/cost` | Token usage and spend |

### Configuration
| Command | What it does |
|---|---|
| `/config` | Model, theme, settings UI |
| `/model` | Switch model mid-session (Opus ↔ Sonnet ↔ Haiku) |
| `/agents` | View/create subagent **definitions** (config view, not runtime). Reads from `~/.claude/agents/` (user) + `<project>/.claude/agents/` (project) + built-ins like `Explore`, `Plan`, `general-purpose` |
| `/mcp` | Manage MCP servers |
| `/hooks` | Manage hooks (`PreToolUse`, `Stop`, etc.) |

### Workflow
| Command | What it does |
|---|---|
| `/init` | Generate `CLAUDE.md` for current repo. **Note:** `CLAUDE.md` is NOT auto-generated per conversation — it's a persistent file checked into the repo. `/init` is the one-time scaffold; after that you edit it manually (or via the `#` prefix). |
| `/review` | **Review a PR** — multi-step review of a pull request. Pass a PR number/URL or run inside a branch; Claude inspects the diff, comments on issues, and proposes fixes. Different from `/security-review` (defensive scan) and `/ultrareview` (multi-agent cloud review, billed). |
| `/security-review` | Security audit of pending changes on the current branch |
| `/ultrareview` | Multi-agent cloud review of branch or `/ultrareview <PR#>` (user-triggered, billed) |
| `/schedule` | Create cron-style remote routines |
| `/loop 5m <cmd>` | Run a command on an interval |

### Inline prefixes (not slash commands)
| Prefix | What it does |
|---|---|
| `! <cmd>` | Run a shell command in the session — output goes into the conversation. Useful for things Claude can't run itself (e.g. `! gcloud auth login`) |
| `# <text>` | Append to memory / `CLAUDE.md` |
| `@ <path>` | Reference a file inline |

### Keyboard
- `Esc` — interrupt
- `Esc Esc` — edit your previous message
- `Shift+Tab` — toggle plan / auto-accept modes
- `Ctrl+R` — search history

### Honorable mentions
`/doctor` (diagnostics), `/ide` (VS Code link), `/bug` (report), `/pr_comments` (fetch PR comments), `/add-dir` (add another working dir), `/fast` (toggle fast mode on Opus 4.6).

### Gotchas
- **`/agents` ≠ runtime status.** It shows configured subagent definitions on disk, not what's currently executing. Same list shows regardless of what's running in another Claude Code window.
- **No cross-session dashboard.** If VS Code Claude Code is mid-task and your terminal is idle, the terminal cannot see the VS Code session's tasks or approval prompts. Approval prompts are modal *inside the session that raised them*.
- **`CLAUDE.md` is persistent, not generated per chat.** It's loaded into context at session start from disk. `/init` scaffolds it once.

---

## Block 6 — Fable 5 System Prompt: What Anthropic's Engineering Teaches You

> Source: `~/busy-brain/prompts/CLAUDE-FABLE-5.md` — 3,825 lines, leaked June 2026.
> Read this not as trivia but as a **master class in production-grade prompt engineering** from the team that built the model.

---

### 6.1 — The architecture: XML section hierarchy

Fable 5's prompt is not a wall of text. It's a **structured document** with nested XML sections. Every major behavioral domain gets its own tag:

```xml
<claude_behavior>
  <product_information>...</product_information>
  <refusal_handling>
    <critical_child_safety_instructions>...</critical_child_safety_instructions>
  </refusal_handling>
  <tone_and_formatting>
    <lists_and_bullets>...</lists_and_bullets>
  </tone_and_formatting>
  <user_wellbeing>...</user_wellbeing>
  <anthropic_reminders>...</anthropic_reminders>
  <evenhandedness>...</evenhandedness>
  <knowledge_cutoff>...</knowledge_cutoff>
</claude_behavior>

<memory_system>
  <memory_overview>...</memory_overview>
  <memory_application_instructions>...</memory_application_instructions>
  <forbidden_memory_phrases>...</forbidden_memory_phrases>
  <memory_application_examples>...</memory_application_examples>
</memory_system>
```

**What to copy:** Use XML tags to separate concerns in your own system prompts. Claude parses them reliably. Flat paragraphs break down on long prompts; tags hold structure under pressure.

---

### 6.2 — The token budget header

The very first thing in the file:

```
<budget:token_budget>
190000
</budget:token_budget>
```

Anthropic injects the remaining context budget at the top of every call. Claude reads this and adjusts response verbosity accordingly — conserving tokens as the budget shrinks.

**What to copy:** If you're building long-running agents or tools that might approach context limits, inject a `<budget:remaining>` signal at the top of each call. Let the model self-regulate length rather than having it cut off mid-task.

---

### 6.3 — Product information as grounding

The `<product_information>` section tells Claude exactly what it is, what products exist, which model strings to use, what surfaces are available (web, API, Claude Code, Claude Cowork, Chrome/Excel/Powerpoint agents). It also tells Claude what it does NOT know and instructs it to search `docs.claude.com` before answering product questions.

**Lesson:** Ground your model in its operational reality at the top of every system prompt. Don't assume it knows which surface it's on, what version it is, or what tools it has access to. State it explicitly.

**Template:**
```xml
<product_context>
  You are the [product name] assistant. You run inside [surface/app].
  You have access to: [tool list].
  You do NOT know: [what to look up instead].
  If asked about [X], search [URL] before answering.
</product_context>
```

---

### 6.4 — Formatting rules: the anti-bullet stance

One of the most surprising sections:

> *Claude writes prose without bullets, numbered lists, or excessive bolding unless the person asks for a list or ranking.*
> *Inside prose, lists read naturally as "some things include: x, y, and z" without bullets.*
> *Claude never uses bullet points when declining a task; the additional care helps soften the blow.*

**Why this matters:** Bullet points signal low-effort, robotic output. Anthropic trained Fable 5 to communicate like a knowledgeable person, not a slide deck. The default is prose; lists are opt-in.

**What to copy:** Add a `<formatting>` section to your system prompts. Be explicit about when to use lists vs prose. Default to prose for most tasks — reserve bullets for ranked comparisons or step-by-step instructions only when the user asks.

---

### 6.5 — Knowledge cutoff injection (dynamic date)

```
Claude's reliable knowledge cutoff is end of Jan 2026. Claude answers the way
a highly informed individual in Jan 2026 would if talking to someone from
Tuesday, June 09, 2026.
```

The current date is **injected dynamically** into the prompt at runtime. Claude doesn't guess the date — it's told.

**What to copy:** Always inject `today = {date}` into your system prompt at runtime, not hardcoded. For agents that need freshness, add: *"If the question could have changed since [cutoff], use web search before answering."*

```python
system = f"Today is {datetime.now().strftime('%A, %B %d, %Y')}. {rest_of_system_prompt}"
```

---

### 6.6 — Memory system: the forbidden phrases pattern

The `<forbidden_memory_phrases>` section is a masterclass in behavioral specificity. Instead of saying "don't make it weird," Anthropic lists exact phrases Claude must never say:

**Never say:**
- "I can see..." / "I notice..." / "According to..."
- "Based on what I know about you"
- "Your memories" / "Your profile" / "Your data"
- "I remember..." / "I recall..." / "From memory..."

**Why:** These phrases break the illusion that Claude naturally knows the user. They make the memory system feel surveillance-like.

**What to copy:** When you define behavioral rules, **list the exact bad phrases** alongside the rule. "Don't be robotic" is useless. "Never say 'As an AI language model'" is specific and enforceable. Your model will comply with specifics, not vibes.

---

### 6.7 — Tool schema design: description as instruction

Every tool schema in Fable 5 bakes **usage instructions into the description field**, not just what the tool does:

```yaml
fetch_sports_data:
  description: >
    Use this tool whenever you need current sports data.
    Bias towards fetching BEFORE responding — workflow:
    1) fetch score 2) fetch stats 3) THEN respond.
    Do NOT rely on memory or assume which players are in a game.
```

The description field is not a label — it's a **decision tree**. Anthropic tells Claude exactly when to call it, in what order, and what not to do instead.

**What to copy:**
```python
tools = [{
    "name": "get_pricing",
    "description": (
        "Fetch live pricing data. ALWAYS call this before answering any "
        "pricing question — never answer from memory. Call ONCE per product. "
        "Do NOT call for historical questions (use knowledge cutoff instead)."
    ),
    "input_schema": {...}
}]
```

---

### 6.8 — Anthropic reminders: mid-conversation injection

```
Anthropic may send Claude reminders or warnings when a classifier fires.
Current set: image_reminder, cyber_warning, system_warning, ethics_reminder,
ip_reminder, long_conversation_reminder.
```

Anthropic doesn't rely entirely on the initial system prompt. They inject **in-band signals** mid-conversation when classifiers fire. Claude is told to expect these and told they will never reduce its restrictions.

**What to copy for your agents:** Design your system to be able to inject mid-conversation guidance — e.g. when a user is about to hit a context limit, inject `<system:reminder>You are 80% through your context. Wrap up the current task.</system:reminder>` into the next user message.

---

### 6.9 — The wellbeing section: scope management

The `<user_wellbeing>` section runs ~800 words covering mental health, self-harm, crisis lines, and over-reliance on AI. It ends with:

> *Claude does not want to foster over-reliance on Claude. Claude never asks the person to keep talking to Claude.*

Anthropic explicitly tells its most capable model **not to be addictive**. This is a product decision with safety and legal implications.

**What to copy:** If you build any product where users might develop unhealthy engagement patterns (mental health tools, companion apps, coaching agents), add an explicit `<engagement_limits>` section. Define what the model should redirect to a human professional, and when.

---

### 6.10 — Summary: the 5 patterns worth stealing

| Pattern | One-line takeaway |
|---|---|
| XML section hierarchy | Separate concerns with tags — don't write a wall of text |
| Dynamic date + budget injection | Inject runtime state (date, token budget, user role) at call time |
| Forbidden phrases list | Specify bad outputs verbatim, not just "don't do X" |
| Tool descriptions as decision trees | Tell Claude WHEN to call, in WHAT order, and what NOT to do |
| In-band mid-conversation signals | Design for classifier-triggered injections in long agent sessions |

**The meta-lesson:** Fable 5's system prompt reads like a **product spec written for a very literal engineer**. It does not rely on inference, good faith, or vibes. Every rule is stated explicitly, with examples of what to avoid. That is the standard for production-grade prompts.

---

## Block 7 — Anthropic Partner Training: Claude Code Product Foundations

Source: Skilljar partner path *partner-badge-claude-code / product-foundations*. Only the CCAR-F-relevant parts captured here (the deployment-path material is partner-sales, not on the exam). Crawled from the page summary — video/slide depth is behind the partner login, so this is orientation-level content only.

### 7.1 — What Claude Code is (relevant to D3)

- Runs **in the terminal, not as an IDE plugin**.
- Works **agentically**: reads files, writes code, runs commands, works through multi-step tasks.
- That agentic posture is what shapes how work gets **scoped and configured** — the reason `.claude/` config, hooks, plan mode, and CLAUDE.md matter.

### 7.2 — Model selection (relevant to D1 architecture choices)

- Three models weighed on **cost, speed, reasoning depth**: Haiku, Sonnet, Opus.
- **Most deployments start with Sonnet — but the recommendation needs a reason behind it.** (Exam-style framing: never pick a model by default; justify against the workload.)
- Selection depends on the **given workload**, not a fixed rule.

### 7.3 — Course shape (context only)

- ~29 min instruction + ~15 min practice.
- Assessment is **scenario-based**: three client profiles, pick the right model + deployment combo. Confirms Anthropic's whole training ecosystem leans scenario/judgment, not fact recall — same as CCAR-F.

### 7.4 — Setup sequencing principle (judgment habit, from the assessment)

- Sequence setup by **when it's actually needed**; don't front-load deployment-specific config.
- Pre-session setup: authentication, proxy routing, TLS certificates, auto-update governance. *(These are partner/IT-admin concerns — **not CCAR-F testable**.)*
- Bedrock/cloud routing: only relevant if the client runs through that path — **not CCAR-F**.
- **Turn limits come later**, once developers are active and you need cost controls. *(This part — cost/latency guardrails — does touch D1/D5.)*

### 7.5 — Installation & Environments lesson (course 2)

Source: Skilljar path *installation-and-environments/486592*. CCAR-F-relevant items only; the corporate proxy/cert/fleet material is partner-deployment, not exam.

- **Cross-platform CLI**: macOS, Linux, Windows (native path **or** WSL). Context only.
- **IDE integrations**: VS Code and JetBrains — relevant to D3 (Claude Code runs in-editor as well as terminal).
- **Headless / non-interactive mode** (D3, exam-relevant): for CI pipelines and automated scripts — this is the `-p`/`--print` + `--output-format stream-json` surface. API-key distribution for GitHub Actions covered here.
- **Dev containers / sandboxed execution**: isolation built into the workflow for teams that need it — touches permissions/sandboxing.
- **settings.json + container spec**: the practice deliverable is an "Installation Configuration Pack" (settings file + container spec) as the IT handoff checklist. `settings.json` is a real D3 config surface; the checklist framing is partner-only.
- **Partner-only (skip for exam)**: corporate proxy + certificate handling, Windows-fleet management decisions.

### 7.6 — Headless CI flags ⭐ EXAM-RELEVANT (D3 + D4)

The single most testable item from Course 2. Scenario: *"Claude Code reviews every PR and outputs structured JSON for a security dashboard — what flags?"*

**Correct combo = `-p` + `--output-format json` + schema described in the prompt.** Each piece does a distinct job:

| Piece | Job |
|---|---|
| `-p` (`--print`) | **Non-interactive** execution — runs without waiting for input |
| `--output-format json` | Emit **JSON, not prose** |
| Schema **in the prompt text** | Defines the expected fields/types/nesting — there is no magic `--json-schema` flag that does this |

Key traps:
- `-p` **alone** → does *not* set output format. Wrong.
- `--output-format json` **alone, no schema in prompt** → JSON shape is **undefined**; the dashboard won't know what to parse. Wrong.
- A schema flag by itself is **not** how you shape output — structure goes in the prompt.
- `--allowedTools` restricts tools; it does **not** produce structured output. Wrong for this ask.
- **Production caveat**: schema-in-prompt shapes output but doesn't guarantee it — build **validation + retry** logic; never assume the shape always matches. (Mirrors the exam rule: *schema compliance ≠ guaranteed, and ≠ semantic correctness*.)

Auth in CI is a **secrets-management** question, not a Claude Code one: headless auths via `ANTHROPIC_API_KEY` (no browser/interactive login). GitHub Actions → repo/org secret referenced as `${{ secrets.ANTHROPIC_API_KEY }}`; GitLab → CI/CD variables; Jenkins → credentials store.

Output-format values seen: `--output-format json` (structured), `--output-format text` (plain). Pipe-in pattern: `echo "What does this function do?" | claude -p --stdin --output-format text`. Common pipe-in sources for pipelines: `git log`, test output, build artifacts.

Container/CI handoff notes (partner-artifact, context only): devcontainer feature reference + version-pinning, an **override to disable automatic updates** for controlled update cycles, and the CI path (GitHub Actions trigger, workflow file location, `@claude` command pattern to invoke from a PR).

### 7.7 — Deployment Architecture (Course 6) ⚠️ mostly NOT CCAR-F

This whole course is **partner-sales / deployment-decision** methodology (billing routes, procurement, cloud commitments, credibility-meter sims). **Skip for exam study.** Only three facts transfer:

- **Pin model versions in managed settings.** Unpinned aliases resolve to defaults that can lag new releases or break users when a model isn't enabled in their account. *(Real config discipline — D3-adjacent; same spirit as knowing exact model strings.)*
- **Zero Data Retention (ZDR) = Claude for Enterprise (direct) only.** No cloud path (Bedrock/Vertex/Foundry) is ZDR-eligible. *(Data-governance fact → D5/security.)*
- **Microsoft Foundry routes to Anthropic-operated infra**, unlike Bedrock and Vertex which keep traffic in the client's own tenancy — a data-residency nuance.
- **Cloud-path parity gaps** — 6-item map of what you *lose* going Bedrock/Vertex/Foundry vs Enterprise direct (Lesson 3.2):

| # | Gap | Scope | Note |
|---|---|---|---|
| 1 | **WebSearch unavailable** | Bedrock only | Built-in WebSearch tool doesn't work; needs approved MCP alternative |
| 2 | **No bundled Claude on the web** | All cloud paths | Only Teams + Enterprise direct include the chat surface. Stakeholders have no demo UI unless bought separately |
| 3 | **Anthropic ZDR does not apply** | All cloud paths | Retention follows the cloud provider's policies (AWS/GCP/Azure), *not* Anthropic. Frame as "different control, not absent control" |
| 4 | **Client owns model version pinning** | All cloud paths | Aliases like `sonnet` resolve to defaults that can lag or point at un-enabled models. **Background tasks default to primary model, not cheaper Haiku** — pin explicitly in shared settings |
| 5 | **Telemetry defaults to off** | All cloud paths | Anthropic metrics, error reporting, and `/feedback` submission are disabled. `/feedback` writes a **local bundle** instead. Need OTel or a gateway for CoE adoption metrics |
| 6 | **Vertex fine print** | Vertex only | Model Garden approval 24–48h · MCP tool search off by default (large tool catalogs load upfront if left unconfigured) · prompt caching availability varies by region — cache counts at zero → check region |

Exam-portable pieces of this map: **ZDR = Enterprise-direct only** (D5) · **pin your own model versions on cloud paths** (D3-adjacent, background tasks default to primary not Haiku is a cost trap) · **`/feedback` writes local bundle when telemetry is off** (D5 observability nuance) · **MCP tool search off by default on Vertex** (D2 detail). Rest is partner-comms.

### 7.8 — Managed settings & corporate network (Course 6, Lesson 3.3)

Most of the lesson is IT-admin (proxy env vars, MDM via Jamf/Kandji, TLS-inspecting proxies like Zscaler/Netskope). **Five facts transfer to the exam:**

1. **Managed settings hierarchy** ⭐ (D3, real exam material). `managed-settings.json` sits at the **top of the Claude Code settings stack — above user and project settings.** Rules here **cannot be overridden by individual developers.** Used to lock permissions, enforce allowed MCP servers, require SSO login, pin version floors across the org. *(This confirms the exam's settings-precedence rule: Enterprise/managed > Personal > Project > Plugin.)*

2. **Three managed-settings delivery paths** (D3): (a) **server-managed** via Anthropic admin console — **Enterprise only**; (b) **MDM / OS-level** — plist on macOS or registry on Windows, deployed via Jamf, Kandji, etc.; (c) **file-based** — write `managed-settings.json` directly to the OS system directory. All three require admin rights (the point).

3. **`api.anthropic.com` is required on EVERY deployment path** — including Bedrock/Vertex/Foundry — because it's the **domain safety check** for the built-in **WebFetch** tool. Block it on Bedrock and WebFetch fails silently even though model traffic works fine. Preflight can be disabled via settings if the client insists. Subtle but exam-flavored.

4. **Never disable TLS verification** — `NODE_TLS_REJECT_UNAUTHORIZED=0` is the wrong fix, always. For TLS-inspecting corporate proxies (Zscaler, Netskope), point **`NODE_EXTRA_CA_CERTS`** at the corporate root CA to trust the re-signed traffic explicitly. Turning verification off fails the client's own security review. D5 discipline.

5. **`/status`** inside Claude Code verifies the final network / trust posture — useful slash command to know exists.

**Architectural constraints that force the LLM gateway pattern** (Lesson 3.4 territory): **SOCKS proxies are not supported** by Claude Code; **NTLM/Kerberos authentication** requires an LLM gateway because Claude Code can't speak either protocol directly. Both are common enterprise stacks → gateway is the answer.

**Sim result — Halvern Bank 7/8** (path 1C→2B→3B→4A). Only lost point: chose hotspot-isolation before calling the network team on Decision 1 — debrief called it "defensible, not wrong." Takeaway: in a live install clinic, **call the network team first**; hotspot-testing is fine instinct but slower than just asking the two questions that matter (is there a proxy? is TLS inspection on?).

Reference-only (the four paths, don't memorize for exam): **Enterprise direct** (Anthropic default; seat-based, SSO/domain capture, RBAC, compliance API, bundles Claude web, only ZDR path) · **Amazon Bedrock** (in-AWS, PAYG, IAM auth, CloudTrail audit, Bedrock Guardrails) · **Google Vertex AI** (in-GCP, ADC/IAM auth, Cloud Audit Logs, Model Garden access takes 24–48h to approve) · **Microsoft Foundry** (Azure, Entra ID/RBAC, Azure Monitor, but routes to Anthropic infra). Path is driven by the client's cloud commitments + compliance posture; it's a pre-kickoff (Day -14) one-way-door decision. All partner-context, not exam.

### 7.9 — LLM gateway pattern (Course 6, Lesson 3.4) ⭐ higher CCAR-F yield

The session-header content is the exam-star of this lesson — connects directly to D1 multi-agent tracking and D5 observability.

**Proxy vs Gateway** (D3 architectural distinction — memorize the one-liner):

| | Proxy | Gateway |
|---|---|---|
| Layer | Network perimeter | Application (understands model traffic) |
| Sees | Packets | Parsed requests |
| Does | Forwards, firewalls, TLS, egress | Auth, attribution, budgets, routing, logging |
| Owner | Network/security team | Platform team |

**One-liner:** *"The proxy gets traffic out of the building. The gateway governs what happens to it."*

**When to recommend a gateway:** more than one team, chargeback requirement, or multi-cloud routing — recommend **before the first invoice**, not after.

**Session headers** ⭐⭐ (D1 + D5, real exam value). Claude Code **automatically** attaches three headers on every request — no config, no code required:

| Header | Level | Purpose |
|---|---|---|
| `X-Claude-Code-Session-Id` | Session | Aggregates all requests in one Claude Code session |
| `X-Claude-Code-Agent-Id` | Subagent | Attributes cost to individual agent threads within the session |
| `X-Claude-Code-Parent-Agent-Id` | Subagent → parent | Links subagent to its parent → **full nested agent attribution** — a session that spawns 5 subagents still rolls up cleanly |

Why this matters for D1: the parent-child ID pattern is how the exam's coordinator-worker (hub-and-spoke) architecture stays *observable* end-to-end. Gateway reads these headers **without parsing request bodies** — clean separation between routing and content.

**Gateway configuration** (D3, concept-level — env-var names are IT-admin but the *pattern* is exam-relevant): identical across paths, only variable names change.

- **Anthropic API path:** `ANTHROPIC_BASE_URL` + `ANTHROPIC_AUTH_TOKEN`
- **Bedrock behind gateway:** `CLAUDE_CODE_USE_BEDROCK=1` + `ANTHROPIC_BEDROCK_BASE_URL` + `CLAUDE_CODE_SKIP_BEDROCK_AUTH=1`
- **Vertex behind gateway:** `CLAUDE_CODE_USE_VERTEX=1` + `ANTHROPIC_VERTEX_BASE_URL` + `CLAUDE_CODE_SKIP_VERTEX_AUTH=1`
- **Skip-auth flag = the centralized-auth payoff in code.** Claude Code stops signing requests because the gateway injects provider credentials server-side.
- **Rotating per-user tokens:** `apiKeyHelper` in settings runs a script that fetches from the client's vault (real settings key, D3-testable).

**Gateway gotcha** (D3, exam-flavored): the gateway **MUST forward `anthropic-beta` and `anthropic-version` headers intact**. A gateway that strips them **silently degrades Claude Code features** — the failure looks like a product bug until someone inspects traffic. Set as a **pilot go/no-go acceptance criterion** for the gateway team.

**LiteLLM** is Anthropic's reference gateway implementation — supports both Anthropic Messages and OpenAI-compatible pass-through, so one gateway can serve both workflows. *Security note (real-world, not exam): LiteLLM PyPI **1.82.7 and 1.82.8 were compromised** with credential-stealing malware — verify version against Anthropic's LLM gateway docs before any client deployment.*

### 7.10 — Security questionnaire answers (Course 6, Lesson 3.5)

Partner-comms wrapper around real D5 content. Exam-transferable pieces:

**Training answer** (D5): "**No, unless you explicitly opt in.**" Anthropic does not train generative models on prompts/code sent to Claude Code under commercial terms (Team, Enterprise, API, all cloud paths). **One exception: Development Partner Program** — admin-level opt-in, actively joined, **not available on Bedrock or Vertex**. Say the qualified "no," not "no, never" — half-answers get fact-checked.

**Local transcript caching** ⭐ (D5, testable, endpoint-security fact). Claude Code **caches session transcripts locally, in plaintext, under the user's home directory, configurable via settings**. This is *why* Claude Code sessions resume after the terminal closes — they aren't ephemeral. The exam-flavored trap: "ephemeral" is a demonstrably wrong answer to any retention question.

**ZDR precise scope** ⭐⭐ (D5, the highest-yield item in Course 6):

- **Enabled per organization** by Anthropic account team **after eligibility review**. **Not standard Enterprise by default. Not on cloud paths.** Each new org under the same account needs its own enablement — bites multi-org rollouts.
- **Covers**: Claude Code inference — prompts + model responses processed in real time, **not stored after the response returns**, regardless of model.
- **Does NOT cover**: claude.ai chat, Cowork, admin metadata (seat assignments), anything third-party MCP servers process.
- **Disables outright** (require server-side storage): **Claude Code on the web**, remote sessions from the desktop app, `/feedback`.
- **Flagged sessions**: can still be **retained up to 2 years** under the usage policy (abuse-handling exception).
- **Analytics under ZDR**: shows **usage metrics but NOT contribution metrics** — design the Day 30 scorecard around what will actually be measurable.
- **Exception path in the law**: "except where law or abuse-handling requires it" — real caveat, useful to remember.

**Encryption by path** (D5 reference):

| Path | At-rest | Notes |
|---|---|---|
| Anthropic direct | AES-256 | ZDR available (per-org enablement) |
| Bedrock | AES-256 (AWS-managed) | Customer-managed via KMS optional |
| Vertex | Google-managed default | CMEK optional |
| Foundry | Azure-native billing/Entra/RBAC | **Routes to Anthropic infra** — data-residency gotcha (already in 7.7) |

**Certifications** (reference only — all self-serve at `trust.anthropic.com`): SOC 2 Type 2 · ISO 27001:2022 · ISO/IEC 27017 (cloud security) · ISO/IEC 27018 (cloud privacy) · **ISO/IEC 42001 (AI management systems)** · CSA STAR Level 2 · HIPAA with BAA · GDPR · NIST 800-171 attestation · **FedRAMP High via Claude for Government** · annual third-party pen-test summaries. Memorizing the list is optional; knowing it's downloadable same-day is not.

**Working rule** (partner-comms, not exam): answer from citable facts, name the one thing you'll verify, never improvise a guarantee. "I'll confirm the region commitment" beats a wrong yes.

**Sim result — Corvane Health 7/10** (path 1A/2C/3B/4A/5A):
- Q2 (-2): picked "sessions ephemeral" — Correct: 30-day server-side + **local plaintext transcripts on laptops**. Real D5 gap → captured above.
- Q4 (-1): picked "broadly yes" on Foundry-in-Azure-tenancy — Correct: **"No, Foundry routes to Anthropic infrastructure."** You had this in 7.7 since Lesson 3.1 — **recall failure**, not knowledge gap. Re-read your own notes before capstone.
- The Q4 miss is the more actionable one: knowing the fact isn't enough if you can't retrieve it under scenario pressure. **Practice active recall on 7.7 and 7.10 before Course 3.**

---

## Block 8 — Preamble control: system prompt vs assistant prefill (D4)

Foundational prompt-engineering. Preamble = the "Sure!", "Of course!", "Here's what I found:" openers Claude adds before the actual answer. Great for chat UX; **breaks structured output** (parsers fail when the first char is `S` not `{`).

**Why it happens:** RLHF training rewards polite, conversational tone. Preamble is a side effect of that training, not an intentional feature. Two techniques override it.

### 8.1 — System-prompt instruction (soft / instruction-following)

```python
client.messages.create(
    model="claude-sonnet-4-6",
    system="Respond ONLY with valid JSON. No preamble, no markdown, no explanations.",
    messages=[{"role": "user", "content": "Rate Inception 1-10 as JSON."}],
    max_tokens=100,
)
```

- **Mechanism:** Claude complies with the instruction.
- **Reliability:** ~95%. Occasionally slips → `Here's the rating:\n{"rating": 9}`.
- **Best for:** flexible style rules ("no markdown", "one paragraph", "British English").

### 8.2 — Assistant prefill (hard / architectural)

```python
messages=[
    {"role": "user", "content": "Rate Inception 1-10 as JSON."},
    {"role": "assistant", "content": "{"},   # ← you write this
]
```

- **Mechanism:** You physically write the first tokens. Claude's next token *must* follow your prefill — architecturally cannot back up and add "Sure!" before your `{`.
- **Reliability:** ~100% for the prefilled characters.
- **Best for:** bulletproof openings (JSON `{`, XML `<answer>`, forced format like `Rating:`).
- **Gotcha:** you must **concatenate** the prefill back onto the response yourself → `"{" + response`.
- **Legal only** if the *last* message is `role:'assistant'`. Starting a fresh conversation on assistant → error.

### 8.3 — Difference table

| | System instruction | Assistant prefill |
|---|---|---|
| Mechanism | Soft (obey request) | Hard (architectural) |
| Reliability | ~95% | ~100% for opening chars |
| Flexibility | Any style rule | Only guarantees opening |
| Downside | Occasional slip | Must re-attach prefill to response |
| Position | `system` param | Last message with `role:'assistant'` |

### 8.4 — Rule of thumb

- Need bulletproof opening character (JSON, XML)? → **prefill**.
- Need flexible style rules ("no markdown, one paragraph")? → **system instruction**.
- Production JSON at scale? → **both together**, plus validate + retry.

### 8.5 — Modern path (Claude 4.6+)

- **`output_config: { format: "json" }`** — first-class API parameter that guarantees JSON output. Replacing prefill for JSON use-cases specifically. Prefill is now considered **legacy for JSON** on 4.6+ family.
- Prefill still valid and useful for **non-JSON** forced openings (`<answer>`, `Rating:`, `- `, section headers).
- Forced tool call is the other modern route to guaranteed structured output.

### 8.6 — Exam links

- Block 13 Q3 (Claude vs OpenAI, `response_format` migration): correct answer combines **system instruction + prefill with `{`** — same two techniques.
- Block 14 Q6 (prefill mechanics): prefill = Claude **continues from** your tokens, does **not repeat** them.
- Anti-pattern: relying on system instruction alone for JSON in production → occasional preamble slip → parser breaks → no retry logic → silent bad data.

---

## Block 9 — Claude Code configuration scopes ⭐⭐ (D3 core, 20% of exam)

Source: Partner Course 3 (Configuration & Customization), Lesson 1. This is the D3 spine — memorize scope, path, precedence, and the permission merge exception.

### 9.1 — The four scopes at a glance

| Scope | Location | Audience | Priority in stack |
|---|---|---|---|
| **Managed** | macOS `/Library/Application Support/ClaudeCode/` · Linux `/etc/claude-code/` | Every session on the machine; deployed by IT via MDM/GPO | **Highest — cannot be overridden** |
| **Local** | `.claude/settings.local.json` in the repo | Only you, only this repo. **Git-ignored automatically** | Above project |
| **Project** | `.claude/settings.json` in the repo | Everyone on the repo. **Committed to git** | Below local |
| **User** | `~/.claude/settings.json` | You, across all projects | **Lowest — last resort** |

### 9.2 — Precedence chain (top wins; Claude walks top-to-bottom, takes first value)

1. **Managed** — system-level, MDM/IT-deployed, non-negotiable
2. **CLI flags** (`--allowedTools`, `--model`) — session-level overrides, **not persisted**
3. **Local** — personal project override (`.claude/settings.local.json`)
4. **Project** — shared team baseline (`.claude/settings.json`)
5. **User** — personal fallback across all projects (`~/.claude/settings.json`)

Rule of thumb: **Managed can't be overridden. User is the last resort.**

### 9.3 — Permission merge exception ⭐ (the trap-topic)

Allow and deny rule lists **MERGE across scopes**, not override. A developer's local allow rule **adds to** the project's list — it doesn't replace it.

Critical consequence: a developer can **expand** their own permissions locally, but **cannot remove a deny rule** set at project or managed scope. This is why Managed is the enforcement layer for hard security policies (block `curl`, deny risky tools, require SSO).

### 9.4 — Decision heuristic

*Scope is an ownership question before it's a technical one.* Three questions pick the scope automatically:

1. Who **controls** this setting?
2. Who should it **affect**?
3. Can they **override** it?

### 9.5 — Common scenarios → correct scope

| Setting / requirement | Right scope | Why |
|---|---|---|
| Block `curl` org-wide, must survive uninstall | **Managed** | Only layer devs can't override; MDM survives reinstall |
| Personal model preference | **User** | Follows you across all projects, isolated to you |
| Team pre-approves `docker run` | **Project** | Ships with repo, applies to every clone, visible in code review |
| Sandbox URLs, test creds, experiments not ready to share | **Local** | Git-ignored, private to you in this repo |
| Approved MCP servers, hooks, deny lists for the team | **Project** | Committed team baseline |
| Client compliance requirements | **Managed** | Non-negotiable enforcement |

### 9.6 — Path-to-scope map (memorize — exam distractors mislabel these)

- `/Library/Application Support/ClaudeCode/` or `/etc/claude-code/` → **Managed**
- `.claude/settings.local.json` (in-repo, git-ignored) → **Local**
- `.claude/settings.json` (in-repo, committed) → **Project**
- `~/.claude/settings.json` (home dir) → **User**

**Common trap**: distractor labels `~/.claude/` as "Local scope" — it's not, it's **User** scope. The word "local" ≠ the User path. Any option that pairs `~/.claude/` with the label "Local" is a decoy.

### 9.7 — Sim: Meridian Rollout 4/6 (path 1A/2C/3A)

- **Q1** — Block `curl` org-wide, must survive reinstall → ✓ **Managed** +2.
- **Q2** — Developer's personal model preference → ❌ picked Project (visible to whole team). Correct: **User** scope. Personal preferences travel across your projects, isolated to you.
    - Root cause: momentum from Q1's "IT enforcement" thinking → defaulted to team-visible scope when the scenario needed personal isolation. Also fell for the trap in 9.6 (option A labeled `~/.claude/` as "Local").
- **Q3** — Team pre-approve `docker run` → ✓ **Project** +2.

**Study tip:** when you read a scenario, name the scope from the *audience*, not from the *action*.
- "Every developer" or "must survive uninstall" → Managed.
- "Just me, this repo" → Local.
- "Whole team, in this repo" → Project.
- "Just me, all my repos" → User.

---

## Block 10 — CLAUDE.md memory hierarchy ⭐⭐ (D3 core)

Source: Partner Course 3 (Configuration & Customization), Lesson 2. Twin of Block 9 — scope + CLAUDE.md are the D3 exam pair.

### 10.1 — Five CLAUDE.md scopes (concatenate, don't override)

| Scope | Location | Behavior |
|---|---|---|
| **Managed Policy** | macOS `/Library/Application Support/ClaudeCode/CLAUDE.md` (Linux equivalent) | Org-wide; every session on machine; **cannot be excluded by developers** |
| **User** | `~/.claude/CLAUDE.md` | Personal defaults across all projects |
| **Project** | `./CLAUDE.md` or `./.claude/CLAUDE.md` | Team-shared, committed to git — the most important one |
| **Local** | `./CLAUDE.local.md` | Personal notes for this repo; **add to `.gitignore`** |
| **Subdirectory** | Any `CLAUDE.md` in a subdirectory | **Loads on demand** when Claude reads files in that dir (NOT at session start) |

**Critical distinction from Block 9 settings scopes**: CLAUDE.md files **CONCATENATE** — they don't override. Claude reads all of them, broadest to most specific. Later entries layer *on top of* earlier ones rather than replacing them.

### 10.2 — CLAUDE.md is context, NOT enforcement ⭐⭐ (highest-yield trap-topic)

CLAUDE.md content is **loaded as context, not enforced configuration.** Claude reads it and *tries* to follow it, but there's no guarantee — especially for vague or conflicting instructions.

For **hard enforcement**, use:
- **Hooks** — shell commands run at fixed lifecycle events (PreToolUse, etc.)
- **Managed settings** — applied before Claude ever runs

Rule of thumb (exam heuristic):
- Behavior shaping / conventions → **CLAUDE.md**
- Non-negotiable enforcement → **hooks** or **managed settings**

### 10.3 — Writing rules that actually work

- **Specific beats vague, always.** "Use 2-space indentation. Run `npm test` before commit." > "Format code properly."
- **Target < 200 lines per file** — longer files degrade adherence and consume more context.
- **Use `@path/to/file` syntax** to reference existing docs. Imported file loads at session start alongside the CLAUDE.md that references it. **Signal over volume.**
- **Pruning rule**: if Claude does it right without the instruction, delete the instruction.
- **"What NOT to do" sections** — explicit prohibitions are more reliable than hoping Claude infers from the codebase.

### 10.4 — Operations to know

- **`/init`** bootstraps a CLAUDE.md by analyzing the codebase (build commands, conventions, structure). **Safe to re-run**: on existing CLAUDE.md, it **suggests improvements, doesn't overwrite**.
- **`claudeMdExcludes`** in local settings — skips noisy CLAUDE.md files from other teams. **Works from user/project/local scope, but NOT from managed policy.** Managed policy CLAUDE.md cannot be excluded by design.

### 10.5 — Monorepo pattern (subdirectory loading)

- **Root CLAUDE.md** → loads every session (system overview, team structure, strategy).
- **Service-boundary CLAUDE.md** (`frontend/`, `backend/`, `test-cases/`) → loads **on demand** only when Claude touches files in that directory.
- Keeps initial context lean; scales to enterprise monorepos.

### 10.6 — True/False traps (exam-flavored misconceptions — all four FALSE)

1. "CLAUDE.md instructions are enforced." → **False.** Context, not enforcement. Use hooks for hard rules.
2. "Project CLAUDE.md is right for personal sandbox URLs." → **False.** That's `CLAUDE.local.md` (git-ignored).
3. "Running `/init` overwrites existing CLAUDE.md." → **False.** It suggests improvements.
4. "Developers can exclude a managed CLAUDE.md via `claudeMdExcludes`." → **False.** Managed policy cannot be excluded.

### 10.7 — Content → scope mapping

| Content | File |
|---|---|
| Org-wide policy (compliance, security norms) | **Managed** CLAUDE.md |
| Personal coding style / defaults across all projects | **User** CLAUDE.md |
| Build commands, arch decisions, coding standards for this repo | **Project** CLAUDE.md |
| Personal sandbox URLs, test creds, uncommitted notes | **Local** CLAUDE.md (`CLAUDE.local.md`) |
| Module-specific context (frontend/, backend/, tests/) | **Subdirectory** CLAUDE.md |

### 10.8 — Sim: Whitmore Group 6/6 (path 1B/2B/3A)

- **Q1** (60-page architecture log): **@-reference** the doc, don't paste — signal over volume. ✓
- **Q2** (deprecated ORM pattern keeps recurring): add a **"What NOT to do"** entry to CLAUDE.md. Explicit prohibitions > hoping Claude infers. ✓
- **Q3** (personal preferences bloating repo CLAUDE.md): move to **User-level** `~/.claude/CLAUDE.md`. Repo CLAUDE.md is for the project; personal follows you across projects. ✓

Debrief: *"precision instrument — curated signal, not documentation storage."* That's the mental model for every CLAUDE.md decision on the exam.

---

## Block 11 — settings.json anatomy & permission evaluation ⭐ (D3 core)

Source: Partner Course 3 (Configuration & Customization), Lesson 3. Builds on Block 9 with the concrete file shape and — new — the **permissions evaluation order**.

### 11.1 — settings.json vs settings.local.json

Same JSON format, opposite purposes. Both live in `.claude/` of the project.

| | `.claude/settings.json` (shared) | `.claude/settings.local.json` (personal) |
|---|---|---|
| Committed to git? | **Yes** — team baseline | **No** — gitignored automatically when Claude Code creates it |
| Audience | Every developer who clones the repo | Just you, in this repo |
| Belongs here | Permission allow/deny rules · **Hook definitions** · Approved MCP server configs · Company announcements | Personal permission-mode preferences · Experimental config you're testing · Machine-specific tool paths · `claudeMdExcludes` for other teams' noise |

### 11.2 — Permissions evaluation order ⭐ (memorize — exam-testable)

Permission rules follow a **fixed** evaluation order, and they **merge across scopes** (see 9.3) rather than override. Order:

1. **Deny** — evaluated first. If any deny rule matches → **blocked**, regardless of what allow rules say. Use for sensitive files (`Read(./.env)`) and risky commands (`Bash(curl *)`).
2. **Ask** — evaluated next. Matching rule → **prompts for confirmation**. Use for potentially risky ops that need human sign-off (`Bash(git push *)`).
3. **Allow** — evaluated next. Matching rule → **proceeds without prompt**. Use for safe, frequent commands (`Bash(npm run test *)`).
4. **Default: ask** — no rule matched → Claude asks. Safe default: unknown tool use requires human approval.

**Rule of thumb**: deny beats allow, always. A deny in Managed scope cannot be un-denied by any local allow rule (9.3 merge exception).

### 11.3 — Sample project `settings.json` (memorize the shape)

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "permissions": {
    "allow": [
      "Bash(npm run lint)",
      "Bash(npm run test *)",
      "Bash(git status)",
      "Bash(git log *)"
    ],
    "deny": [
      "Bash(curl *)",
      "Read(./.env)",
      "Read(./.env.*)",
      "Read(./secrets/**)"
    ]
  },
  "companyAnnouncements": [
    "Review our coding guidelines at docs.acme.com/claude"
  ]
}
```

- **`$schema` line** enables autocomplete + inline validation in VS Code/Cursor. Include it in every project settings file.
- **Rule syntax**: `Tool(pattern)` — e.g. `Bash(pattern)`, `Read(path)`, `WebFetch(domain:host)`. Wildcards `*` and `**` supported.

### 11.4 — What NEVER goes in shared settings.json ⭐ (trap-topic)

- **Model preference** → belongs in **User** scope (`~/.claude/settings.json`) — travels across all your projects.
- **Environment variables with credentials** → never in a committed file; use env or `apiKeyHelper` from a vault (see 7.9).
- **`defaultMode` override** → belongs in the developer's **Local** file (`settings.local.json`).

### 11.5 — Sim: Apex Logistics 5/6 (path 1A/2B/3A)

- **Q1** (block `WebFetch(domain:internal-ledger.apex.com)` **across every engineer's machine**, not just the platform repo): ❌ picked Project deny (defensible +1). Correct: **Managed policy via IT**. Project scope only protects *this repo*; engineers working elsewhere lose the protection.
- **Q2** (test new internal MCP server before recommending): ✓ **Local** (gitignored, personal). +2.
- **Q3** (team agrees to pre-approve `Bash(docker compose up *)`): ✓ **Project** (committed, applies to every clone). +2.

**Pattern flag — third recall failure in a row on Managed-vs-Project.** Corvane Q4 (Foundry-in-Azure), Meridian Q2 (User vs Project), now Apex Q1 (cross-machine). The knowledge exists in Block 9.6 — the retrieval doesn't. **Active-recall drill before next study block:** cover the notes, answer aloud:
- *"Cross-machine, must survive uninstall → ?"* → Managed
- *"Just me, all my projects → ?"* → User
- *"Team baseline in this repo → ?"* → Project
- *"Just me, this repo → ?"* → Local

Ten reps and it sticks.

---

## Block 12 — Slash commands & output styles (D3, Course 3 Lessons 4–5)

### 12.1 — Custom slash commands (Lesson 4)

Any `.md` file in `.claude/commands/` (project) or `~/.claude/commands/` (user) becomes a slash command. **No registration or restart** — Claude discovers new command files automatically.

- **Filename** → command name. `review-pr.md` → `/review-pr`.
- **Nested folders** → namespace with `:`. `security/audit.md` → `/security:audit`.
- **YAML frontmatter** (optional):
  - `description` — shown in the command picker
  - `allowed-tools` — restrict tool use for this command (e.g. `Read, Bash(git *)`)
- **`$ARGUMENTS`** placeholder — substituted with text after invocation. `/review-pr 847` → `$ARGUMENTS` = `847`.

**Example — the shape the exam expects:**

```markdown
---
description: Review a pull request against the security checklist
allowed-tools: Read, Bash(git *)
---

## PR Review: $ARGUMENTS

You are reviewing PR $ARGUMENTS against Acme Corp's security checklist.

Run `git diff main` to inspect the changed files, then evaluate:
- No credentials, tokens, or API keys in changed files
- No new eval() or dynamic code execution patterns
- No new external network calls without logging

Summarise as: approved / needs changes / blocked.
```

**Design principle**: write the command for the person who'll use it *on the worst day of a sprint* — specific enough to run without thinking, short enough to read in under 30 seconds.

**Scope decisions**:
- Repeated team ritual (standup command, PR review) → **project** (`.claude/commands/`)
- Personal shortcut, formatting preference, notes helper → **user** (`~/.claude/commands/`)

Sim: **Vantage Capital 6/6** (1B/2B/3B). No unpacking needed.

### 12.2 — Output styles (Lesson 5) ⭐ new D3 exam topic

**The distinction from CLAUDE.md** (memorize — exam-testable):

- **CLAUDE.md = what Claude KNOWS** (project memory, architecture, conventions, build commands)
- **Output style = how Claude COMMUNICATES** (tone, format, level of explanation, TODO markers)

Both are injected into the system prompt at session start. Neither is enforcement.

**Session-start constraint** ⭐: output styles modify the system prompt **at session start**. Changing mid-session has **no effect** — requires `/clear` or a new session for the change to take.

**Setting the style**:
- `/config` in a session → saves to `settings.local.json`
- `"outputStyle": "Explanatory"` in any settings file at the appropriate scope (Block 9 precedence applies)

**Four built-in styles**:

| Style | Behavior | When to use |
|---|---|---|
| **Default** | Standard engineering mode. Efficient, precise, no added commentary. | Most production teams past initial adoption — leave here unless there's a specific reason to change. |
| **Explanatory** | Adds "Insights" sections explaining implementation choices and codebase patterns. | **Adoption phase** — engineers need to understand *what* Claude is doing, not just accept the output. |
| **Proactive** | Executes immediately with reasonable assumptions rather than asking. Still prompts for consequential actions. | Faster/more autonomous when the team already trusts Claude and the task is low-stakes. |
| **Learning** | Explains reasoning **AND** places `TODO(human)` markers at key decision points. | Collaborative mode — devs complete critical pieces rather than accepting Claude's output wholesale. |

**Custom output styles**:
- `.md` files in `.claude/output-styles/` at project, user, or managed level
- **`keep-coding-instructions: true`** → LAYER your format on top of Claude's engineering persona (keeps the engineering instructions, adds your format)
- **`keep-coding-instructions: false`** (default) → REPLACE the engineering persona entirely (use when Claude isn't doing software engineering: writing assistant, data analyst, requirements formatter)

**Three GSI engagement patterns** (all use `keep-coding-instructions: true` — still engineering, just formatted):
- Engagement-docs style: client-ready artifacts with structured headers + next steps
- Security-review style: every finding with severity, file, line, fix
- Onboarding mode: explanatory commentary for juniors joining mid-engagement

### 12.3 — Phase-reading heuristic (activation lifecycle)

| Phase | Right style | Why |
|---|---|---|
| Day 1 adoption — engineers asking "why?" | **Explanatory** | Surfaces reasoning without waiting to be asked; addresses the trust gap at source |
| Mid-adoption (want human ownership of key calls) | **Learning** | `TODO(human)` markers force devs to complete critical pieces |
| Productivity push / handoff — team already trusts Claude | **Default** | Remove commentary, clean engineering mode |
| Autonomous long-horizon, low-stakes | **Proactive** | Only when team trusts AND task is low-risk |

**Common trap** ⭐: on **handoff day**, moving to Proactive to "let Claude go faster" is **wrong** — Proactive = more consequential actions with fewer prompts. Handoff calls for *removing commentary* (Default), not *adding autonomy*.

### 12.4 — Sim: Hartfield 4/6 (path 1A/2B/3B) + PATTERN FLAG

- **Q1** (Day 1, engineers asking why): ✓ **Explanatory** +2.
- **Q2** (Day 3 productivity push, team confident): ❌ picked Proactive (defensible +1). Correct: **Default**. Judgment error — over-rotated toward more capability when the right call was to remove overhead. See 12.3 trap.
- **Q3** (persistent client-format requirement across the team): ❌ picked "add to CLAUDE.md" (defensible +1). Correct: **custom output style with `keep-coding-instructions: true`** in `.claude/output-styles/`.

**Q3 is a recall failure — fact was already in Block 10.2**: *"CLAUDE.md ≠ enforcement; use hooks or purpose-built mechanisms."* Plus 10.2's split: *"CLAUDE.md = what Claude knows. Output style = how Claude communicates."* A persistent output format is a *how*, not a *what*.

---

## ⚠️ PATTERN FLAG — Four recall failures in the past week

| # | Sim | Miss | Fact was in |
|---|---|---|---|
| 1 | Corvane Q4 | Foundry routes to Anthropic infra | 7.7 |
| 2 | Meridian Q2 | Personal preference → User scope | 9.5 |
| 3 | Apex Q1 | Cross-machine → Managed | 9.6 |
| 4 | Hartfield Q3 | Persistent format → output style, not CLAUDE.md | 10.2 |

**Diagnosis**: knowledge is present, retrieval fails under scenario pressure. This is a **study-method issue**, not a knowledge issue. More reading won't fix it. Active recall will.

**Fix (do before Course 4):**
- Cover the notes. Answer aloud from prompts:
  - "Cross-machine, must survive uninstall → ?" → Managed
  - "Just me, all my projects → ?" → User
  - "Team baseline in this repo → ?" → Project
  - "Just me, this repo → ?" → Local
  - "Foundry routes to whose infra?" → Anthropic (unlike Bedrock/Vertex)
  - "Persistent output format across a team → ?" → custom output style (`.claude/output-styles/`), not CLAUDE.md
  - "Team knows *what* → ?" → CLAUDE.md
  - "Team communicates *how* → ?" → output style
  - "Need guaranteed enforcement → ?" → hooks or managed settings, not CLAUDE.md
- 10 reps of the cycle. Track which prompts you hesitate on — those are the retrieval bottlenecks.
- Then, and only then, paste Course 4.

---

## Block 13 — MCP Extensibility ⭐⭐ (D2 core, 18% of exam)

Source: Partner Course 4 (Extensibility), Lesson 1. **D2 is 18% of the exam and MCP is the spine of it** — this is the highest-yield remaining course.

### 13.1 — MCP capabilities: three types (memorize)

| Type | What it is | When used |
|---|---|---|
| **Tools** | Actions Claude can take (create ticket, query DB, trigger pipeline) | Model decides which to call + what to pass |
| **Resources** | Data Claude can read (open tickets, error logs, API schemas) | Loaded into context **on demand**, not constantly |
| **Prompts** | Reusable context templates the server exposes | e.g. standardized preamble that loads client's API docs before any coding task |

**Model stays the same; what it can reach changes.**

### 13.2 — Install & scope

```bash
# Ticketing — pull issue context before writing a fix
claude mcp add linear

# Browser automation
claude mcp add --transport stdio playwright -- npx @playwright/mcp@latest

# Verify + list connected servers and tools they exposed
/mcp
```

**Scope → config file placement**:

| Scope | Flag | File | Applies to |
|---|---|---|---|
| **Local** (default) | (none) | `~/.claude.json` — **keyed to current project** | Just you, this project |
| **Project** | `--scope project` | `.mcp.json` in repo root | Everyone on the repo (committed) |
| **User** | `--scope user` | `~/.claude.json` | You, all your projects |
| **Org** | via `managed-settings.json` | IT-deployed | All developers on machine |

**Trap**: default `local` and `--scope user` **both write to `~/.claude.json`** — the difference is whether it's keyed to current project or global.

**`/mcp`** slash command at session start = verify what's connected + what tools each server actually exposed.

### 13.3 — Three MCP archetypes for engagements

Every activation asks: **what MCP servers does this client already use?**

1. **Ticketing systems** — Jira, Linear, GitHub Issues. Enables "Ticket to PR" pattern; no manual copy-paste of ticket descriptions.
2. **Error logs & observability** — OTel, Datadog, Sentry. Claude reads recent error traces directly. Compresses "error → fix underway" loop. High signal for modernisation work.
3. **Internal systems** — private APIs, internal DBs, service catalogues, Confluence, proprietary tooling. Require **custom/client-built MCP server** OR the **MCP tunnel** (when system isn't reachable from developer's laptop).

### 13.4 — Auth model ⭐ (security review question)

**OAuth-scoped MCP servers** → Claude inherits **the user's own permissions**. MCP server surfaces what the user already has access to — nothing more. This is the answer that usually resolves security reviews' "what can Claude see?" question.

**BUT** — servers using **static API keys, service accounts, or `headersHelper` credentials** may grant access that **differs from** the user's own. Always confirm authentication method + exposed tools before deploying to a team.

**Client framing**: *"Properly scoped MCP servers should not grant access beyond what the user or configured credential can reach. It reduces context switches; it is not a new data-access channel."*

### 13.5 — Transport types (D2 exam-testable)

- **stdio** (local subprocess) — runs on developer's machine, **uses whatever network path the laptop already has**. If laptop reaches Jira via corporate VPN, the stdio MCP server can too. **No external calls, no new firewall exceptions.**
- **SSE / HTTP** — remote MCP server. Traffic goes over network to the server, which then reaches the target system.

**Scenario answer pattern** (Extensibility Lesson 1 practice):
> *"Security policy blocks external network calls from developer laptops. We still want Claude Code to reach the internal Jira."*
> **Correct: local stdio MCP server.** Runs as subprocess on laptop, uses corporate network path directly.
> **Wrong**: cloud-hosted MCP proxy (still an external call from laptop). Wrong: skip MCP entirely (treats solvable config problem as blocker).

### 13.6 — Key framings to remember

- **"MCP is a context amplifier, not a data integration project."**
- **"Model stays the same; what it can reach changes."**
- **Pre-kickoff inventory question**: "What MCP servers does this client already use?" — belongs in the activation-plan checklist.

### 13.7 — Two MCP control planes (Course 4 Lesson 2) ⭐

**User-installed** vs **Org-deployed** are governed differently — clients conflate them, so the CISO's "can developers install anything?" question has a nuanced answer.

| Plane | Mechanism | Scope | Who controls |
|---|---|---|---|
| **User-installed** | `~/.claude.json` or project `.mcp.json` | Only that developer's sessions | Developer; blocked centrally only if admin sets deny in `managed-settings.json` |
| **Org-deployed — deployment** | `managed-mcp.json` | Pushes fixed servers to every user automatically — no user action | IT/admin |
| **Org-deployed — filtering** | `allowedMcpServers` in `managed-settings.json` | Restricts which servers devs may add themselves | IT/admin |

**Two separate controls; configure both on Day 0.**

### 13.8 — `managed-settings.json` MCP allowlist ⭐⭐ (D3+D2 exam-testable config)

```json
{
  "allowManagedMcpServersOnly": true,
  "allowedMcpServers": [
    { "serverUrl": "https://api.github.com/*" },
    { "serverUrl": "https://linear.app/mcp/*" },
    { "serverCommand": ["npx", "-y", "@playwright/mcp@latest"] },
    { "serverUrl": "https://*.client-internal.com/*" }
  ]
}
```

Key facts (memorize):

- **`allowManagedMcpServersOnly: true`** → allowlist is **enforced**. Devs cannot install servers outside it. **Without this flag → list is advisory, not enforced.** This flag is the answer to the CISO's question.
- **`allowedMcpServers` entries must be objects** — `{ "serverUrl": "..." }` or `{ "serverCommand": [...] }`. **NOT bare strings.**
- `serverUrl` supports wildcards (`*`).
- `serverCommand` is an argv array (e.g. `["npx", "-y", "@playwright/mcp@latest"]`) for stdio local servers.

### 13.9 — Independent governance layers (defense-in-depth)

Governance works through **two independent** layers. Both must be configured:

1. **Server allowlist** (`allowedMcpServers`) — what CAN be installed.
2. **Egress domain allowlist** — where installed servers CAN CONNECT (network-layer).

If a server is somehow installed but its egress domain isn't allowed → the network call fails. Layers work independently.

**Plus** OAuth scoping (from 13.4): Claude inherits **user's own permissions**. If dev can't read a private repo, neither can Claude via MCP.

**Client framing**: *"MCP governance isn't a trust conversation. It's a configuration. The allowlist controls what can be installed, egress controls limit where it can call, and OAuth scoping means Claude reaches only what the developer already can."*

### 13.10 — Day 0 rule + true/false traps

**Rule**: MCP allowlist is a **Day 0 task**, alongside SSO/SCIM and spend reporting. **NOT** Day 30, NOT "experiment freely first." Retrofitting governance after developers form habits is harder than setting it up cleanly at kickoff.

True/false traps from the lesson (all straightforward):

| Statement | Answer |
|---|---|
| With default settings, developers can install any MCP server locally | **TRUE** — default is permissive; `allowManagedMcpServersOnly: true` is what locks it |
| Egress domain allowlists can block unapproved installed servers' outbound calls | **TRUE** — independent layers |
| MCP allowlist is a Week 4 task; safer to experiment first | **FALSE** — Day 0 prerequisite |
| OAuth-scoped MCP = Claude accesses only what the dev is authorized to reach | **TRUE** — key security-review closer |

**Sim heuristic**: launch Day 0 with **approved-only allowlist**, log pending servers (e.g. Playwright still under IT review) as CoE agenda items. Don't delay cohort for a single pending server. Don't bypass process for expedited approvals. Same-week turnaround via CoE is the target.

### 13.11 — Remote MCP relay: when to use (Course 4 Lesson 3) ⭐

**The problem it solves**: system is approved for MCP access + legitimate, BUT only accepts connections from inside the corporate network. Claude Code on developer's laptop can't reach it directly.

**Architectural decision** (D2 exam pattern):

| Direct connection | Remote relay |
|---|---|
| Target reachable from developer's environment | Target behind network boundary laptop can't cross |
| SaaS tools (GitHub, Linear, Slack), VPN-accessible systems | Internal APIs restricted to specific subnets, air-gapped envs, no firewall rule for dev laptops |
| `claude mcp add` → done | Deploy MCP server inside corporate network, expose via HTTP/SSE, connect via VPN |

**Rule**: **relay adds latency and a failure point** — don't use it if direct connection works. GitHub = SaaS = direct. Confluence-behind-VPN = relay.

### 13.12 — `.mcp.json` HTTP/SSE server config + CLI

```json
{
  "mcpServers": {
    "internal-api": {
      "type": "sse",
      "url": "https://mcp.client-internal.com/sse"
    }
  }
}
```

CLI equivalent:
```bash
claude mcp add --transport sse internal-api https://mcp.client-internal.com/sse
```

**Transport types recap** (all 3 now covered):

| `type` | Use case | Auth |
|---|---|---|
| **`stdio`** | Local subprocess on dev's machine (uses laptop's existing network path) | OAuth possible, or process env vars |
| **`sse`** | Remote MCP over server-sent events | OAuth · static headers · `headersHelper` |
| **`http`** | Remote MCP over HTTP | OAuth · static headers · `headersHelper` |

**Auth options for HTTP/SSE MCP servers** (memorize):
- **OAuth** — for servers that support it; Claude inherits user's permissions (see 13.4)
- **Static headers** — API keys or bearer tokens in `.mcp.json`
- **`headersHelper`** — custom auth: internal SSO, Kerberos, short-lived tokens, dynamic credentials

### 13.13 — Relay security framing (D5-adjacent)

**What the relay carries**: MCP protocol traffic only — tool call requests + responses. **Not a VPN. Not general network access.** The security boundary stays at the **MCP server** running inside the network, which controls exactly which tools/resources are exposed.

**Common client objection**: *"We can't allow Claude Code to make calls through a tunnel. We don't know what traffic is flowing through it."*

**Correct response**: explain what the relay carries. It's not a VPN. **The MCP server inside the network is the actual security boundary**, and it enforces exactly which tools/resources are exposed to Claude. Log-review after deployment doesn't address the architectural concern; explain the mechanism first, monitoring second.

**Anti-patterns**:
- Adding relay for GitHub (SaaS, direct works)
- Confusing relay (network problem) with `managed-mcp.json` (distribution problem)
- Removing relay after client objection instead of explaining what it carries

---

## Block 14 — Skills ⭐⭐ (D3 core — Course 4 Lesson 4)

**Definition**: a **folder** of files (instructions, scripts, templates) that gives Claude a specific reusable capability. **Loaded only when relevant** to the current task — not loaded when not needed = zero overhead.

### 14.1 — Two categories

| Category | What it solves | Examples |
|---|---|---|
| **Capability Skills** | Things Claude *can't do well* without specialized instructions | PDF generation in client format, complex Office layouts, proprietary output templates, ISO 20022 XML payment messages |
| **Knowledge Skills** | Org-specific workflows/standards Claude needs to *apply consistently* | Coding conventions, PR description templates, incident post-mortem format, compliance language, brand guidelines |

**One-liner framing**: *"A Skill turns a document nobody reads consistently into something Claude applies automatically."*

### 14.2 — File anatomy

**Minimum viable Skill** = 1 file:
```
my-skill/
└── SKILL.md      ← required
```

**Real engagement Skill** = SKILL.md + bundled resources loaded on demand:
```
api-docs-skill/
├── SKILL.md
├── endpoint-template.yaml   ← loaded on demand
├── example-spec.yaml        ← loaded on demand
└── apply_template.py        ← run if needed
```

**SKILL.md structure** = YAML frontmatter + body:
```markdown
---
name: API Documentation Standards
description: Apply client's internal REST API documentation format
             when writing or reviewing any endpoint specification
---

## Overview
[Instructions Claude follows when this skill loads]

## Format Requirements
[Specifics: header format, field definitions, required fields]

## Example
[One worked example of a compliant spec]

Read ./endpoint-template.yaml for the full schema
```

Frontmatter fields (from earlier Course 3 Lesson 2 + this lesson):
- **`name`** — the Skill's identifier
- **`description`** ⭐⭐ — **the trigger**. Most important line. Determines whether Claude loads it.
- **`context: fork`** — run in isolated sub-agent context (skill outputs don't pollute main conversation)
- **`allowed-tools`** — restrict tool access during Skill execution
- **`argument-hint`** — prompt for required params when invoked without args

### 14.3 — Progressive disclosure ⭐⭐ (the exam-testable mechanism)

Claude uses a **three-step loading protocol** — it does NOT load all Skills into every session.

| Step | What Claude sees | Result |
|---|---|---|
| **1. Scan** | name + description ONLY | Decides: relevant to this task? |
| **2. Load** | Full SKILL.md body | Reads instructions + examples |
| **3. Fetch** | Linked bundled files (if needed) | Accesses templates, specs, scripts |

**Consequence**: a library of **10–20 Skills doesn't degrade performance** on every task. Overhead is proportional to relevance, not to library size.

**Consequence #2**: `description` quality determines whether the Skill triggers correctly. **Vague description → Skill doesn't load when it should, or loads when it shouldn't.** Description-writing is the most important authoring decision.

**Invocation paths**:
1. **Automatic** — Claude scans descriptions, decides relevance (default)
2. **Direct** — user invokes by name: `/skill-name`
3. **Explicit reference** — user mentions in prompt: "use my-skill for this"

### 14.4 — Three engagement Skill patterns ⭐ (memorize the pattern selection heuristics)

| Pattern | Signal | Fix |
|---|---|---|
| **Pattern 1 — Refined through experience** | Repeated task · established quality standard · **output varies across team** | Encode the standard as instructions in SKILL.md |
| **Pattern 2 — Quality depends on materials** | Reference material exists · **isn't reaching Claude reliably** (people paste it inconsistently, personal copies drift) | Bundle the reference file; SKILL.md tells Claude when to consult it |
| **Pattern 3 — Capability gap** | Claude **can't do the task correctly at all** · missing knowledge of a format/schema/protocol · every attempt fails | Build Skill with schema + required fields + worked example |

**Pattern selection heuristic** (this is the exam trap where Winston got 3/3 wrong):

| Symptom | Pattern |
|---|---|
| Output is **consistently wrong / fails validation** | **P3** (capability gap — Claude doesn't know the format) |
| Output is **consistent when applied but people don't apply it uniformly** | **P1** (established standard, needs encoding) |
| Reference **exists** but **access is unreliable** (paste drift, forgotten steps) | **P2** (bundle for on-demand loading) |

**Decision tree — memorize this exact sequence** ⭐:

```
Can Claude already perform the task correctly SOMETIMES?
│
├── Yes, but quality varies
│      → Pattern 1: encode the standard
│         "Do it the same way every time"
│
└── No
     │
     ├── Does the correct information already exist,
     │   but Claude does not reliably receive it?
     │      → Pattern 2: bundle the reference
     │         "Always give Claude the right material"
     │
     └── Does Claude need specialised knowledge,
         rules, schemas, or examples it does not know?
             → Pattern 3: teach the capability
                "Teach Claude something it does not know"
```

**Three one-liners for exam-day recall**:
- **P1**: *"Do it the same way every time."*
- **P2**: *"Always give Claude the right material."*
- **P3**: *"Teach Claude something it does not know."*

**Real-world application examples** (from Winston's own work):

| Client asset | Likely pattern | Why |
|---|---|---|
| QC severity rubric | **P1** | Claude can assess issues; the goal is consistent severity + routing |
| Metric dictionary / approved business definitions | **P2** | Definitions exist; need reliable delivery to Claude |
| Normalized evidence schema (proprietary) | **P3** | Claude has never seen it; must learn fields + rules from scratch |

### 14.5 — Sim walkthrough (from Course 4 Lesson 4)

**Sim 1 — Service catalogue, 3 devs pasting drifting copies** → **P2** (materials exist, need reliable access).
- Not P1: symptom is inconsistent *access*, not inconsistent writing.
- Not P3: catalogue already exists; Claude doesn't need it built from scratch.

**Sim 2 — Post-mortem severity classifications vary (P2 vs P4 for same incident)** → **P1** (established standard, inconsistent application).
- Not P2: bundling the runbook still leaves Claude interpreting prose. **Fix is encoding the rubric as instructions**, not just making it accessible.
- Not P3: Claude *can* write post-mortems; consistency is the problem, not capability.

**Sim 3 — ISO 20022 XML with wrong field names, missing nested elements, every test fails schema** → **P3** (capability gap).
- Not P1: output is *consistently wrong*, not inconsistent. Pattern 1 applies when quality varies; here every test fails.
- Not P2 alone: reference file isn't enough — Claude can't navigate a 200-page spec on demand. **P3 goes further: schema + required fields + complete worked example — like briefing an engineer who's never seen the format.**

**Root heuristic**: **P3 is for "can't do at all" · P1 is for "does it inconsistently" · P2 is for "materials exist but don't reach Claude reliably."**

### 14.6 — True/false traps (from lesson check)

| Statement | Answer | Why |
|---|---|---|
| "Claude loads every Skill's full SKILL.md on every task" | **FALSE** | Progressive disclosure — Claude reads description first, loads body only if relevant. 10+ Skills = zero overhead on unrelated tasks. |
| "A Skill can include executable scripts Claude runs as part of the workflow" | **TRUE** | Python, shell, any executable. SKILL.md instructs when/how. This is how Capability Skills work. |
| "The description field is cosmetic — Claude doesn't use it to decide whether to load the Skill" | **FALSE** | Description is **the trigger**. Vague description = Skill doesn't fire when it should. Most important authoring decision. |

### 14.7 — Skills vs CLAUDE.md — pick the right layer (D3 crossover)

| Use CLAUDE.md when… | Use a Skill when… |
|---|---|
| Instructions apply to **every** session in this project | Instructions apply only when a **specific task** comes up |
| Universal standards (tech stack, build commands, tone) | Task-specific expertise (PDF gen, ISO 20022, post-mortem rubric) |
| Always-loaded context, cheap | On-demand loading via progressive disclosure |
| Same team, same shared file (project scope) | Team-shared OR personal (`~/.claude/skills/` for personal variants) |

**Rule**: if applying it every session wastes context, it's a Skill. If it's applicable every session, it's CLAUDE.md.

### 14.8 — Skills library placement (D3 scope, ties to Block 9)

- **Project-scoped** — `.claude/skills/` in repo (committed, shared)
- **User-scoped** — `~/.claude/skills/` (personal variants; different name than team's to avoid conflict)
- **Managed** — org-deployed via IT (similar to `managed-settings.json` pattern)

**Personal customization workflow**: if the team's `<name>` skill doesn't fit your workflow, create `~/.claude/skills/<my-name>/` with different name. Doesn't affect teammates.

**Marketplace check**: before building a Skill from scratch, check the client's existing Skills + Anthropic's marketplace. Don't build what's already available.

### 14.9 — Authoring a Skill that works (Course 4 Lesson 5) ⭐⭐

**The three-element description rule** (this is where the exam traps you):

A good `description:` needs **all three**, not just two:

| Element | Purpose | Example fragment |
|---|---|---|
| **1. Trigger condition (WHEN)** | Tells Claude *when* to load | "when writing or reviewing function signatures, API endpoints, or service interfaces" |
| **2. Output / format (WHAT)** | What the Skill produces or applies | "JSDoc format, required fields, and example patterns" |
| **3. Distinctive marker (WHICH)** | Distinguishes from other similar Skills | "the client's TypeScript documentation standard" |

**Trap**: descriptions can *look* correct with just trigger + format but fail because they're indistinguishable from a sibling Skill. If the client has two documentation Skills (TypeScript vs OpenAPI), the description must name **which one** it is.

Failure modes:
- **Vague** ("Apply PR format") → Claude doesn't know when to load. Never triggers.
- **Over-broad** ("Help with API documentation") → loads on unrelated tasks, creates context overhead.
- **Missing distinctive marker** → correctly loads but Claude picks between similar Skills arbitrarily.

### 14.10 — Five-step authoring process

1. **Identify the trigger** — when does this Skill activate? Be specific.
2. **Write the description** — three elements, in one sentence
3. **Write SKILL.md core** — state format · show ONE complete example · list required fields · link to bundled reference (don't embed)
4. **Bundle reference files** — schemas, templates, scripts loaded on demand
5. **Test** — request the trigger prompt; verify (a) Skill loaded and (b) output matches standard

**Debugging by symptom**:
- Skill **doesn't load** when it should → fix the **description** (missing trigger condition or too vague)
- Skill **loads but produces wrong output** → fix the **instructions** in SKILL.md body

### 14.11 — Explicit constraints beat more examples ⭐⭐ (exam trap #2)

**"Skills behave like staff — they follow the instructions they've been given."**

When Claude *consistently produces wrong output* from a Skill:

| Wrong fix | Right fix |
|---|---|
| Add more examples of the desired behavior | Add a **targeted explicit rule** |
| "Show, don't tell" | Both. But rule first. |
| Remove the Skill and go manual | Never — you'd lose all adoption |

**Rule**: Claude applies **explicit written constraints FIRST**. It does NOT reliably infer behavioral rules from example patterns alone. If the Skill is adding a "Lessons Learned" section on minor incidents, write:

> *"Only include the Lessons Learned section for P1 and P2 severity incidents."*

One sentence fixes it. Adding more examples of minor-incident post-mortems just gives Claude more reference material for the pattern it's already misapplying.

### 14.12 — Authoring principles (the difference between Skills that last and ones that drift)

1. **Keep it focused** — one Skill per workflow. Don't bundle "coding standards + PR format + security review" into one file.
2. **Start simple** — core guidance first, expand from real usage gaps.
3. **Use examples** — one worked example beats three paragraphs of rules. But use it *in addition to* explicit constraints (not instead).
4. **Test incrementally** — verify simple version before building multi-file complexity. A silently-failing Skill is worse than no Skill.
5. **Version your Skills** — client standards change; when their PR template changes, the Skill needs updating. Treat Skills like production code.

### 14.13 — The Skill Creator shortcut

For a Knowledge Skill from scratch: **prompt Claude** with:
> *"Build a Skill for [task]. Here are 5 examples: [examples]."*

Claude generates the folder structure, SKILL.md, and example files. Faster than writing from scratch, and the description will reflect how Claude actually interprets the task (useful sanity check for description quality).

### 14.14 — Common exam traps summary

| Trap | Wrong intuition | Correct rule |
|---|---|---|
| "Add more examples to fix wrong output" | Examples always help | **Explicit constraints first, examples second** |
| "Description with trigger + format is enough" | Two elements sound complete | **Three elements: trigger + format + distinctive marker** |
| "If Skill loads but output is wrong, description is broken" | Both are description problems | **Loads wrong → fix description. Loads right, output wrong → fix instructions** |
| "Bundle everything so Claude has full context" | More context = better output | **Focused Skills load precisely; bundled everything loads noisily** |
| "Remove the Skill if it's misbehaving" | Cut losses | **One targeted rule usually fixes it; keep the adoption** |

### 14.15 — The two-layer model + memory rules ⭐⭐ (Winston's synthesis — the exam-day mental picture)

**Every Skill has two layers, and each does a different job.** Getting these confused is what causes the two most common exam traps.

| Layer | Purpose | The question it answers |
|---|---|---|
| **1. YAML `description`** | Gets the Skill **selected** (loaded) | *"Should this Skill load right now?"* |
| **2. `SKILL.md` instructions** | Gets the task **performed correctly** | *"How should Claude do the work now that the Skill has loaded?"* |

**Memory rule** (say this out loud before any Skills question):
> **"Description gets the Skill *selected*. Instructions get the task *performed correctly*."**

**Corollary**:
> **"When the failure is specific, fix it with a specific rule — not more general examples."**

**Debug ladder** — when Claude behaves incorrectly with a Skill, walk this in order:

| Symptom | Which layer to fix | What to add |
|---|---|---|
| **Correct Skill fails to load** | Description metadata | Trigger condition · capability/output · distinctive marker (all three) |
| **Skill loads, but Claude follows wrong behavior** | Instructions in SKILL.md | An **explicit rule** — allowed + disallowed behavior stated directly |
| **Rule understood but Claude still varies** | Instructions in SKILL.md | Decision table · deterministic validation · edge-case examples |

**Why this framework matters on the exam**:

- Question asks "Skill loads but produces wrong output" → **the description is fine**; fix instructions (add explicit rule). Don't rewrite description.
- Question asks "Skill never loads even when relevant" → **the instructions are fine**; fix description (add trigger / distinctive marker). Don't add more examples.
- Question mentions "adding more examples fixes it" → almost always wrong. **Explicit rules beat implicit inference.**

**The two-example diagnosis** (Course 4 Lesson 5 checks):

| Sim | Correct fix | Why |
|---|---|---|
| "Claude keeps adding Lessons Learned to P3/P4 incidents" | Add explicit rule "Only include Lessons Learned for P1/P2" | Layer 2 fix (instructions) — Skill loads correctly; rule is missing |
| "Which description triggers correctly?" | The one with **trigger + format + distinctive marker** | Layer 1 fix (metadata) — needs a differentiator vs sibling Skills |

---

## Block 15 — Hooks & the Enforcement Spectrum ⭐⭐ (D1 + D3 + D5 — Course 4 Lesson 6)

### 15.1 — The five enforcement mechanisms (Winston's synthesis)

**Every behavior in Claude Code can be governed by one of five mechanisms, on a reliability spectrum**:

| Component | Purpose | Reliability |
|---|---|---|
| **Instruction** | Tells Claude *how* it should behave | Probabilistic |
| **Skill** | Gives Claude reusable expertise and procedures | Still interpreted by Claude |
| **Hook** | Automatically runs system logic at a lifecycle event | **Deterministic enforcement** |
| **Validator** | Checks whether an output follows rules | Deterministic or model-assisted |
| **Human approval** | Allows a person to approve high-risk actions | Governance control |

**Rule of thumb**: as consequences increase (financial, security, compliance), move DOWN the table toward deterministic mechanisms. Prompt/Skill guidance for style; Hook enforcement for guarantees; Human approval for irreversible actions.

### 15.2 — Layered enforcement in practice

Same rule, two layers:

- **Instruction (probabilistic)**: *"Do not edit production configuration."* — Claude *should* obey, but there's no hard barrier.
- **Hook (deterministic)**: *"Before every Edit call, inspect the path. If under `/production/`, exit 2."* — the edit is **actually blocked**.

**Strongest design** = both. Instruction tells Claude what good behavior looks like; Hook technically enforces the critical boundary.

**Memory rule** ⭐:
> **"Skills teach Claude. Hooks control the environment."**

### 15.3 — Hook lifecycle events (memorize the two most-tested)

| Event | Timing | Use for |
|---|---|---|
| **`PreToolUse`** | Before a tool executes | **PREVENT** — block edits to protected paths, block refunds over threshold, require ticket before writes |
| **`PostToolUse`** | After a tool finishes | **OBSERVE or REACT** — log every Bash call, run auto-formatting, normalize timestamps in returned data |

**Memory rule** ⭐:
> **"PreToolUse to prevent. PostToolUse to observe or react."**

### 15.4 — Hook config in `settings.json`

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "jq -r '.tool_input.command' >> ~/claude-bash-log.txt"
          }
        ]
      }
    ]
  }
}
```

**Structure** — memorize:

- Top-level `"hooks": {...}` in `settings.json`
- Keyed by **lifecycle event** (`PreToolUse` / `PostToolUse`)
- Each entry has a **`matcher`** (tool name — activates only for that tool) and a **`hooks`** array of `{type, command}` objects
- `type: "command"` is the shell-command hook type
- **Tool-call JSON is piped to hook via stdin** — extract fields with `jq`

**JSON gotcha**: JSON does NOT support `#` comments. Docs sometimes show them for annotation — strip them before writing your `settings.json`.

### 15.5 — Hook security ⭐⭐ (governance layer, exam-testable)

Hooks run **real shell commands with the developer's permissions**. A malicious hook could:
- Read files
- Copy credentials
- Execute arbitrary software
- Change repositories
- Send data externally

**Key phrase** (memorize):
> **"A compromised hook is a lateral movement path"** — an attacker in the hook can move laterally into any system the developer can access.

**Good governance controls** for hooks:

- Store hooks in **source control**
- Require **code review** for hook changes
- **Restrict who** can modify them (managed-settings.json can lock hook config)
- **No embedded secrets**
- **Validate all input** (tool-call JSON is untrusted)
- **Least privilege** — run with minimum permissions needed
- **Log** hook changes
- **Deploy approved versions centrally** (not per-developer)

**Anti-pattern (command injection)**: if your hook takes JSON input and re-executes it via `sh -c`, you've built an injection surface. Prefer extracting the value with `jq` and logging it directly, not re-executing it.

### 15.6 — Exit codes control Hook behavior

| Exit code | Meaning | Effect |
|---|---|---|
| **0** | Success | Tool call proceeds as normal |
| **2** | Blocking failure | **PreToolUse: blocks the tool call. Tool never runs.** |
| Non-zero (other) | Warning / error | May log; behavior varies |

The magic combo is **PreToolUse hook + exit code 2** — that's the deterministic enforcement mechanism the exam keeps testing.

### 15.7 — Glossary (Winston's terms — the exam-day quick-reference)

| Term | Plain-English meaning | Example |
|---|---|---|
| **Hook** | Automatic command triggered by a Claude Code lifecycle event | Log every Bash call |
| **Lifecycle event** | Defined moment during an agent session | Before a tool call · when a task ends |
| **PreToolUse** | Hook event before a tool executes | Block edits to protected files |
| **PostToolUse** | Hook event after a tool finishes | Run formatting · audit logging |
| **Matcher** | Filter determining which tool calls activate a hook | Activate only for `Bash` |
| **Exit code** | Numeric result returned by a command | 0 = succeed · 2 = block |
| **stdin** | Input supplied directly to a command | Claude Code passes tool-call JSON to the hook |
| **jq** | CLI tool that extracts values from JSON | `jq -r '.tool_input.command'` |
| **Enforcement hook** | Hook that technically blocks prohibited actions | Require a ticket before protected writes |

### 15.8 — Common exam trap: hook vs instruction

| Scenario | Wrong choice | Right choice |
|---|---|---|
| "Prevent refunds above $500 in a customer-support agent" | Prompt: "Do not process refunds above $500" | **PreToolUse hook** blocking `process_refund` calls with amount > $500 (exit 2) |
| "Ensure identity verification before financial ops" | Prompt: "Always call get_customer first" | **PreToolUse hook** blocking `process_refund` until `get_customer` has returned verified ID |
| "Normalize Unix timestamps to ISO 8601 from different MCP tools" | Instruction to Claude | **PostToolUse hook** with the normalizer |
| "Log every Bash command developers run" | Ask developers to log manually | **PostToolUse hook** on Bash calls, matcher `Bash`, appends to log |

**Rule**: any time an exam question involves **financial, security, or compliance consequences** — the answer is usually a **hook** (deterministic), not a prompt/skill instruction (probabilistic).

### 15.9 — All five common lifecycle events (Course 4 Lesson 6)

Block 15.3 only had two events. The full common set is **five**, with 20+ total in Claude Code:

| Event | When it fires | Primary use |
|---|---|---|
| **`PreToolUse`** | Before Claude runs any tool | **Blocking enforcement** — check conditions before the action |
| **`PostToolUse`** | After a tool run completes | Logging, auto-formatting, side-effect triggers |
| **`Notification`** | When Claude sends a notification | Alerts: Slack message, desktop sound, webhook ping |
| **`Stop`** | When the **main agent's** task completes | Summary logging, cleanup, end-of-session actions |
| **`SubagentStop`** | When a **subagent** completes | Subagent result handling, parallel job coordination |

**Advanced governance events** (beyond the common five, ~20 total): `SessionStart` (init), `PermissionRequest` / `PermissionDenied` (fine-grained approval), `FileChanged` (sensitive-file protection), `ConfigChange` (drift detection).

### 15.10 — Exit codes revisited (add code 1)

Block 15.6 was incomplete. Full table:

| Exit code | Meaning | Effect |
|---|---|---|
| **0** | Success | Tool call proceeds normally |
| **1** | Failure, **non-blocking** | Error surfaces in Claude's context but execution proceeds |
| **2** | Blocking failure | **PreToolUse: blocks the tool call. Tool never runs.** |
| Other non-zero | Warning / error | Logged; behavior varies by event |

**Exit-code exam gotcha**: only **`PreToolUse` + exit 2** is the true enforcement combo. `PostToolUse + exit 2` doesn't undo the tool call (it already ran) — it just logs/errors.

### 15.11 — Four hook use case categories

The Activation Plan groups hooks into four archetypes:

| Category | Example | Event | Effort |
|---|---|---|---|
| **Notifications** | Slack ping when Claude waits for input · sound on task complete | `Notification` or `Stop` | Trivial · Week 1 |
| **Auto-formatting** | `prettier --write` on every `.ts` edit · `gofmt` on `.go` | `PostToolUse` on `Edit` | Trivial · Week 1 |
| **Logging** | Timestamped record of every Bash call | `PostToolUse` on `Bash` | Low · Week 1–2 |
| **Enforcement** | Block writes to `/config` without ticket · block refunds > $500 | `PreToolUse` + exit 2 | Higher · Week 4 packaging |

### 15.12 — Activation Plan timing

- **Day 3–5** of Week 1: **start with 2 low-risk, high-value hooks** — a Notification hook (Slack/sound when Claude needs input) + an Auto-format hook on the primary language. Zero developer overhead, immediate productivity win.
- **Week 4 (packaging)**: security-logging hooks + custom compliance hooks go into the **team plugin**. These are the artifacts demonstrating the deployment is under governance — what the client's security team needs to see at engagement close.

**Rule of thumb**: hooks are **baseline setup, not an advanced feature.** Have an opinion on hooks by Day 3.

### 15.13 — Course 4 Lesson 6 sim answers (memorize the two)

**Sim 1** — Block edits to `/config` unless session context has a ticket number:
- ✅ **PreToolUse on `Edit`** with matcher/path check + exit 2 (blocks the edit before it happens)
- ✗ PostToolUse on Edit — edit already happened, can only log the violation
- ✗ Stop hook scanning at session end — too late, every edit already made

**Sim 2** — Slack notification when a security-audit **subagent** completes:
- ✅ **`SubagentStop`** — fires the moment that subagent returns results
- ✗ Stop — fires when the *main* agent completes, potentially minutes later
- ✗ PostToolUse on Bash — fires after *every* command; dozens of pings, not one

**Trap patterns to remember**:
- **PreToolUse blocks. PostToolUse reacts.** — the single most-tested distinction in D3/D5.
- **Stop = main agent done. SubagentStop = subagent done.** Choose based on which agent triggers the event.
- **Blocking requires PreToolUse + exit 2.** PostToolUse + exit 2 is not blocking; the tool already ran.

---

## Block 16 — Subagents & Multi-Agent Orchestration ⭐⭐⭐ (D1 core, 27%)

### 16.1 — Subagents vs Parallel Claude instances (the D1 trap-topic)

**The single most-confused distinction in agentic architecture.** Both involve multiple Claude processes running at once. The difference is **whether they communicate**.

| | **Subagents** | **Parallel Claude instances** |
|---|---|---|
| **What it is** | Specialized mini-agents spawned within your session | Independent Claude Code instances in separate terminals |
| **Context** | Isolated sub-context; **returns results to main agent** | Full independent context per instance; **never communicate** |
| **When to use** | Delegate specialized work without polluting main context | Multiple tasks that could each ship as separate PRs; hours of independent work |
| **Coordination** | Automatic: main agent waits for results | Manual: you manage across terminals; TMUX for awareness |

**Memory rule** ⭐:
> **"Subagents return results. Parallel instances ship work."**

**Getting this wrong is the most common subagent design error on engagement teams.** Any exam scenario about "how should I run these two independent workstreams?" reduces to this table.

### 16.2 — Subagent spec anatomy (D1 mechanics)

Each subagent = a **markdown spec file** in the project's `agents/` directory:

```
my-project/
├── CLAUDE.md
├── agents/
│   ├── code-reviewer.md
│   ├── security-auditor.md
│   └── researcher.md
└── src/
```

**Spec format** (example `security-auditor.md`):

```yaml
name: security-auditor
description: Scans for SQL injection, XSS, CSRF, and OWASP
             Top 10 vulnerabilities in modified code. Returns
             a structured findings report.
tools: Read, Grep, Bash
```

**Two exam-testable fields**:

| Field | Role | Parallel with Skills |
|---|---|---|
| **`description`** | Main agent decides which subagent to spawn by scanning descriptions | Same three-element rule: **trigger + capability + distinctive marker** |
| **`tools`** | Scopes the subagent to exactly the tools it needs | Security auditor doesn't get `Edit`/`Write` — principle of least privilege |

**Cross-reference**: subagents are spawned via the **`Task` tool**. Coordinator's `allowedTools` **must include `Task`** for spawning to work (see Block 13.4 / Ch 15 field manual). **Parallel subagents = multiple Task calls in ONE coordinator response**, not across turns.

### 16.3 — Canonical pattern: three-agent security audit ⭐

The canonical D1 pattern to propose when a client needs governance on AI-generated code:

```
Main agent (writing feature)
   ↓  spawns audit subagent when feature ready for review
Audit subagent (OWASP scan)
   ↓  isolated context; returns structured findings report
Remediation subagent (applies fixes)
   ↓  receives findings; applies targeted fixes; returns remediated code
Main agent (secure feature complete)
   Main context stayed clean; audit detail never entered main window
```

**Value proposition** (exam framing): produces an **auditable trail** (each subagent's task + output loggable) without slowing the main dev flow. Demonstrates security governance without architectural changes.

### 16.4 — Context isolation model (what subagent sees / doesn't see)

**Subagent SEES** (its inputs):
- Its own **system prompt** (from the spec file)
- The **task description** passed by the main agent
- Its **own tool results** as it works

**Subagent does NOT see** (must be passed explicitly if needed):
- Prior conversation messages
- MCP connections established in the main session (unless explicitly passed)
- Main agent's current file state beyond what's in the task description

**Design consequence**: **design subagent tasks to be self-contained.** Include all findings, source URLs, file contents needed for the subagent's work directly in the task prompt. See Ch 15 field manual: "subagent context is never inherited."

### 16.5 — Isolation is NOT process/network isolation ⚠️

**Common client misconception** (and an exam-testable trap):

Subagents share the **same Claude Code session** and use **separate context windows**. This is:
- ✅ Context isolation (that's the whole point)
- ❌ NOT process-level isolation
- ❌ NOT network-level isolation

**Consequence**: proxy rules, credentials, session-level policies, and network configuration **STILL APPLY** to subagent operations. Don't assume isolation that hasn't been explicitly confirmed with the client's platform team.

### 16.6 — Failure handling: no automatic retry ⭐⭐

**Rule**: when a subagent fails, Claude Code returns an **error result** to the main agent. There is **no automatic retry**. The main agent decides what to do.

Error result format:
```json
{ "status": "error", "message": "Parse failed: minified file at /dist/app.min.js" }
```

Main agent's options (must be in its instructions):
- **Retry** with a different approach
- **Skip** and continue with partial results
- **Escalate** to human review
- **Flag** the failure and proceed with other subagent results

**Anti-patterns**:
- Silent skip (masks the error)
- Halt the entire pipeline for one subagent failure (discards unrelated clean results)
- Passing failed result downstream to next subagent (audit → remediation cascade)

**Design principle** (memorize): **design subagent tasks to be atomic** — each returns either a result or an error, handled independently.

### 16.7 — True/false traps (Course 4 Lesson 7)

| Statement | Answer |
|---|---|
| "The main agent's instructions determine how a subagent failure is handled — no automatic recovery built into Claude Code" | **TRUE** |
| "If a subagent fails, Claude Code automatically retries it until it succeeds" | **FALSE** (no automatic retry; explicit main-agent handling required) |

### 16.8 — Course 4 Lesson 7 sim answers (memorize the two)

**Sim 1 — IT says proxy policy will block subagent spawning**:
- ✅ **Ask IT what specifically is being blocked** first. Subagents spawn *within the session process* — they don't make outbound API calls to spin up. Proxy usually applies to HTTP/S calls, not in-process spawning. **Investigate before redesigning.**
- ✗ Switch to parallel terminals — solves the wrong problem (loses coordination + result-collection)
- ✗ Accept the restriction without interrogating — most costly option; a clarifying question may dissolve the concern

**Sim 2 — Security audit subagent fails on minified file; lint + test subagents returned clean**:
- ✅ **Receive error, log failure, flag file for manual review, proceed with lint + test results.** Atomic task design means one failure doesn't invalidate unrelated work.
- ✗ Mark entire pipeline failed — discards clean results
- ✗ Automatic retry — doesn't exist; main agent must handle

### 16.9 — D1 memory rules (say aloud before D1 questions)

- **"Subagents return results. Parallel instances ship work."**
- **"Subagents share the session, not the network — proxy/credentials still apply."**
- **"No automatic retry. Main agent's instructions handle failure."**
- **"Multiple Task calls in ONE response = parallel spawning."**
- **"Subagent context is never inherited — pass everything explicitly."**

Combined with your Block 15 enforcement spectrum + Block 14 Skills two-layer model, that's the D1 + D3 core.

### 16.10 — Glossary (Winston's synthesis + analytics-context mapping)

| Term | Plain-English meaning | Winston's analytics example |
|---|---|---|
| **Subagent** | Specialized agent spawned by a parent agent to complete part of the same task and return structured results | Traffic, Product, CRM, and QC subagents supporting the Business Review agent |
| **Parent agent** | Coordinating agent that delegates work and integrates results | Business Review orchestrator |
| **Isolated context** | Each subagent sees only what it needs — reduces token usage and cross-domain interference | Traffic agent receives only traffic evidence, not merchandising or CRM detail |
| **Context pollution** | Unnecessary information filling an agent's context window, making reasoning less efficient | Feeding raw SQL, campaign logs, and inventory data into one giant prompt |
| **Parallel Claude instances** | Completely independent Claude sessions working on unrelated tasks | One Claude refactors validation while another builds a QC dashboard in separate terminals |
| **Context compression** | Returning concise, structured findings instead of full reasoning or raw data | Traffic subagent returns findings + confidence + evidence IDs, not all intermediate analysis |

---

## Block 17 — Plugins ⭐⭐ (D3 packaging / distribution — Course 4 Lesson 8, capstone)

**Definition**: a **folder with a `plugin.json` manifest + all Claude Code extensions bundled** into one installable unit. Developer installs it with **one command** and gets Skills, hooks, MCP configs, slash commands, and subagent specs together.

### 17.1 — Plugin directory structure ⭐ (memorize)

```
my-plugin/
├── .claude-plugin/
│   └── plugin.json          ← required manifest
├── commands/                ← custom slash commands
│   └── code-review.md
├── agents/                  ← subagent specs (Block 16.2)
│   └── security-auditor.md
├── skills/                  ← Skills (Block 14)
│   └── coding-standards/
│       └── SKILL.md
├── hooks/                   ← hook config (Block 15)
│   └── hooks.json
└── .mcp.json                ← MCP server definitions (Block 13.8)
```

**Note the exact paths**: `.claude-plugin/plugin.json` (dot-prefix folder, singular file), then top-level `commands/`, `agents/`, `skills/`, `hooks/`, and root-level `.mcp.json`. Directory naming is exam-testable.

### 17.2 — `plugin.json` manifest — 3 required fields

```json
{
  "name": "finserv-activation",
  "version": "1.0.0",
  "description": "Claude Code activation plugin for FinServ Corp engineering team"
}
```

Required: **`name` · `version` · `description`**.

### 17.3 — Install commands (D3 slash commands)

```
/plugin install @org/plugin-name    ← install specific plugin
/plugin browse                      ← browse available plugins
/plugin update @org/plugin-name     ← update installed plugin
```

### 17.4 — Fitness test: what belongs in the plugin ⭐⭐ (Day 28 packaging call)

Every component has a bundling bar. **A component that worked for one developer isn't ready for 12.**

| Component | Bundle if… |
|---|---|
| **Skill** | Used by ≥ 2 team members AND proven in practice during activation |
| **MCP config** | **Approved by client's security team** AND has stable, tested connection |
| **Hook** | Working, tested, adds value for **whole team** (not just one developer's workflow) |
| **Subagent** | Proven in ≥ 1 real engagement scenario during activation |
| **Slash command** | Frequently used prompt pattern the team wants to preserve, not a one-off experiment |

**Anti-patterns**:
- ❌ "Bundle everything — it was all built during the activation"
- ❌ "Skip MCPs and subagents to reduce maintenance complexity" (that's preference, not governance)
- ❌ **"Label unreviewed MCP as 'experimental' and bundle it"** — the label doesn't substitute for security review. Developers assume bundled = safe.

### 17.5 — Two distribution scopes (governance layers)

**Don't couple these into one mega-plugin.** Different owners, different release cadences.

| Scope | Owner | Contents | Release cycle |
|---|---|---|---|
| **Team plugin** | Team CoE-managed shared registry | Team-specific Skills, hooks, MCPs, subagent specs | Team iterates without CoE approval |
| **Enterprise marketplace** | CoE-governed | Org-wide approved MCP configs, security hooks, compliance Skills | Stricter release cycle: CoE approves before pushing org-wide |

**Rule**: never couple team + enterprise into one plugin — a change to any component would require a full CoE release cycle. Keep them independent.

### 17.6 — SCIM integration & the "Day 1 governance pitch" ⭐

**Enterprise marketplace plugin workflow** (three steps):
1. **Create + approve** the plugin
2. **Publish** it to the marketplace
3. **Assign** it to relevant **SCIM groups** in Admin Console

**Result**: any developer provisioned into those SCIM groups **receives the approved configuration automatically** on Day 1. No manual install. No shadow tooling. **Access to the tool and access to the governed configuration arrive together.**

**The CISO pitch** (memorize the phrasing):
> *"Your security team approves the plugin, your IT team assigns it to the right SCIM groups, and every new developer inherits the approved configuration on their first day."*

### 17.7 — Dependency versioning (D3 + D5 reliability)

Three practices to establish with the CoE at Day 30:

1. **Pin MCP server versions in `plugin.json`.** MCP servers update independently; an upstream schema change can break workflows. Pin versions and let the CoE test + promote new ones deliberately.
2. **Version the plugin itself.** When CoE releases a new version, developers run `/plugin update`; version number tells support which config a team runs.
3. **Document the Day 30 package.** Record what's in the plugin + which MCP versions bundled + who owns it. This is the handoff document. **Without it, the plugin is a black box the CoE can't maintain.**

### 17.8 — True/false traps (Course 4 Lesson 8)

| Statement | Answer | Why |
|---|---|---|
| "Team plugin and CoE plugin should share a release cadence because they're distributed as a bundle" | **FALSE** | Separate owners, independent cadences. Coupling defeats the two-layer governance model. |
| "An unreviewed MCP config can be bundled if labeled 'experimental'" | **FALSE** | Label doesn't substitute for security review. Developers treat bundled components as safe. Bypasses the governance the CISO endorsed. |

### 17.9 — Course 4 Lesson 8 sim answer (Day 28 packaging)

**Scenario**: 5 components. Which to bundle?

| Component | Verdict | Reason |
|---|---|---|
| Security-auditor subagent (proven across 3 sprints) | ✅ Bundle | Passes subagent fitness |
| API documentation Skill (8 of 10 engineers using) | ✅ Bundle | Passes Skill fitness |
| Logging hook (tested, working) | ✅ Bundle | Passes hook fitness |
| Jira MCP config (IT-approved last week) | ✅ Bundle | Passes MCP fitness (security approved) |
| ISO 20022 Skill (2 of 10, still testing) | ❌ Leave in dev branch | Below Skill fitness threshold; revisit next sprint |

**The rule**: **proven + approved goes in**. Borderline stays in dev branch. Never bundle unapproved MCPs or untested Skills — every developer receives them on install.

### 17.10 — D3 packaging memory rules

- **"Plugin = one folder, one manifest, one install command, everything bundled."**
- **"Fitness first: proven usage + security approval, or it doesn't ship."**
- **"Team plugin ≠ CoE plugin: separate owners, separate release cadences."**
- **"SCIM groups + approved plugin = Day-1 governance."** (New devs get config automatically.)
- **"Pin MCP versions. Version the plugin. Document the package. Then hand off."**

**Cross-reference**: this ties together Blocks 13 (MCP), 14 (Skills), 15 (Hooks), 16 (Subagents) — the plugin is the packaging that makes all of them survive after the engagement ends. If a client asks "who owns this after Day 30?" — the answer is the CoE + the versioned plugin manifest.

---

## Block 18 — Managed Settings Security Controls ⭐⭐ (D3/D5 — Course 6 Lesson 1)

`managed-settings.json` complete reference — every field the security team can lock. **Sits above every other layer; no user or project setting can override it** (see Block 9.2).

### 18.1 — Delivery mechanisms (three ways to push)

| Mechanism | When to use | Client fit |
|---|---|---|
| **Server-managed** (Claude.ai admin console) | Central control without existing MDM. **Available on Teams + Enterprise** (Enterprise unlocks full feature set). | No Jamf/Intune in place |
| **MDM / OS policies** — macOS via Jamf managed prefs · Windows via Intune / Group Policy (registry) | Existing device management already in place | **FinCo (Jamf for macOS)** — natural fit |
| **File-based** (manual filesystem install) | Pilots · small deployments · staged testing | Non-scalable; plan the move to MDM before full rollout |

### 18.2 — Day 0 Auth controls ⭐

| Field | Purpose | FinCo mapping |
|---|---|---|
| **`forceLoginMethod`** | Enforces `"claudeai"` (SSO) or `"console"` auth. **Blocks API key login**, which bypasses SSO + audit controls | Set to `"claudeai"` so every login routes through Okta SSO |
| **`forceLoginOrgUUID`** | Login fails unless account belongs to specified org UUID. Prevents shadow personal accounts on company domain | Pins logins to corporate org — dev can't sign in with personal Claude account on work email |

**Rule**: whenever the client says "every account must trace to [SSO provider]" → `forceLoginMethod` + `forceLoginOrgUUID`. API keys bypass SSO by design.

### 18.3 — MCP controls (recap of Block 13.8)

| Field | Effect |
|---|---|
| **`allowedMcpServers`** | Allowlist of approved MCP server names. Empty array = total lockdown during review |
| **`allowManagedMcpServersOnly`** ⭐ | **Only admin-defined MCP servers can activate.** User-added servers blocked regardless of allowlist state. Category-level control. |

**Rule**: to close **the entire class** of "developer added their own MCP server" risk → `allowManagedMcpServersOnly: true`, NOT `deniedMcpServers` per-name (per-name only patches one server; new unapproved servers can still appear).

### 18.4 — Hook controls (new field pair)

| Field | Effect |
|---|---|
| **`allowManagedHooksOnly`** | Ships approved automation while blocking anything a developer wires up on their own. Category-level parallel to `allowManagedMcpServersOnly` |
| **`disableAllHooks`** | Kill switch. Blocks all hooks from running. |

### 18.5 — Permission controls (new)

| Field | Effect |
|---|---|
| **`allowManagedPermissionRulesOnly`** | Prevents users from overriding tool approval rules set by the admin |
| **`disableAutoMode`** | Stops developers from turning off approval prompts entirely — keeps human in the loop on tool calls in regulated environments |

**Rule**: for regulated clients (finance, healthcare) → `disableAutoMode: true`. Human-in-the-loop is not optional.

### 18.6 — Version enforcement (new — enforcement, not documentation)

| Field | Effect |
|---|---|
| **`requiredMinimumVersion`** | Claude Code **exits at startup** if installed version below this. Not a warning — a hard block. |
| **`requiredMaximumVersion`** | Claude Code exits at startup if installed version above this |

**Rule**: for tested-version compliance rules (SOC 2, ISO 27001) → these are the enforcement mechanism. `>= X.Y.Z` compliance policy becomes literal, machine-checked at boot.

### 18.7 — Org-wide CLAUDE.md via `claudeMd` ⭐⭐ (new key)

**The `claudeMd` key** in `managed-settings.json` injects **organization-wide instructions** into every session as **managed memory**.

- Loads **BEFORE** any project or user CLAUDE.md
- **Cannot be overridden** by lower layers (matches Block 10.2 rule)
- The place for **non-negotiable instructions** — not preferences a developer can quietly ignore

**Cross-reference with Block 10 CLAUDE.md hierarchy** — this is the **managed** level, above all others. Adding `claudeMd` to `managed-settings.json` is how an admin enforces org-wide instructions that Claude reads BEFORE any local CLAUDE.md file.

### 18.8 — Writing effective org CLAUDE.md (4 principles)

1. **Policy, not preferences.** Test: *"would violating this create a compliance/legal issue?"* Yes → org level. No → project/user level.
2. **Use Claude to draft.** Share the client's Acceptable Use Policy / data-handling guidelines with Claude → ask for a draft managed CLAUDE.md → review + tighten. Faster and calibrated to the client's own policy language.
3. **Avoid over-restriction.** Overly prescriptive instructions dilute the signal. If security adds 30 lines of stylistic rules alongside 3 compliance requirements, Claude tries to satisfy all equally and dilutes the important ones.
4. **Include the *why*.** Add rationale ("due to regulatory requirements", "per IP policy") alongside each constraint. Devs who understand *why* are less likely to work around it, and audits are easier.

### 18.9 — FinCo client scenario (Course 6 recurring context)

**FinCo Financial Services** — 1,800 devs, AWS-native (us-east-1 + us-west-2), Okta SSO, Jamf MDM.

**Three security non-negotiables**:
1. All data processing stays in approved AWS regions
2. Every developer account traces to Okta
3. Any new AI tooling clears a written security review

**Managed settings for FinCo** (memorize the mapping):

| Requirement | Field |
|---|---|
| Every login through Okta | `forceLoginMethod: "claudeai"` + `forceLoginOrgUUID: <FinCo UUID>` |
| Only approved MCP servers | `allowManagedMcpServersOnly: true` + populated `allowedMcpServers` |
| Human-in-loop on tool calls | `disableAutoMode: true` |
| Only approved hooks | `allowManagedHooksOnly: true` |
| Version compliance | `requiredMinimumVersion` + `requiredMaximumVersion` |
| Org-wide compliance instructions | `claudeMd: <finco-org-instructions>` |
| Delivery | Jamf → macOS managed preferences |

### 18.10 — Sim answer (Course 6 Lesson 1)

**Scenario**: developers connected a personal GitHub MCP server accessing repos outside the approved list. One setting to close the **category** of risk?

- ✅ **`allowManagedMcpServersOnly: true`** — closes the whole class ("developer added their own server")
- ✗ `disableAllHooks: true` — wrong category (hooks, not MCP)
- ✗ Add server name to `deniedMcpServers` — patches ONE server; next unapproved one still slips through
- ✗ `forceLoginMethod: "claudeai"` — auth control, doesn't restrict MCP servers

**Trap rule**: **category-level fixes beat symptom-level fixes** whenever the exam frames the problem as "close the class of risk" or "the security team keeps seeing new instances." Per-name deny lists are always the wrong answer when the client's issue is a policy gap, not a specific server.

### 18.11 — Memory rules

- **"managed-settings.json is the file users cannot override."**
- **"When a client says 'no personal servers, ever' → `allowManagedMcpServersOnly: true`. Category, not per-name."**
- **"API key login bypasses SSO — block it via `forceLoginMethod`."**
- **"`claudeMd` in managed-settings loads BEFORE any local CLAUDE.md. Non-overridable."**
- **"`requiredMinimumVersion` is enforcement, not documentation — Claude Code exits at startup."**
- **"Regulated client → `disableAutoMode: true`. Human-in-the-loop is not optional."**

---

## Block 19 — Permission System & Roles ⭐⭐ (D3 core — Course 6 Lesson 2)

Cross-ref: Block 11.2 has the permission evaluation order (Deny → Ask → Allow → default Ask). Block 18.5 has the managed-settings toggle. This block has the **classification principles + role hierarchy + ownership model**.

### 19.1 — The Allow/Ask/Deny classification principle ⭐

Operations are classified by **risk**, not by "how often does the developer want a prompt":

| Category | Rule | Examples |
|---|---|---|
| **Allow** | **Non-destructive, high-frequency** — reversible, local, no external side effects | Run test suite (`npm test`) · read source file (`cat src/app.js`) |
| **Ask** | **Irreversible OR external network call OR shared-resource write** — first-use gate keeps boundary visible | `git push origin` (irreversible, shared) · POST to Jira API (external) |
| **Deny** | **Catastrophic and irreversible** — no legitimate use in an assisted workflow | `rm -rf /` (nothing recoverable) · production-config wipes |

**Design principle**: **"allow non-destructive high-frequency; ask on irreversible/external; deny what should never run."** Gating everything defeats the purpose — the value is deliberate classification, not universal prompting.

**Locking mechanism** (from Block 18.5): `allowManagedPermissionRulesOnly: true` prevents users from adding/modifying their own allow/ask/deny entries.

### 19.2 — Two-bucket ownership model ⭐⭐ (client security-review framing)

For every question about "who's responsible for what?" in a security review, split into two buckets:

**Anthropic owns** (client cannot configure or disable):

| Layer | What it is |
|---|---|
| **Model safety** | Constitutional AI, RLHF safety training, weight-level refusal, usage policy enforcement |
| **Platform integrity** | Runtime classifiers, pre-release eval, platform-level protections (universal, not per-tenant) |

*"In a security review: this is the line you point to when a client asks whether they can weaken safety behavior. They can't, and that's a feature."*

**Client configures**:

| Layer | What it is |
|---|---|
| **Operation gating** | Allow/Ask/Deny rules, role-based access, connector consent, permission policies |
| **Audit & governance** | Managed settings, SSO + SCIM, data retention, Compliance API, review workflows |

**Rule**: when a client asks "can we weaken/turn off X?" — if X is Anthropic's layer, the answer is no (and that's the point). If X is the client's layer, show them the field.

### 19.3 — Four built-in roles ⭐

| Role | Scope | Who typically holds it |
|---|---|---|
| **Primary Owner** | Full org control · billing · all settings. **One per org.** | The person accountable for the whole deployment |
| **Owner** | Member management · connector approval · **edits `managed-settings.json`** · day-to-day governance | Security or platform team lead |
| **Admin** | (between Owner and Member — implied intermediate admin capabilities) | Team leads |
| **Member** | Uses Claude Code · configures **personal settings within admin bounds** · cannot override managed settings | Regular developers (all 1,800 at FinCo) |

**Rule**: for any "who can change this?" question, use this mapping:
- If it's in `managed-settings.json` → **only Owner** can change it
- If it's a user-configurable setting → **user** can change it, but only within the constraints the Owner already set

### 19.4 — Connector consent (separate governance gate) ⭐

**OAuth-scoped MCP connections require Owner approval per-user** before activating that user's resource access.

**Two gates, not one**:

| Gate | Governs |
|---|---|
| **MCP allowlist** (`allowedMcpServers`) | Which servers **may exist** in the deployment |
| **Connector consent** | Whether a **specific user's resources** can actually be accessed by an approved server |

**Consequence**: even if an MCP server is on the allowlist, a specific user's OAuth grant requires separate consent. This gives per-user granular control on top of the org-wide allowlist.

### 19.5 — Roles vs Groups (D3 organizational modeling)

| | **Roles** | **Groups** |
|---|---|---|
| **Purpose** | Access controls — *what a user can do* | Multi-purpose containers of users |
| **What they do** | Define permissions (4 built-in + custom) | Govern **access** (via role assignment) · **spend limits** by team/dept · **plugin distribution** targeting |
| **Assignment** | Additive across groups a user belongs to | Manual creation OR SCIM-synced from IdP |
| **Custom** | Admins can create custom roles beyond the 4 built-ins | — |

**Trap**: groups are **not purely** access-control containers. A group might exist just for spend attribution with **no role assignment at all**. Any exam scenario saying "groups map 1:1 to permissions" is wrong.

### 19.6 — Roles are additive → over-assignment risk

**Rule**: a user in multiple groups **accumulates all roles from each group**. Over-assigning groups → unintended permission accumulation.

**Right question** on most deployments: *"Which group owns this function, and does this person belong in it?"* — NOT *"What role does this person need?"* Function-first thinking prevents role sprawl.

### 19.7 — Day-1 governance at scale (current best path)

The current mechanism for controlling which connectors/skills a group can access:

**Bundle approved tools into an enterprise plugin + assign that plugin to relevant groups via RBAC.**

Ties together:
- **Block 17** (plugin structure + fitness test)
- **Block 18** (managed-settings enforcement)
- **This block** (RBAC via groups)

Engineers get pre-approved connectors by default. **Governed and deployed before anyone logs in.**

### 19.8 — On the roadmap: connector-level role controls (not yet)

- **Planned**: restrict which roles can use a specific connector · scoped capabilities per connector
- **Current model**: on/off access per connector (no role-level granularity yet)
- **Workaround today**: plugin + RBAC via groups (from 19.7)

**Client conversation**: when asked "can we control connector access by role?" — flag as **coming**, offer plugin + RBAC pattern as **current path**.

### 19.9 — Course 6 Lesson 2 sim answer ⭐

**Scenario**: FinCo dev workflow — (1) auto-run tests after save · (2) push commits to corporate GitLab · (3) call internal Jira API for ticket status.

**Correct classification**: **B — Test allow · GitLab push ask · Jira API call ask**

| Op | Category | Why |
|---|---|---|
| Test suite (`npm test`) | **Allow** | Non-destructive, reversible, local |
| GitLab push | **Ask** | **Irreversible + shared repo** — needs deliberate sign-off |
| Jira API call | **Ask** | External network call — first-use gate keeps boundary visible |

**Trap**: option C (push = allow, API = ask) is close but wrong. **Even to a "corporate" GitLab, push is irreversible and touches a shared resource.** Ask.

**Trap**: option D (all three = ask) creates alert fatigue. Gating everything defeats the purpose of classification.

### 19.10 — True/false traps

| Statement | Answer | Why |
|---|---|---|
| "Member can configure their own personal `settings.json`" | **TRUE** | Members control their personal layer, within managed bounds |
| "Admin can prevent users from setting own allow/deny via managed-settings" | **TRUE** | `allowManagedPermissionRulesOnly: true` locks the permission model |
| "Claude Code always asks approval before ANY bash command" | **FALSE** | `Allow` category runs silently; only Ask/Deny trigger prompts |
| "Groups function purely as access-control containers — 1 group ↔ 1 set of permissions" | **FALSE** | Multi-purpose: RBAC · spend limits · plugin distribution. Groups can exist with no role assignment at all. |

### 19.11 — Memory rules

- **"Allow non-destructive high-frequency · Ask irreversible/external · Deny catastrophic."**
- **"Anthropic owns safety + platform. Client owns gating + audit."** (Two-bucket model)
- **"Primary Owner: one per org, accountable. Owner: edits managed-settings. Member: personal only, within bounds."**
- **"Two MCP gates: allowlist says WHICH servers may exist · consent says WHO can access."**
- **"Roles are additive across groups. Over-assign → unintended permission accumulation."**
- **"Push to shared repo = ASK, always. External API call = ASK, always."** (First-use gate)
- **"Plugin + RBAC via groups is the current scale-governance path. Connector-level role controls are roadmap only."**

---

## Block 20 — Sandbox: Filesystem + Network Scoping ⭐⭐ (D3/D5 — Course 6 Lesson 3)

### 20.1 — Sandbox mental model (reframe)

**The sandbox is NOT a restriction on capability. It's what LETS you authorize autonomous operation.**

Three things the sandbox does:

| Function | Effect |
|---|---|
| **Define boundaries** | Explicitly scope which directories + hosts are accessible. No ambiguity during an autonomous task. |
| **Reduce approval prompts** | **Counterintuitive**: good scoping *increases* autonomy. Inside a trusted boundary, nothing to ask about. Remaining prompts are the ones that matter. |
| **Contain failure** | Blast radius bounded by the boundary you drew. Client asks "worst case?" → the boundary is your answer. |

**Rule**: the sandbox is the security team's answer to *"can we authorize autonomous operation?"* Without it, you can't defend the deployment in a security review.

### 20.2 — Five sandbox keys (memorize the exact paths in `managed-settings.json`)

```json
{
  "sandbox": {
    "filesystem": {
      "allowWrite": [ ... ],   // paths Claude may read + write
      "denyWrite":  [ ... ],   // never modify (even inside allowed parent)
      "denyRead":   [ ... ]    // never read (credential stores)
    },
    "network": {
      "allowedDomains": [ ... ],   // approved endpoints; supports wildcards (*.finco.internal)
      "deniedDomains":  [ ... ]    // explicit block; takes precedence over allowedDomains
    }
  }
}
```

| Key | Purpose |
|---|---|
| **`sandbox.filesystem.allowWrite`** | Project working directories where Claude may operate |
| **`sandbox.filesystem.denyWrite`** | Never modify (Dropbox sync folders, protected paths) |
| **`sandbox.filesystem.denyRead`** | Never read (`.aws/credentials`, `.env`, secret stores) |
| **`sandbox.network.allowedDomains`** | Internal registries, approved corporate endpoints (wildcards OK) |
| **`sandbox.network.deniedDomains`** | Personal cloud storage, public registries, exfiltration paths |

### 20.3 — Precedence rules ⭐

- **`deniedDomains` takes precedence over `allowedDomains`.** Both listed → deny wins.
- **`denyRead` / `denyWrite` enforced even inside allowed paths.** If `~/finco-app` is `allowWrite` but `~/finco-app/.env` is `denyRead`, Claude cannot read the env file despite the parent being allowed.

### 20.4 — Two-layer egress control (D5 reliability + platform frame)

| Layer | Owner | What it does |
|---|---|---|
| **Baseline** | **Anthropic** (universal) | Domain allowlists · URL sanitization · exfiltration defense — applies to every deployment |
| **Org-level** | **Client** in `managed-settings.json` | The 5 sandbox keys above — configured once, applies across the deployment |

**Key clarification** (exam-testable): the sandbox is **NOT a per-developer setting**. Security team owns the network boundary at the org level. Individual devs can't loosen it locally.

### 20.5 — Common resource categorizations (memorize the mapping)

| Resource type | Correct sandbox slot | Why |
|---|---|---|
| Project working directory (`~/finco-app`) | **`filesystem.allowWrite`** | Task needs read + write |
| Cloud sync folders (`~/Dropbox`, `~/OneDrive`) | **`filesystem.denyWrite`** | Data-exfiltration path even if inside allowed parent |
| Credential stores (`~/.aws/credentials`, `~/.ssh/`, `.env`) | **`filesystem.denyRead`** | No place in an assisted coding task |
| Internal registries (`npm.finco.internal`, `nexus.finco.internal`) | **`network.allowedDomains`** | Approved tooling task needs |
| Public registries (`registry.npmjs.org`, `pypi.org`) | **`network.deniedDomains`** | Even if not in allowlist by default, **explicit deny creates the audit record** the security team needs |

### 20.6 — Course 6 Lesson 3 sim answers ⭐

**Sim 1 — "Prevent Claude from touching `~/Dropbox` while allowing test-run + git commit"**:

- ✅ **`managed-settings.json` with directory deny rule (`denyWrite`)**
- ✗ CLAUDE.md instruction to avoid the folder — that's *guidance*, not policy; user can ignore or Claude can slip up
- ✗ User's personal `settings.json` — dev could remove it; not admin-enforced
- ✗ "Not configurable" — always wrong when sandbox exists

**Rule**: **settings files are POLICY. Prompt instructions are GUIDANCE.** When a client asks where a control lives → the answer is *settings*, not *instructions*.

**Sim 2 — "Internal npm registry access + block public registries"**:

- ✅ **Both**: add `npm.finco.internal` to `allowedDomains` AND public registries to `deniedDomains`
- ✗ Remove all network restrictions — defeats the sandbox
- ✗ `allowedDomains` only, rely on default block — security team wants an **explicit deny record** in the audit trail. Implicit block ≠ auditable
- ✗ Proxy route instead — proxy is a valid network architecture but doesn't replace the sandbox config decision

**Rule**: **explicit allow + explicit deny = audit trail.** Two entries, one for what's approved, one for what's specifically blocked. Even if the default would block the domain, the explicit entry creates the record.

### 20.7 — Memory rules

- **"Sandbox enables autonomy. It's not a restriction — it's the boundary that lets you authorize."**
- **"5 sandbox keys: allowWrite · denyWrite · denyRead · allowedDomains · deniedDomains."**
- **"Deny always wins. Deny enforced even inside an allowed parent."**
- **"Sandbox is org-level via managed-settings. Never per-developer."**
- **"Explicit deny creates the audit trail. Implicit block is not auditable."**
- **"Settings are policy. Prompt instructions are guidance. Client boundary questions → answer with settings."**
- **"Cloud sync = denyWrite. Credential stores = denyRead. Internal registries = allowedDomains. Public registries = deniedDomains."**

---

## Block 21 — Identity Governance: SSO, SCIM, Network Controls ⭐⭐ (D3/D5 — Course 6 Lesson 4)

### 21.1 — SSO fundamentals

- **Protocols**: SAML 2.0 or OIDC — routes all users through the client's IdP
- **Governance benefit**: one identity · one audit trail · one off-boarding flow
- **Deprovisioning**: developer leaves → Claude access revoked with everything else via IdP

**Critical rule** ⭐: **"SSO alone is not enough."** Without domain capture, users can still sign up with a personal Gmail on the company domain and land in a shadow workspace. Enable **domain capture** to close this gap.

### 21.2 — Three provisioning models (know the tradeoffs)

| Model | What it does | Deprovisioning | When to use |
|---|---|---|---|
| **SCIM** ⭐ **recommended default** | IdP-driven automatic sync for full lifecycle: provisioning · group changes · deprovisioning | **AUTOMATED** — key deciding factor | Any production deployment at scale |
| **JIT** (Just-in-Time) | User created on first SSO login | ❌ **NONE** — creates accounts, never removes them. No group sync either | Getting started only; leaves lifecycle half-managed |
| **Manual** | Admin-managed seat invitations | Manual, error-prone | Pilots of 20–50 users only; never destination |

**The deciding factor is automated deprovisioning.** Any exam question about "at-scale governance" or "security-review-defensible" points to **SCIM**, regardless of size.

**SCIM rollout pattern**: pilot 50–100 users → monitor 2–4 weeks → expand by department → org-wide. Run identity config **in parallel with pilot design**, not after.

### 21.3 — Domain capture (the "SSO alone" gap-closer)

**Without domain capture**: a developer can sign up with a personal Gmail (or personal Claude account tied to work email) and bypass SSO entirely — the account exists but doesn't route through the IdP.

**With domain capture**: all logins from the company domain automatically route into the corporate workspace. No individual configuration required.

**Rule**: SSO + domain capture is **one pair of controls**, not two independent ones. Deploy them together.

### 21.4 — Network controls (two separate questions)

| Control | Question it answers | Effect |
|---|---|---|
| **IP allowlisting** | *"Who can reach Claude at all?"* | Restricts Claude access to corporate IP ranges (VPN-gated / on-prem) — network-perimeter enforcement |
| **Tenant restrictions** ⭐ | *"Which Claude org can they log into?"* | Prevents users on corporate network from logging into **unauthorized Claude organizations** — blocks shadow AI even when IP allowlisting is active |
| **Domain capture** | (identity, per 21.3) | Forces company-domain logins into the corporate workspace |
| **Session security** | Session hygiene | Configurable session timeout + re-auth intervals |

**Trap**: IP allowlisting alone doesn't stop shadow AI. A developer connected via VPN can still log into a *personal* Claude workspace. **Tenant restrictions is what closes that loop.** Both should be in scope for enterprise deployments where shadow AI is a concern.

### 21.5 — Go-live requirements (from Lesson 4 sim, memorize the four musts)

For an 1,800-dev FinCo-style enterprise, **required before go-live**:

1. **SSO through the corporate IdP** (Okta at FinCo) — every account traces back to IdP
2. **Domain capture** — closes the personal-account loophole (SSO alone doesn't do it)
3. **SCIM provisioning** — 1,800 devs is not a manual-invite scale; automated deprovisioning is non-negotiable at scale
4. **IP allowlisting to corporate VPN** — network-layer enforcement alongside SSO

**Post-launch (can wait)**:
- Session timeout configuration (post-launch optimization; doesn't block go-live)

**Wrong approach**:
- **Manual seat invitations at scale** — not viable for 1,800 devs; SCIM already handles it

**Rule**: go-live checklist = **SSO + domain capture + SCIM + IP allowlisting**. Anything you'd defer (session timeout tuning) or hand-do (manual invites) is a wrong answer to "what's required before go-live?"

### 21.6 — FinCo alignment (Course 6 recurring scenario)

Ties Block 21 controls to FinCo's three non-negotiables (Block 18.9):

| FinCo requirement | Control |
|---|---|
| Every developer account traces to Okta | SSO (SAML/OIDC) + Domain capture + `forceLoginOrgUUID` (Block 18.2) |
| Access disappears when employment ends | **SCIM automated deprovisioning** |
| Corporate tooling must route through VPN | IP allowlisting to corporate ranges |
| No shadow AI on corporate network | **Tenant restrictions** (blocks unauthorized Claude orgs from VPN) |

### 21.7 — Memory rules ⭐

- **"SSO alone is not enough. Domain capture closes the personal-account loophole."**
- **"SCIM is the default at scale. JIT creates accounts but never removes them."**
- **"IP allowlisting says WHO can reach Claude. Tenant restrictions say WHICH Claude org they may use."**
- **"Go-live 4 = SSO + Domain capture + SCIM + IP allowlisting. Session timeout waits. Manual invites don't scale."**
- **"Deprovisioning is the deciding factor. Any 'audit-defensible at scale' answer = SCIM."**
- **"Run identity config in parallel with pilot design, not after."**

---

## Block 22 — Data Controls: ZDR, Custom Retention, No-training, HIPAA ⭐⭐ (D5 — Course 6 Lesson 5)

Cross-ref: Block 7.10 already has the ZDR *precise scope* from the Corvane Health sim (what ZDR covers/doesn't/disables/enables). This block adds the *comparison framework* + custom retention + surface defaults + parsing heuristic.

### 22.1 — The three data controls (memorize the comparison)

**Clients often ask for all three when they need one.** Know the distinction cold.

| Control | Type | What it is | Self-serve? |
|---|---|---|---|
| **No-training commitment** | Default policy | Enterprise data never used to train Claude models. Applies to **all enterprise plans by default**. | Yes — already on, no config |
| **Custom data retention** | Admin-set | Admin configures retention windows per surface, **1 day to indefinite**. Console-configurable. | Yes — via admin console |
| **ZDR (Zero Data Retention)** | **Contract** | Anthropic stores **NO inputs or outputs**. Requires separate Anthropic agreement. | **No — not self-serve** |
| **HIPAA path** | **Contract** | **BAA + ZDR both active.** BAA extends automatically to Claude Code only when ZDR is on. | **No — sales cycle** |

**Rule of confusion** ⭐: clients ask for ZDR when they usually mean **custom retention**. Distinguish:
- **Custom retention**: *"You control how long it's held"* — configurable
- **ZDR**: *"Anthropic holds nothing at all"* — contractual

**Both can coexist with no-training**, which all enterprise clients already have.

### 22.2 — HIPAA dependency ⭐

**A BAA alone is NOT sufficient for Claude Code HIPAA coverage.** Full requirement:

```
Healthcare client needs Claude Code under HIPAA
        ↓
   BAA + ZDR must BOTH be active
        ↓
   Then BAA automatically extends to Claude Code
```

**Anti-pattern**: assuming a signed BAA covers Claude Code by itself. Doesn't. ZDR is the prerequisite.

**Rule**: healthcare client in scope → raise **both BAA and ZDR** with the Anthropic AE early. This is a sales-cycle conversation, not a go-live checkbox.

### 22.3 — Parsing the client ask (sales heuristic) ⭐

When a client asks about data, the words are often ambiguous. Distinguish first, then answer:

| Client says… | They usually mean… | Control |
|---|---|---|
| *"How long do you hold on to our conversations?"* | Duration + control | **Custom retention** |
| *"Can we ensure our code is never used to improve your models?"* | Model training | **No-training** (already on) |
| *"Anthropic must not store our inputs or outputs at all, anywhere"* | Literally zero storage | **ZDR** (contract) |
| *"We need Claude Code covered under our BAA"* | HIPAA | **BAA + ZDR** (both) |

**Discovery question** (memorize the phrasing): *"Are you concerned about Anthropic staff accessing your data, or about data being used to train future models?"* The answer tells you which lever they actually need.

### 22.4 — Default retention by surface ⭐ (the go-live surprise)

Memorize the 4 surface defaults — this is exam-testable:

| Surface | Default | Configurable? |
|---|---|---|
| **Claude.ai Enterprise** | **Indefinite** by default (admin-configurable, minimum 30 days) | Yes |
| **Claude Code** | **Indefinite** if no policy set — configure BEFORE go-live | Yes |
| **Cowork** (desktop productivity agent) | **Local device only** — no server-side retention | N/A (client-side) |
| **Office Agents** (MS Office integrations) | **30-day product-enforced auto-deletion** | **No — NOT configurable** |

**The go-live surprise**: default for both Claude.ai Enterprise and Claude Code is **indefinite**. If a client expects a bounded window, **someone has to set it**. Don't assume a shorter default exists.

**Rule for exam**: any question about "how long is data kept?" → answer depends on **which surface + whether admin has configured it**. The default is indefinite for the two configurable server-side surfaces; only Office Agents has a fixed 30-day product enforcement.

### 22.5 — ZDR is not self-serve (timing rule)

**Rule**: ZDR requires a separate Anthropic agreement — **not something you toggle in the admin console**. Raise it in the **sales cycle**, not at go-live. A client expecting to enable it in-console will be blocked waiting on contract.

**Anti-pattern**: promising ZDR at go-live when it hasn't been contractually arranged.

### 22.6 — True/false traps (Course 6 Lesson 5)

| Statement | Answer | Why |
|---|---|---|
| "ZDR means the org's data is not used to train Claude" | **FALSE** | That's **no-training**. ZDR is stronger — no storage at all. Two separate controls. |
| "Enterprise can configure Claude Code to delete after 7 days" | **TRUE** | Custom retention is 1 day to indefinite; 7 is valid. |
| "Healthcare needs BAA + ZDR both for Claude Code HIPAA coverage" | **TRUE** | BAA alone insufficient; ZDR must also be active. |

### 22.7 — Memory rules ⭐

- **"Three levers: no-training (default) · custom retention (admin) · ZDR (contract)."**
- **"No-training ≠ ZDR. No-training already on; ZDR is a separate contract for 'nothing stored at all.'"**
- **"HIPAA on Claude Code = BAA + ZDR. A BAA alone is not enough."**
- **"Default retention is indefinite for Claude Code + Claude.ai Enterprise. Set it before go-live."**
- **"Office Agents = 30-day fixed. Cowork = local only. Both non-configurable server-side."**
- **"ZDR is not self-serve — sales cycle, not console toggle."**
- **"Client says 'how long you keep our data' → custom retention. Client says 'store nothing at all' → ZDR. Client says 'never train on our code' → no-training (already on)."**

---

## Block 23 — Compliance, Trust Center & Ownership Model ⭐⭐ (D5 capstone — Course 6 Lesson 6)

Cross-refs: **Block 7.10** already has the certification list from the Corvane sim; **Block 19.2** has the two-bucket ownership model. This block adds the *grouping-by-purpose* framing + operational controls (audit logs, Compliance API) + trust-center rule.

### 23.1 — Certification stack, grouped by purpose (memorize the buckets)

Full list (available at `trust.anthropic.com`):

| Purpose | Certifications | How to answer |
|---|---|---|
| **Security baseline** | SOC 2 Type 2 · ISO 27001:2022 | *"Yes, both, audited annually — see trust.anthropic.com"* — the opener every questionnaire uses |
| **Cloud + privacy** | ISO 27017 (cloud security) · ISO 27018 (cloud privacy) · CSA STAR Level 2 | Beyond SOC 2 — same move, direct to trust center |
| **Regulated industries** | HIPAA (BAA available) · **FedRAMP High (Claude for Government only!)** · GDPR | Framework-specific. Flag FedRAMP scope caveat. |
| **Standards** | NIST 800-171 · **ISO 42001:2023 (AI management systems)** | ISO 42001 = AI-specific — strong signal for AI-governance maturity evals |
| **UK-specific** | UK Cyber Essentials | Regional cert for UK-based clients |

### 23.2 — The trust center rule ⭐⭐

**Rule**: for any client certification / attestation / compliance-artifact question → **direct them to `trust.anthropic.com`**.

- Never quote certification details from memory — trust center is always current
- **The site is always the source of truth**, not your recall
- Full set: reports · attestation letters · questionnaire responses · pen-test summaries

### 23.3 — FedRAMP scope caveat ⭐ (exam-testable trap)

**FedRAMP High applies to Claude for Government, NOT standard Enterprise plans.**

Trap answer: *"Yes, we're FedRAMP High"* on a standard Enterprise deployment question. **Always confirm which product the client needs** before quoting FedRAMP coverage.

**Corollary**: any true/false statement claiming "FedRAMP applies to all Enterprise plans" is **FALSE**.

### 23.4 — Two operational controls (Audit Logs + Compliance API) ⭐

**Neither is configured by default. Both are Enterprise features.**

| Control | Purpose | Retention | Export |
|---|---|---|---|
| **Audit logs** | User activity · conversations · admin changes | **180-day rolling window** | **SIEM export available** |
| **Compliance API** | Programmatic access to conversation content for DLP, eDiscovery, legal hold | **Up to 6 years** | Programmatic access |

**Rule**: **configure access to both during pre-launch setup**. Logs accumulate **from first use**, so waiting to configure means the first weeks of data have no admin access.

**Trap**: neither exists by default. Any exam question implying "audit logs are on out of the box" is wrong at the *access* level (log data may exist but admin access to it isn't automatic).

### 23.5 — Client questionnaire routing (the 3-way answer) ⭐⭐

For every security-review question, route it to one of three answers:

| Question type | Route to | Example |
|---|---|---|
| **"Do you hold [certification]?"** | **`trust.anthropic.com`** | SOC 2, ISO 27001, HIPAA BAA — direct to the trust center |
| **"Can admins disable/reconfigure [Anthropic's control]?"** | **Anthropic owns it** — cannot be disabled | Runtime classifiers · Constitutional AI · usage policy enforcement · pre-release eval |
| **"Where is [client control] configured?"** | **Client configures it** — via managed settings / admin console | Retention windows · SSO/SCIM · audit log access · connector governance · IP allowlist · permission rules |

**Rule**: know before the client asks. Answering hesitantly = losing credibility in the room.

### 23.6 — Client vs Anthropic ownership recap (see Block 19.2 for full model)

**Anthropic owns** (cannot be disabled):
- Model safety (Constitutional AI, RLHF, weight-level refusal, usage policy enforcement)
- Runtime classifiers
- Platform integrity + pre-release eval

**Client configures** (via managed settings + admin console):
- Managed settings (Block 18)
- SSO + SCIM (Block 21)
- Data retention windows (Block 22)
- Audit log access + Compliance API (this block)
- Connector governance (Block 13.7–13.10)
- IP allowlisting + tenant restrictions (Block 21.4)
- Permission rules (Block 19)

### 23.7 — True/false traps

| Statement | Answer | Why |
|---|---|---|
| "FedRAMP High authorization applies to all Claude Enterprise plans" | **FALSE** | Claude for Government only |
| "A client's system prompt can reconfigure runtime safety classifiers" | **FALSE** | Anthropic-owned floor; no config can go below it |
| "SOC 2 Type 2 reports are publicly available at trust.anthropic.com" | **TRUE** | Full reports + attestation letters live there |

### 23.8 — Memory rules ⭐

- **"Trust center for certifications. Anthropic-owned for the floor. Managed settings for everything else."**
- **"FedRAMP = Claude for Government only. Standard Enterprise is NOT FedRAMP-covered."**
- **"ISO 42001:2023 = AI-specific. Signal for AI-governance maturity evaluations."**
- **"Audit logs: 180-day rolling · SIEM export · Configure access BEFORE go-live."**
- **"Compliance API: 6-year retention · programmatic · Enterprise feature · not default."**
- **"Every certification question → `trust.anthropic.com`. Never quote from memory."**
- **"Every 'can we disable X?' about runtime safety → NO, and that's a feature."**

---

### Course 6 (Security & Governance) — complete map

You now have the full Course 6 governance stack across Blocks 18–23:

| Block | Lesson | Focus | Client answer |
|---|---|---|---|
| **18** | L1 | Managed settings fields | "Fields live in `managed-settings.json`" |
| **19** | L2 | Permissions + roles | "Two-bucket model + four roles + connector consent" |
| **20** | L3 | Sandbox | "5 keys · deny > allow · org-level only" |
| **21** | L4 | Identity governance | "SSO + Domain capture + SCIM + IP allowlist + Tenant restrictions" |
| **22** | L5 | Data controls | "3 levers + HIPAA needs BAA + ZDR · default retention indefinite" |
| **23** | L6 | Compliance + trust | "trust.anthropic.com for certs · 3-way routing · FedRAMP caveat" |

**One master framing rule** that covers 80% of Course 6 questions:

> **"For any security-review question: route to `trust.anthropic.com` (certifications), Anthropic-owned (can't disable), or Client configures (managed-settings.json + admin console). Three answers, always."**

---

## Block 24 — Winston's Glossary (from ChatGPT sync, v2.0 · 2026-07-16)

The living glossary you've been co-authoring with ChatGPT. Preserved verbatim in your structure. Anchors examples to your analytics work (Traffic Agent · Business Review Orchestrator · QC severity rubric).

Cross-refs: Block 16 (Subagents mechanics) · Block 14 (Skills patterns) · Block 15 (Hooks + enforcement spectrum) · Block 22 (Data controls) · Block 19 (Ownership model).

### 24.1 — Foundation Models

| Term | Plain-English meaning | Example |
|---|---|---|
| **LLM — Large Language Model / Foundation Model** | The core model that predicts and generates language, code, and reasoning | Claude, GPT, Gemini |
| **Pre-training** | Large-scale initial training that gives the model broad language, coding, knowledge, and reasoning capability | Claude learns general analytics and business concepts |
| **Post-training** | Training after pre-training that shapes instruction-following, tool use, safety, and reasoning behavior | Claude learns to follow QC rules and use tools |
| **Hallucination** | A plausible-sounding claim that is unsupported, invented, or wrong | Claiming inventory caused a decline without evidence |
| **Grounding** | Connecting claims to trusted evidence or approved sources | Every factual claim links to an evidence ID |
| **Deterministic** | Same input → fixed rules → same result | SQL calculates revenue variance |
| **Non-deterministic** | Same input may produce different but still valid outputs | Claude writes slightly different executive summaries |

### 24.2 — Agent Architecture

| Term | Plain-English meaning | Example |
|---|---|---|
| **Agent** | An AI worker that can reason, use tools, and complete a task | Traffic Agent |
| **Agentic AI** | AI that plans and executes multi-step work toward an objective | Builds an end-to-end business review |
| **Orchestrator / Parent Agent** | Coordinates specialist agents, tools, sequencing, and recovery | Business Review Orchestrator |
| **Subagent** | Specialised child agent spawned by a parent; returns structured results (cross-ref Block 16) | Security Auditor · Product Agent |
| **Parallel Claude Instances** | Independent Claude sessions working separately, not communicating (cross-ref Block 16.1) | QC build in one instance · docs in another |
| **Worker Agent** | Executes a bounded specialist task | SQL extraction agent |
| **Synthesis Agent** | Combines multiple findings into one conclusion or recommendation | Creates executive performance narrative |
| **Domain Agent** | Specialist agent focused on one business domain | Traffic · Product · CRM · Media |

### 24.3 — Compliance & Data Governance (Section 12)

| Term | Plain-English meaning | Example |
|---|---|---|
| **BAA — Business Associate Agreement** | A US contract required under HIPAA when a vendor handles PHI on a covered entity's behalf | Contract required when the vendor may process PHI |
| **HIPAA — Health Insurance Portability and Accountability Act** | US healthcare privacy/security law covering PHI and regulated entities | Determines whether healthcare data needs HIPAA controls |
| **PHI — Protected Health Information** | Individually identifiable health information protected under HIPAA | Patient diagnosis linked to an identity |
| **No-training** | Policy: customer inputs and outputs are not used to train or improve foundation models. **Separate from retention.** | Business data may be retained for service/safety, but not used for model training |
| **Custom Retention** | Organization-configurable policy: how long customer content is stored before deletion | Enterprise admin selects approved retention period |
| **Retention vs Training** | **Retention** = how long data is stored · **No-training** = whether that data is used for model improvement | 30-day retention can still be no-training |

Cross-ref Block 22 for the full three-lever framework (no-training / custom retention / ZDR) + HIPAA path (BAA + ZDR both required).

### 24.4 — Winston's 10 Golden Rules ⭐⭐ (personal design principles)

Rules built from your architecture experience. These are the ones to say out loud before making design calls on the exam.

1. **Use deterministic code for calculations and LLMs for reasoning.** — Official metrics stay in SQL or Python.
2. **Every factual claim must be grounded in evidence.** — Require evidence IDs.
3. **Normalize all agent outputs into a common schema.** — Traffic · Product · CRM return compatible objects.
4. **Keep subagent contexts isolated; return structured summaries, not raw reasoning.** — Main agent receives findings, not full audit detail.
5. **Validation checks correctness · QC judges quality · evals improve the system over time.** — Separate run-level checks from portfolio-level measurement.
6. **Use explicit rules before adding more examples.** — State P1/P2 behavior directly. (Ties to Block 14.11 Skills authoring rule.)
7. **Choose the right skill pattern: consistency · reliable access · capability gap.** — Diagnose the failure before building the skill. (Ties to Block 14.4 P1/P2/P3 tree.)
8. **Use hooks and validators to enforce critical behavior, not instructions alone.** — Block protected writes with PreToolUse. (Ties to Block 15's enforcement spectrum.)
9. **The orchestrator coordinates; specialists specialise.** — Keep Traffic and Product responsibilities bounded.
10. **Treat failures as structured data, not vague exceptions.** — Return error context, severity, origin, and next action. (Ties to Block 16.6 subagent failure handling.)

### 24.5 — Missing sections (pending)

The paste you sent had 129 lines hidden between §2 and §12 — likely Sections 3–11. When you paste them, I'll append here. Candidate topics based on your v2.0 structure:
- §3–5: Reasoning · Tool Use · Retrieval (RAG)
- §6–8: Prompt Engineering · Structured Output · Evaluation
- §9–11: Deployment · Safety · Reliability

---

## Block 25 — Course 7 L1: Claude Enterprise Administration (Pre-kickoff)

**One-liner:** Role mismatches + $0 spend limit are the two Day-1 failure causes. Catch both before kickoff, not at it.

Cross-refs: Block 21 (SSO/SCIM/Domain capture) · Block 18 (managed-settings.json fields).

### 25.1 — Role Hierarchy ⭐ (exam trap — "Admin ≠ admin")

| Role | Count | Can do | Cannot do |
|---|---|---|---|
| **Primary Owner** | Exactly 1 | Provision + purchase seats · Data exports · Transfer ownership · Everything Owner can do | — |
| **Owner** | Unlimited | Configure SSO + SCIM · Audit logs · Data retention · Usage analytics · Invite/remove Admins + Owners | — |
| **Admin** | Unlimited | Invite + remove members · Usage analytics (Enterprise only, not Team) | **Configure SSO or SCIM** · **Provision seats** · Audit logs |
| **User** | Everyone | Chat · Projects · Claude Code (if right seat type) | No admin settings visible |

**The trap:** IT contacts get Admin "by default" — but Admin can't configure SSO or provision seats. **Catch in discovery, not on kickoff morning.**

**Memory rule:** Pre-kickoff config task → Owner minimum. Seat provisioning → Primary Owner only.

### 25.2 — Seat Types ⭐ (exam trap — "Standard blocks Claude Code entirely")

| Billing model | Seat type | Claude Code? | Notes |
|---|---|---|---|
| Seat-based (Legacy) | **Standard** | ❌ | Chat only. Auth errors on `claude` = check seat type first |
| Seat-based (Legacy) | **Premium** | ✅ | Primary Owner assigns. Converts at next renewal |
| Usage-based (Transitional) | **Chat** | ❌ | Being phased out |
| Usage-based (Transitional) | **Chat + Code** | ✅ | Being phased out |
| Usage-based (Current) | **Claude Enterprise** | ✅ | All-inclusive. **Default spend limit = $0** |

**The trap:** Current Enterprise plan is all-inclusive but org spend limit defaults to **$0** — set it before the first API call or every call fails.

### 25.3 — Pre-kickoff Checklist (Day -14 to Day 0)

```
1. Configure identity  (Owner or Primary Owner)
   ├── SAML 2.0 or OIDC SSO → pilot test before broad rollout
   ├── Domain capture → auto-routes all users from org domain
   └── SCIM (>20 devs) → auto-provision + de-provision from IdP
       (JIT = simpler, less control)

2. Assign seats + set spend limit  (Primary Owner for seats)
   ├── Settings > Organization > Members
   └── Set org-level spend limit first (default $0 = all API calls fail)

3. Deploy managed-settings.json  (BEFORE developers install — non-retroactive)
   └── Sits above user + project settings, cannot be overridden
   └── Lock permissions · enforce auth · pin version floor · MCP allowlists

4. Verify developer authentication
   ├── Developer runs `claude` → selects "Claude account with subscription" → Enterprise SSO
   ├── Run `/status` inside Claude Code to confirm seat + auth provider
   └── If previously used personal account: `/logout` first
```

### 25.4 — Failure Pattern Diagnosis ⭐⭐

| Symptom | Root cause | Fix |
|---|---|---|
| **One** developer can't use Claude Code | Wrong seat type (Standard on legacy) | Upgrade seat |
| **Everyone** fails simultaneously | Org spend limit = $0 | Set spend limit first |
| IT can't configure SSO | Role is Admin, not Owner | Elevate to Owner |
| IT can't provision seats | Role is Owner, not Primary Owner | Primary Owner must do it |
| Developers bypass MCP policy | Policy in docs only, not enforced | Add to `managed-settings.json` |
| Developers on personal accounts | No `/logout` before Enterprise auth | `/logout` then re-auth via SSO |

**Key signal:** One failure = individual (seat/auth). **Everyone fails simultaneously = org-level ($0 spend limit).**

### 25.5 — Your scenario debrief (7/8)

| # | Your call | Score | Lesson |
|---|---|---|---|
| 1 — First call | Confirm her role | ✅ +2 | Role is gating — can't build plan without it |
| 2 — Admin revealed | Both blocked, elevate now | ✅ +2 | Admin can't do SSO or seats; both blocked |
| 3 — Everyone fails Day 1 | SSO issue | ⚠️ +1 | **Wrong signal.** Everyone = org-level = $0 spend limit |
| 4 — MCP policy | managed-settings.json allowlist | ✅ +2 | Only enforceable layer; docs can't override dev behavior |

---

## Block 26 — Course 7 L2: Analytics, Measurement & Day 30 Readout

**One-liner:** Admin Console answers "Is it working?" OTel answers "Is it working for the business?" Day 30 readout = four metrics, Green/Amber/Red, headline first.

Cross-refs: Block 25 (managed-settings.json deploy) · Block 18 (managed-settings.json fields).

### 26.1 — Two-Tool Measurement Stack ⭐

| Tool | Setup required | What it gives you | Best for |
|---|---|---|---|
| **Admin Console** | None — available to Owners immediately | DAU · Sessions · Seat utilization · Org spend · Cohort retention | Day 7/14/30 readouts · Champion briefs · Quick adoption checks |
| **OTel Pipeline** | `CLAUDE_CODE_ENABLE_TELEMETRY=1` in dev env · Route to Prometheus/Grafana/OTLP backend | session.count · active_time · lines_of_code · commit.count · pull_request.count · cost.usage · token.usage per dev | Engineering metrics · ROI models · Per-developer cost tracking · Large deployments |
| **Analytics Chat** | None — within Admin Console | Conversational queries ("which teams had highest session counts last week?") on same underlying data | Ad hoc questions without exporting CSVs |

**Working rule:** Admin Console = "Is it working?" OTel = "Is it working for the business?"

**Critical data source distinction ⭐:** Anthropic Analytics API = aggregate usage for general Claude (claude.ai). For **Claude Code deployments**, session and cost metrics come via **OTel or Admin Console — not the Analytics API**.

### 26.2 — Four Scorecard Metrics ⭐⭐

| Metric | Target | Amber signal | Red signal | Source |
|---|---|---|---|---|
| **DAU** | 60% by Week 3 | Plateau below 50% in Week 2 | Below 40% at Week 4 = change management problem, not product | Admin Console > Analytics > Active users |
| **Sessions/User** | 2–3/day | Below 1.5/day | Not integrated into workflow — pair with active_time.total | Admin Console or OTel active_time.total |
| **Week 2 Retention** | 80%+ | — | Below 80% past Week 2 predicts churn at expansion | Admin Console cohort view |
| **Cost/Developer** | Track weekly | — | Spike without matching sessions = runaway usage or misconfigured spend limit | Admin Console > Billing or OTel cost.usage |

**Super-user pattern:** 10–15 developers drive disproportionate cost and output. Cost spike without adoption increase → **check per-developer breakdown first, not aggregate.** Lever = model matching (lighter model for workflows that don't need frontier capability).

### 26.3 — OTel Deployment Paths

| Path | When to use | Config |
|---|---|---|
| **Console exporter** | Debug only — single developer | Default; no config needed |
| **Prometheus** | Standard team deployment | Set exporter endpoint in dev environment |
| **Enterprise OTLP via managed-settings.json** | 50+ developers · Org-wide consistency required | Add `telemetry.enabled` + `otlpEndpoint` to managed-settings.json — applies to every machine, can't be overridden by developers |

```json
// managed-settings.json OTel config
{
  "telemetry": {
    "enabled": true,
    "otlpEndpoint": "https://otel.your-backend.com"
  }
}
```

Deploy managed-settings.json **before** developers install Claude Code — telemetry config is non-retroactive.

### 26.4 — Day 30 Readout Structure

```
1. Lock baselines  (Day -14 to Day 0)
   └── Tickets closed/sprint · PRs/developer · self-reported time on repetitive tasks
   └── If missed: note in readout + recommend capturing at next rollout

2. Pull Week 4 data  (Admin Console)
   └── Settings > Analytics → DAU, sessions/user, Week 2 cohort retention
   └── Cross-reference OTel cost.usage if pipeline was deployed

3. Structure scorecard
   └── Rate each metric: Green (at/above target) · Amber (within 15%) · Red (below threshold)
   └── One sentence per metric explaining the number — never raw numbers without context

4. Brief the champion
   └── Lead with headline: overall Green/Amber/Red
   └── Follow with the metric most directly supporting expansion decision
   └── Hold detail for questions
   └── If Red: come with remediation plan, not just a number
```

### 26.5 — Your scenario debrief (6/8)

| # | Your call | Score | Lesson |
|---|---|---|---|
| 1 — Pull adoption data | Admin Console > Analytics | ✅ +2 | Fastest path, no setup, 48 hrs to readout |
| 2 — Read the numbers | Amber on DAU+sessions, Green on retention+cost, push plan | ✅ +2 | Honest scorecard names gaps and comes with a plan |
| 3 — Missing baselines | Delay readout for retrospective baseline | ❌ +0 | **Window closed Day 1.** Retrospective baseline = impractical. Use what you have, flag for next rollout |
| 4 — ROI question | Anchor to cost/session vs dev day rate | ✅ +2 | Give CFO the inputs ($2/session vs $400-800/day); they do the math themselves |

**Memory anchor for Decision 3:** Baseline window = Day -14 to Day 0. Once deployment starts, it's gone. Never delay readout to manufacture data that doesn't exist.

**ROI frame shortcut:** `$3.10/day ÷ 1.6 sessions = ~$2/session` vs developer day rate $400–800 fully loaded. Frame as ratio, let CFO close.

---

## Block 27 — Course 7 L3: Compliance API & Observability Stack

**One-liner:** Compliance API is the only surface that captures conversation content. Every other mechanism captures metadata only.

Cross-refs: Block 21 (SSO/SCIM identity) · Block 22 (data controls / ZDR / retention) · Block 25 (Primary Owner role) · Block 26 (OTel + Analytics).

### 27.1 — The Five-Mechanism Observability Stack ⭐⭐

| Mechanism | What it captures | Content? | Retention | Access | Real-time? |
|---|---|---|---|---|---|
| **Compliance API** | Conversation content · file uploads · activity feed events | ✅ **Yes — only one** | 1 day to indefinite (Enterprise default: indefinite) · Legal hold up to 6 years | **Primary Owner only** | Pull (polling) |
| **Audit Logs** | Sign-ins · project/file events · member changes · admin setting changes | ❌ Metadata only | 180-day rolling window | Owners + Primary Owners | CSV export from Org Settings |
| **Admin API** | User provisioning · workspace mgmt · API keys · spend limits | ❌ Metadata only | — | Primary Owners + Owners | Programmatic |
| **OTel** | Tool calls · bash commands · MCP invocations · API requests | ❌ Metadata only | Opt-in stream | Opt-in via MDM or env var | ✅ Real-time OTLP stream |
| **Analytics** | Aggregated adoption · seat utilization · feature usage · spend | ❌ Metadata only | — | Owners + Primary Owners via dashboard + API | Daily snapshots |

**Master framing rule:** "What was *discussed*?" → Compliance API. "What was *executed*?" → OTel. "Admin events?" → Audit Logs. "Adoption signals?" → Analytics. **Never conflate Analytics API with Compliance API in a security review.**

### 27.2 — Compliance API Details ⭐

| Property | Value |
|---|---|
| **What it captures** | Chat inputs · outputs · file uploads · activity feed events |
| **Who can enable** | **Primary Owner only** (Owners cannot see the option) |
| **Retention** | Enterprise default = indefinite · Configurable 1 day → indefinite · Legal hold = specific user/conversation preserved past standard window |
| **Max retention** | Up to 6 years |
| **Where to enable** | Organization Settings › API › Enable under Compliance API |
| **Access keys** | Create one key per integration · Shown once, store securely · Rotate = new key, other integrations unaffected |
| **Plan availability** | SIEM = Enterprise + Platform · DLP/eDiscovery/AI posture = Enterprise only |
| **Vendor integrations** | 28+ across all four categories |

### 27.3 — Four Compliance API Use Cases

| Use case | Endpoint | Integration examples | Plan |
|---|---|---|---|
| **SIEM** | `GET /v1/organizations/{id}/audit-events` | Splunk · Microsoft Sentinel · OTLP backend | Enterprise + Platform |
| **DLP / CASB** | `GET /v1/organizations/{id}/conversations` | Nightfall · Microsoft Purview · Symantec | Enterprise only |
| **eDiscovery** | `GET .../conversations/{conversation_id}` | Relativity · Exterro | Enterprise only |
| **AI Security Posture** | Same endpoints | Behavioral risk flagging tools | Enterprise only |

**Shared interface model:** Customer security team and their security vendors access the same Compliance API endpoints, surfaced within tools the client already operates.

### 27.4 — Routing Compliance Requests (quick decision table) ⭐

| Client request | Right surface | Why |
|---|---|---|
| Employee conversation content for HR/legal | **Compliance API** | Only surface with conversation content |
| Real-time alert on bash commands from Claude Code | **OTel** (`OTEL_LOG_TOOL_DETAILS=1` → SIEM) | Real-time stream; Compliance API is pull-only |
| Legal hold for specific user pending investigation | **Compliance API legal hold** | Pins specific user/conversation regardless of org retention policy |
| Scan conversations for PII (DLP) | **Compliance API** (DLP/CASB integration) | OTel has identity metadata but NOT conversation content |
| Admin change history (who changed what setting) | **Audit Logs** | Admin events, 180-day window |
| Day 30 adoption readout | **Admin Console / Analytics** | Aggregated DAU, sessions, seat utilization |
| Per-developer cost tracking | **OTel** (`cost.usage`) | Admin Console shows org-level only |

### 27.5 — Enablement Path (5 steps)

```
1. Identify requirement  (SIEM / DLP / eDiscovery / AI posture)
   └── Each drives different endpoint + integration

2. Confirm Primary Owner on the call
   └── Owners cannot see the enablement option — wrong person = wasted call

3. Enable in Organization Settings
   └── Org Settings › API › Enable (Compliance API) — under 1 minute, no engineering needed

4. Create compliance access key
   └── + Create key · One key per integration · Shown once · Rotate = new key

5. Wire to integration
   └── DLP tool / SIEM / eDiscovery platform
   └── Platform docs: platform.claude.com/docs/en/manage-claude/compliance-api
```

### 27.6 — Your scenario debrief (6/8)

| # | Your call | Score | Lesson |
|---|---|---|---|
| 1 — HR investigation | Compliance API by user ID | ✅ +2 | Only surface with conversation content |
| 2 — Real-time bash alerting | OTel + OTEL_LOG_TOOL_DETAILS=1 → SIEM | ✅ +2 | OTel = real-time execution stream; Compliance API = pull only |
| 3 — Legal hold | Set org-wide retention to 3 years | ⚠️ +1 | **Wrong tool.** Org-wide retention ≠ legal hold. Legal hold = Compliance API targeted pin for specific user/conversation, regardless of org policy |
| 4 — DLP / PII monitoring | OTel → SIEM scan for PII patterns | ⚠️ +1 | **OTel has metadata, not content.** Can flag unusual session patterns but cannot scan conversation text for PII. Content-level DLP = Compliance API |

**Memory anchor for decisions 3+4:** Legal hold ≠ retention setting. PII in conversations = Compliance API (not OTel). OTel knows *what* ran; Compliance API knows *what was said*.

---

## Block 28 — Course 2: Installation & Environments (L1–L5)

**One-liner:** Confirm environment before kickoff (not during). Platform → Install → Auth → Verify. For CI: `-p` flag makes it headless. For security: container/VM is the only isolation that covers everything.

### 28.1 — Platform Support & Install Commands ⭐

| Platform | Path | Install command |
|---|---|---|
| **macOS** | Native | `curl -fsSL https://claude.ai/install.sh \| bash` |
| **Linux** | Native (Ubuntu 20.04+, Debian 10+, Alpine 3.19+) | Same curl command |
| **Windows — Native** | No WSL needed · PowerShell or CMD · Git for Windows optional (else uses PowerShell) | `irm https://claude.ai/install.ps1 \| iex` (PowerShell) |
| **Windows — WSL** | Linux toolchains + sandboxing · WSL 2 recommended · **Requires IT enablement on managed machines** | Install inside WSL, behaves like Linux |

**Native vs WSL trap:** Native Windows = no IT ticket needed. WSL = IT must enable it on managed images.

### 28.2 — Auth Paths + Four Pre-Kickoff Blockers ⭐

**Two auth paths after install:**

| Path | When | IT involvement |
|---|---|---|
| Browser-based login | Interactive developers on Team/Enterprise | None — individual-level |
| API key (`ANTHROPIC_API_KEY`) | Headless · CI · automated workflows · when set, overrides subscription login | IT must create key, distribute (env var / secrets vault), rotate periodically |

**Four blockers to confirm with IT before install day:**

1. **Network access** — confirm reachable: `api.anthropic.com` · `claude.ai` · `platform.claude.com` · `downloads.claude.ai` · `raw.githubusercontent.com` · Firewall rules take days to change — first item to raise
2. **Proxy + certificates** — `HTTPS_PROXY` / `HTTP_PROXY` + `NODE_EXTRA_CA_CERTS` for custom CA (e.g. Zscaler TLS inspection)
3. **Auth architecture** — browser vs API key vs mixed cohort — shapes entire provisioning workflow
4. **Windows native vs WSL** — WSL on managed machines may need IT ticket

**Verification commands:**
```bash
claude --version   # "command not found" = PATH not updated → close/reopen terminal
claude doctor      # validates config, lists invalid settings with source file + field name
/status            # inside session — confirms proxy/gateway config applied correctly
```

**Troubleshoot quick-ref:**
- `curl: (7) Failed to connect to claude.ai port 443` → corporate firewall blocking outbound HTTPS
- `command not found: claude` after install → PATH not updated (close terminal, reopen)

### 28.3 — IDE Integrations ⭐

| IDE | Setup | Key detail |
|---|---|---|
| **VS Code** | Extension: `anthropic.claude-code` from Marketplace | `vscode:extension/anthropic.claude-code` |
| **Cursor** | Same extension | `cursor:extension/anthropic.claude-code` — fully supported, same experience |
| **VS Code forks** (Kiro, Devin Desktop, etc.) | Open VSX registry or Extensions view | All supported |
| **JetBrains** (IntelliJ, PyCharm, etc.) | **Two installs required:** CLI (from L1 installer) + plugin from JetBrains Marketplace | Plugin provides IDE integration; CLI provides engine. **Both required.** |

**Three Day-1 capabilities to demonstrate:**
1. **Diff viewing** — changes in native IDE diff viewer, not terminal output
2. **Selection context** — highlight a function → Claude already knows what you're working on
3. **File reference shortcuts** — `@app.ts#5-10` pulls specific file + line range
   - VS Code: `Option+K` / `Alt+K`
   - JetBrains: `Cmd+Option+K` / `Alt+Ctrl+K`

**`/config` settings (interactive menu in session):**
- `autoConnectIde` · `autoInstallIdeExtension` · `externalEditorContext` · `editorMode` (normal or vim)

**Exam trap:** Cursor question answer = B. "Cursor is supported — same extension, same experience." Don't hedge or send to IT.

### 28.4 — Terminal Patterns + Environment Variables ⭐⭐

**Four shortcut categories (teach in this order):**

| Category | Commands | When to teach |
|---|---|---|
| **Bash mode** | `! <command>` — runs shell cmd, output in Claude's context | **Day 1 first** — changes how devs think about the tool |
| **Context mgmt** | `/clear` (reset conversation, NOT files) · `/compact` · `/context` | Week 2 — after devs hit context limit |
| **Navigation** | `Esc` (cancel) · `Esc Esc` (rewind menu: Fork / Rewind code / Fork+Rewind) · `Shift+Tab` (cycles default → auto-accept edits → plan) | When relevant |
| **File + session** | `@file.ts#5-10` · `--continue`/`-c` (resume last session) · `--resume <id>` · `/model` | When relevant |

**True/False traps:**
- `! prefix` runs shell + output in Claude's context → **TRUE**
- `/clear` undoes file changes → **FALSE** (resets conversation only, not files)
- `Shift+Tab` cycles to plan mode → **TRUE**
- Shell piping works same as Unix → **TRUE**

**Key environment variables:**

| Variable | Category | What it does |
|---|---|---|
| `ANTHROPIC_API_KEY` | Auth | API key; overrides subscription login when set |
| `ANTHROPIC_AUTH_TOKEN` | Auth | Custom bearer token; takes precedence over API_KEY |
| `ANTHROPIC_BASE_URL` | Deployment | Redirect to LLM gateway |
| `CLAUDE_CODE_USE_BEDROCK` | Deployment | Route through Amazon Bedrock (set to `1`) |
| `CLAUDE_CODE_USE_VERTEX` | Deployment | Route through Google Vertex AI |
| `HTTPS_PROXY` / `HTTP_PROXY` | Network | Corporate proxy URL |
| `NO_PROXY` | Network | Bypass proxy hosts (`*` = all) |
| `NODE_EXTRA_CA_CERTS` | Network | Path to custom CA cert file |
| `CLAUDE_CODE_CERT_STORE` | Network | `bundled,system` (default) · `bundled` · `system` |
| `CLAUDE_CODE_CLIENT_CERT` | Network | mTLS client cert path |
| `DISABLE_TELEMETRY` | Governance | Disable telemetry |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` | Governance | Suppress non-essential outbound (air-gapped envs) |
| `DISABLE_AUTOUPDATER` | Governance | Prevent auto-update (central version management) |
| `CLAUDE_CODE_MAX_TURNS` | Behavior | Max agentic turns before stop + confirm (cost control) |

**Pre-session env vars needed (proxy + cert + version policy client):** `ANTHROPIC_API_KEY` · `HTTPS_PROXY` · `NODE_EXTRA_CA_CERTS` · `DISABLE_AUTOUPDATER` — four of six in the activity.

### 28.5 — Dev Containers + Sandbox Isolation ⭐⭐

**Isolation layer comparison (what each restricts):**

| Access Surface | Built-in Bash Sandbox | Sandbox Runtime | Container / VM |
|---|---|---|---|
| Bash commands | ✅ Restricted | ✅ Restricted | ✅ Restricted |
| File tools (Read/Write) | ❌ Full access | ✅ Restricted | ✅ Restricted |
| MCP servers | ❌ Full access | ❌ Full access | ✅ Restricted |
| Hooks | ❌ Full access | ❌ Full access | ✅ Restricted |
| Web access | ❌ Full access | ✅ Restricted | ✅ Restricted |

**Critical trap:** Built-in Bash sandbox only restricts bash subprocesses. **File tools, MCP, hooks, web = unrestricted** unless you add `permissions.deny` rules or use container/VM.

**Four sandbox properties:** Directory scoping · Network allowlisting · Approval-free within bounds · Out-of-sandbox notification (surfaces attempt rather than silently failing)

**Minimal settings.json sandbox config:**
```json
{
  "sandbox": {
    "enabled": true,
    "filesystem": {
      "denyRead": ["/"],
      "allowRead": ["/project", "~/.claude"],
      "allowWrite": ["/project"]
    },
    "network": { "allowedDomains": ["api.anthropic.com", "*.client-internal.com"] }
  },
  "permissions": {
    "allow": ["Bash(npm run test *)", "Bash(npm run lint)", "Read(/project/**)"],
    "deny": ["Bash(curl *)", "Read(./.env)", "Read(~/.ssh/**)"],
    "defaultMode": "acceptEdits"
  }
}
```

`defaultMode` options: `default` · `acceptEdits` · `plan` · `auto`

**Dev container feature:**
```json
{
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": { "ghcr.io/anthropics/devcontainer-features/claude-code:1.0": {} }
}
```
Feature version pins install script, not Claude Code release. Use `DISABLE_AUTOUPDATER` for pinned version policies.

**Security questionnaire answer:** "We configure explicit deny rules for sensitive paths like `~/.ssh/**`, enable the Bash sandbox for shell commands, and **verify these rules before deployment**. Access is governed by **active configuration**, not default behaviour." ("By default no" = wrong frame for security teams.)

### 28.6 — Headless Mode + CI Flags ⭐⭐

**Five key headless flags:**

| Flag | Purpose | When to use |
|---|---|---|
| `-p "prompt"` | **Non-interactive mode** — required for any pipeline use | All CI/automation |
| `--allowedTools "Bash,Read,Edit"` | Restrict which tools available in this execution | Limit scope per pipeline stage |
| `--append-system-prompt "..."` | Inject pipeline-level instructions ("output as JSON", "focus on security") | Specialise per stage |
| `--output-format json` | JSON output (schema defined in prompt) — add validation + retry for production | Dashboard/ticket/DB consumers |
| `--bare` | Disable local hooks · skills · plugins · MCP · auto memory · CLAUDE.md | Reproducible CI — same result on any machine |

**Three pipeline patterns:**
```bash
# Code review (PR → JSON security report)
gh pr diff "$1" | claude -p --append-system-prompt "Review for security vulnerabilities" --output-format json

# Test-and-fix loop
claude -p "Run test suite, fix any failures" --allowedTools "Bash,Read,Edit"

# Structured extraction
claude -p 'List all API endpoints. Output JSON array with "path" and "method" per item.' --output-format json
```

**GitHub Actions integration:**
- Run `/install-github-app` from an active session → installs to org → @claude trigger on any PR/issue comment
- Custom workflows: trigger (PR/schedule) → `ANTHROPIC_API_KEY` from GitHub Secrets → `claude -p` with flags → output handling (post to PR / save to file)

**Scenario answer:** PR review → JSON report = **C: `-p` + `--output-format json` + schema in prompt**
- `-p` = non-interactive; `--output-format json` = structured output; schema defined in prompt text
- `--output-format json` alone without schema in prompt = undefined shape, dashboard can't parse

---

## Block 29 — Course 1: Product Foundations (L1–L3)

**One-liner:** Claude Code = agentic loop (Observe→Plan→Act→Verify), same model across all surfaces. Model choice: Sonnet default, Opus for long-horizon autonomous work. Platform: cloud-native only when data residency forces it; otherwise Enterprise.

### 29.1 — What Claude Code Is ⭐ (L1)

**Chat vs Claude Code:**

| | Chat interface | Claude Code |
|---|---|---|
| Access | Stateless, no file/terminal access | Reads + writes files, runs bash, edits codebase |
| Loop | Single exchange | Loops until task done or paused |
| Auditability | Generated text | Every tool call logged + visible in terminal |

**Agentic loop:**
```
Observe (read files, terminal, grep) →
Plan (which files, which commands, what order) →
Act (edit files, run bash, call tools — all real, on-machine) →
Verify (surface result, wait approval / loop back to Observe on failure)
```

**Four surfaces — same model, same loop, different access:**

| Surface | Access type | Key detail |
|---|---|---|
| **CLI** | Native OS-level | Full filesystem + terminal. Reference point for all config decisions |
| **IDE Extensions** | Native (same as CLI) | VS Code + JetBrains — editor is a wrapper, not a lighter version |
| **Agent SDK** | Host environment | CI/CD runners, multi-agent pipelines — scope = wherever it runs |
| **Desktop / Web / Mobile** | Scoped | **Reaches filesystem/terminal only when explicitly invoked** — not directly from host OS |

**True/false traps:**
- Claude Code uses a different model tier than Claude.ai → **FALSE** (same model)
- Can run bash commands + edit files → **TRUE**
- IDE extension gives different capabilities than CLI → **FALSE** (same capabilities, editor is a wrapper)

### 29.2 — Model Selection ⭐⭐ (L2)

| Model | Cost | Context | Speed | Depth | Use for |
|---|---|---|---|---|---|
| **Haiku 4.5** | Lowest | 200k | Fastest | Lowest | Sub-agent pipelines · CI scripting · rapid prototyping · cost-sensitive |
| **Sonnet 4.6** | Mid | 1M | Balanced | Balanced | **Production default** — most Claude Code work |
| **Opus 4.8** | Highest | 1M | Slowest | Deepest | Long-horizon autonomous tasks · complex refactors · "get it right first time" |

**Effort lever (try before switching models):**
- Adjust reasoning depth within a tier — cheaper than upgrading
- Opus 4.8: `xhigh` = recommended for coding and agentic work (deepest reasoning this tier offers)
- Sonnet 4.6: goes up to `high`
- Simple tasks (20-line utility tests) = same result at default as at extended thinking
- Complex tasks (multi-file refactor, cross-module deps) = effort produces materially better output

**Scenario answer:** 50 devs routine work + small group overnight autonomous refactoring → **C: Sonnet 4.6 default · Opus 4.8 for overnight runs**
- Haiku for all = degrades quality on complex tasks
- Opus for all = +65% cost on routine work for no gain
- Tiered: cost-efficient daily + reasoning-depth for the runs that need it

### 29.3 — Platform Options: 7 Paths, 3 Categories ⭐⭐ (L3)

**Three categories:**

| Category | Products | Choose when | What you lose |
|---|---|---|---|
| **Claude-managed** | Teams · Enterprise | Fastest path, no hard cloud requirement | — |
| **Cloud-native** | Bedrock (AWS) · Vertex (GCP) · Azure Foundry | Existing cloud commitment or data residency requirement | Claude.ai web · managed settings · Compliance API |
| **API / Console** | Anthropic API · Console | Single developer · prototype only. Never for governed rollout | All enterprise controls |

**Decision framework (3 questions in order):**
1. Must processing stay in a cloud region they control? → Yes → which cloud provider?
2. Does security need SSO, audit logs, managed settings, Compliance API? → Yes → Enterprise tier
3. Rollout scope? → Team/org vs single dev/prototype

**Enterprise vs Teams:**

| Feature | Teams | Enterprise |
|---|---|---|
| Basic SSO + admin tools | ✅ | ✅ |
| Domain capture + SCIM | ❌ | ✅ |
| RBAC + managed settings | ❌ | ✅ |
| Compliance API | ❌ | ✅ |
| Audit logs | ❌ | ✅ |

**Seat types (usage-based current model):**

| Seat | Claude Code? | Common trap |
|---|---|---|
| **Standard** | ❌ No | Most common default seat — "we have Claude" ≠ can run Claude Code |
| **Chat + Code** | ✅ Minimum | Gap between what was demoed and what was purchased |
| **Claude Enterprise** | ✅ Full | If security asks for audit logs/managed settings → they need this tier |

Legacy plans: Standard (no CC) / Premium (CC included). Confirm which billing model the client is on before procurement.

**Cloud-native trade-off:** Satisfies existing cloud commitment — **not** a security requirement. Governance gap vs Enterprise is real — always flag it. Add LLM Gateway (middleware for auth/logging/filtering/rate limiting) on top of Bedrock/Vertex/Foundry.

**Scenario answer:** Financial services + AWS-committed + regional data processing requirement → **B: Bedrock + LLM Gateway**
- Enterprise = SaaS, Anthropic's infrastructure, client has no regional control
- Bedrock = processes in client-controlled AWS region + existing billing

---

## Block 30 — Course 3: Configuration & Customization (L1–L5)

**One-liner:** Four config scopes (Managed > CLI flags > Local > Project > User), permissions merge not override, CLAUDE.md is context not enforcement, settings.json is team-shared, slash commands are reusable MD files, output styles change how Claude communicates.

Cross-refs: Block 9 (CC config scopes) · Block 18 (managed-settings.json) · Block 20 (sandbox/permissions) · Block 14 (Skills authoring).

### 30.1 — Configuration Scope Hierarchy ⭐⭐ (L1)

**Priority order (top wins, Claude walks top→bottom):**

| Priority | Scope | Location | Who controls | Override-able? |
|---|---|---|---|---|
| 1 | **Managed** | macOS: `/Library/Application Support/ClaudeCode/` · Linux: `/etc/claude-code/` | IT via MDM/Group Policy | ❌ Never — survives reinstall |
| 2 | **CLI flags** | Session-level (`--allowedTools`, `--model`) | Developer at launch | Session only, not persisted |
| 3 | **Local** | `.claude/settings.local.json` | Individual developer | Git-ignored automatically |
| 4 | **Project** | `.claude/settings.json` | Team (committed to git) | By Local or above |
| 5 | **User** | `~/.claude/settings.json` | Individual (personal defaults) | Lowest priority |

**Permission merge exception ⭐:** Allow/deny rule lists **merge** across scopes, not override. Developer's local allow adds to project's list. A deny set at project/managed scope **cannot be removed** by local config.

**Ownership heuristic:** Who controls it? Who should it affect? Can they override it? → The right scope picks itself.

**Scenario:** Block curl across every machine, survives reinstall → **Managed scope** (IT pushes via MDM). Project scope only applies to one repo; user scope can be overridden; local scope is personal.

### 30.2 — CLAUDE.md Hierarchy ⭐ (L2)

**Five scopes — concatenate, not override (broadest → most specific):**

| Scope | Location | Loaded when |
|---|---|---|
| Managed Policy | macOS: `/Library/Application Support/ClaudeCode/CLAUDE.md` | Always — cannot be excluded |
| User | `~/.claude/CLAUDE.md` | Every session |
| Project | `./CLAUDE.md` or `./.claude/CLAUDE.md` | Every session |
| Local | `./CLAUDE.local.md` (add to .gitignore) | Every session, not committed |
| Subdirectory | `./subdir/CLAUDE.md` | On demand when Claude reads files in that directory |

**Key behaviours:**
- `/init`: auto-bootstraps CLAUDE.md by analysing the codebase — refine from there
- `claudeMdExcludes`: skip other teams' CLAUDE.md noise — works from any scope **except managed**
- `@path/to/file` imports: linked file loads at session start alongside the CLAUDE.md that references it

**Writing rules:**
- Specific + verifiable ("Use 2-space indentation. Run `npm test` before committing") not vague ("Format code properly")
- Under 200 lines — longer files reduce adherence
- Pruning rule: if Claude does it right without the instruction, **delete it**

**True/false traps:**
- CLAUDE.md instructions are enforced (Claude must follow) → **FALSE** — context/memory, not constraint. Use hooks or managed settings for enforcement
- Project CLAUDE.md = right place for sandbox URLs/test data → **FALSE** — use CLAUDE.local.md (gitignored)
- `/init` overwrites existing CLAUDE.md → **FALSE** — analyses and drafts, doesn't overwrite
- Developers can exclude managed CLAUDE.md with claudeMdExcludes → **FALSE** — managed policy cannot be excluded

### 30.3 — settings.json vs settings.local.json ⭐ (L3)

| File | Committed? | Use for | Never put here |
|---|---|---|---|
| `.claude/settings.json` | ✅ Git-committed | Permissions allow/deny · hooks · MCP servers · company announcements | Model preferences · credentials · defaultMode overrides |
| `.claude/settings.local.json` | ❌ Git-ignored | Personal mode prefs · experimental config · machine-specific tool paths · claudeMdExcludes | Anything the team needs |

**Permission evaluation order — Deny → Ask → Allow ⭐**
1. **Deny** — if any deny rule matches → blocked (no override possible)
2. **Ask** — if ask rule matches → Claude prompts for confirmation
3. **Allow** — if allow rule matches → proceeds without prompt
4. **Default** → ask (unknown tool use requires human approval)

"Block first, challenge second, permit last." An explicit prohibition wins before Claude considers prompting or automatically allowing. A `deny` rule must never be bypassed via an `ask` route.

**`$schema` line:** Add `"$schema": "https://json.schemastore.org/claude-code-settings.json"` to every project settings.json → enables autocomplete + inline validation in VS Code/Cursor.

**Scenario:** Team allow/deny + personal experiments → **B: team rules in .claude/settings.json, personal experiments in .claude/settings.local.json**. Cross-machine block survives reinstall → **B: managed policy via IT** (project scope only covers one repo).

### 30.4 — Custom Slash Commands ⭐ (L4)

**Location and naming:**

| Location | Scope | Auto-discovered? |
|---|---|---|
| `.claude/commands/` | Project — committed to git, team-shared | ✅ No restart needed |
| `~/.claude/commands/` | User — available in all projects on this machine | ✅ No restart needed |

- Filename = command name: `review-pr.md` → `/review-pr`
- Namespaced: `security/audit.md` → `/security:audit`
- `$ARGUMENTS` placeholder substituted with text after the command invocation

**Command structure:**
```markdown
---
description: Review a pull request against the security checklist
allowed-tools: Read, Bash(git *)
---

## PR Review: $ARGUMENTS

[Prompt body — specific enough to run without thinking, short enough to read in 30s]
```

**Design principle:** Write for the person who'll use it on the worst day of a sprint. Specific + scoped allowed-tools. Option B beats Option A (specific with $ARGUMENTS + tools + audience > short and flexible).

**Scenario:** git log before every standup (whole team, daily) → **B: .claude/commands/ in repo, committed to git** (everyone gets it automatically; user scope = only on your machine; leaving it as manual prompt = misses the point of commands).

### 30.5 — Output Styles ⭐ (L5)

**CLAUDE.md vs Output Styles:**
- CLAUDE.md = what Claude **knows** (project memory, conventions, build commands)
- Output styles = how Claude **communicates** (tone, format, proactivity, explanation depth)
- **Session start constraint:** output style set at session start only. Changing mid-session has no effect. Apply changes after `/clear` or in a new session.

**Four built-in styles:**

| Style | Behaviour | Best for |
|---|---|---|
| **Default** | Efficient, precise, no added commentary | Production teams past initial adoption |
| **Explanatory** | Adds "Insights" sections explaining each decision | **Adoption phase** — engineers asking "why" |
| **Proactive** | Executes immediately, makes assumptions, still shows prompts for consequential actions | Speed-focused workflows |
| **Learning** | Reasoning + `TODO(human)` markers at decision points — developer completes critical pieces | Teams that want to stay in the loop on key decisions |

Set via `/config` in session (saves to settings.local.json) or `"outputStyle": "Explanatory"` directly in any settings file.

**Custom output styles:** `.claude/output-styles/` at project/user/managed level

| Option | Behaviour | Use for |
|---|---|---|
| `keep-coding-instructions: true` | Adds communication format ON TOP of built-in engineering instructions | Engagement docs · security review findings · onboarding mode |
| `keep-coding-instructions: false` (default) | Replaces built-in engineering persona entirely | Non-engineering use (writing assistant, data analyst, requirements formatter) |

**Day 1 scenario (engineers keep asking why Claude made architecture choices):** → **A: Explanatory** (engineers asking why = adoption phase, they need explanations. Learning adds TODO markers which isn't the issue here. Default would leave the questions unanswered.)

---

## Block 31 — Course 7 L4: OTel Pipeline Setup ⭐⭐

**One-liner:** OTel = what was executed. Enable with one master switch, configure exporters, deploy via managed-settings.json. Prompt content is NOT captured by default — three separate opt-in flags control progressively more detail.

Cross-refs: Block 26 (OTel overview + scorecard metrics) · Block 27 (5-mechanism observability stack) · Block 25 (managed-settings.json deployment).

### 31.1 — What OTel Captures vs Other Surfaces

| Surface | Captures | Real-time? |
|---|---|---|
| **OTel** | Every tool call · bash command · MCP invocation · API request | ✅ Streaming |
| **Compliance API** | Conversation content (what was said) | Pull only |
| **Audit logs** | Admin events (sign-ins, setting changes) | 180-day CSV |

### 31.2 — Signal Types + Opt-in Flags ⭐⭐

| Signal | What's included | Required to enable |
|---|---|---|
| **Metrics (8)** | sessions · tokens · cost.usage (USD) · lines of code · commits · pull requests · code edit decisions · active time | `CLAUDE_CODE_ENABLE_TELEMETRY=1` only — streams by default |
| **Events** | Tool calls · API requests · permission mode changes · MCP connections · auth events | + `OTEL_LOGS_EXPORTER=otlp` |
| **Bash command content** | The actual command text | + `OTEL_LOG_TOOL_DETAILS=1` |
| **Full tool output** | Raw file contents · command output (truncated at 60KB) | + `OTEL_LOG_TOOL_CONTENT=1` + `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1` |
| **Prompt/conversation content** | Developer's input text | + `OTEL_LOG_USER_PROMPTS=1` |

**Privacy default:** Conversation content is **not captured** unless `OTEL_LOG_USER_PROMPTS=1` is explicitly set. All detail flags are **off by default**.

**CISO question answer:** "No — prompt content is not captured by default. `OTEL_LOG_USER_PROMPTS=1` is an explicit opt-in not in the current config."

**cost.usage attributes:** model · query_source · speed · effort · agent.name · skill.name · plugin.name · mcp_server.name · mcp_tool.name

### 31.3 — 5-Step Pipeline Setup ⭐

```
1. Master switch (required — everything ignored without it)
   CLAUDE_CODE_ENABLE_TELEMETRY=1

2. Choose exporters (can mix across signal types)
   OTEL_METRICS_EXPORTER=otlp      # or: prometheus, console
   OTEL_LOGS_EXPORTER=otlp         # or: console (no Prometheus for logs)

3. Configure endpoint + auth
   OTEL_EXPORTER_OTLP_ENDPOINT=http://collector.example.com:4317
   OTEL_EXPORTER_OTLP_HEADERS=Authorization=Bearer <token>
   OTEL_EXPORTER_OTLP_PROTOCOL=grpc            # default, port 4317
   # use http/json if collector doesn't support gRPC

4. Deploy via managed-settings.json via MDM
   → High precedence, cannot be overridden by developers
   → Auth token stays out of developer reach
   → Only scalable path for 100+ developer orgs

5. Verify with short export interval (remove before production)
   OTEL_METRIC_EXPORT_INTERVAL=10000  # 10s instead of 60s default
   # Run session → check backend → confirm data arriving → remove override
```

**Tab 1 — Dev / local (console only):**
```
CLAUDE_CODE_ENABLE_TELEMETRY=1
OTEL_METRICS_EXPORTER=console
OTEL_LOGS_EXPORTER=console
# No endpoint needed — output goes to stdout; verify data shape before wiring to a backend
```

**Tab 2 — Production OTLP (deploy via managed-settings.json, NOT .env):**
```
CLAUDE_CODE_ENABLE_TELEMETRY=1
OTEL_METRICS_EXPORTER=otlp
OTEL_LOGS_EXPORTER=otlp
OTEL_EXPORTER_OTLP_PROTOCOL=grpc
OTEL_EXPORTER_OTLP_ENDPOINT=http://collector.example.com:4317
OTEL_EXPORTER_OTLP_HEADERS=Authorization=Bearer your-token
```

**Tab 3 — Multi-team attribution (add to Tab 2, push different attribute blocks per team via MDM):**
```
OTEL_RESOURCE_ATTRIBUTES=department=engineering,cost_center=CC-4421
# Push different values per team via MDM — no org restructuring, no backend transforms needed
```

### 31.4 — Cost Attribution Pattern

`OTEL_RESOURCE_ATTRIBUTES` pushed via MDM → tags **every metric and event** from that machine with org-level labels (department, cost_center) → flows to cost.usage in dashboards automatically.

```
OTEL_RESOURCE_ATTRIBUTES=department=engineering,cost_center=CC-4421
```

Push different attribute blocks per team via MDM → no org restructuring, no backend-side transforms needed.

### 31.5 — Your scenario debrief (6/8 first attempt ⚠️ — Decision 2 was the trap)

| # | Decision | Correct call | Your call | Why |
|---|---|---|---|---|
| 1 — Bash commands in Splunk | `OTEL_LOGS_EXPORTER=otlp` + `OTEL_LOG_TOOL_DETAILS=1` | ✅ +2 | ✅ | Logs exporter enables event stream; tool details adds command content — both required |
| 2 — Department cost attribution | `OTEL_RESOURCE_ATTRIBUTES` via MDM | ❌ 0 | "Create separate Claude orgs per department" | **TRAP:** Separate orgs is an admin/billing restructure. The right tool is `OTEL_RESOURCE_ATTRIBUTES` pushed via MDM — tags every metric/event, no restructuring |
| 3 — Org-wide non-overridable | managed-settings.json via MDM | ✅ +2 | ✅ | High precedence, developer cannot override, only scalable path at 500 devs |
| 4 — Are conversations captured? | No — prompt capture requires explicit opt-in | ✅ +2 | ✅ | Privacy-preserving default; CISO needs this to brief legal/privacy teams |

**Decision 2 memory anchor:** "Separate orgs" = nuclear option (billing split, admin overhead). "OTEL_RESOURCE_ATTRIBUTES" = lightweight MDM label → flows to cost.usage automatically. Cost attribution = labels, not org structure.

---

## Block 32 — Course 7 L5: Audit Logs ⭐⭐

**One-liner:** Audit logs = what changed in the org. Not conversations, not tool calls. 180-day CSV, no setup, any Owner can pull it.

Cross-refs: Block 27 (5-mechanism observability stack) · Block 31 (OTel Pipeline) · Block 33 (Compliance API, Lesson 7.3).

### 32.1 — What Audit Logs Capture

**33 event types across 4 categories:**
- Sign-ins
- Member additions and removals
- Project and file events
- Admin setting changes

**What they do NOT contain:** conversation text · tool call detail · bash commands · prompt or response text · any execution-level data.

| Property | Value |
|---|---|
| **Retention** | 180-day rolling window (older events auto-removed) |
| **Who can access** | Owners and Primary Owners |
| **How to access** | Organization settings › Data and Privacy → CSV export |
| **Setup required?** | None — no API key, no engineering involvement |

### 32.2 — Three Access Patterns

| Pattern | When to use | Key constraint |
|---|---|---|
| **CSV export** (one-off) | Security review, legal governance question, ad-hoc who-changed-what | No date filter — exports full 180-day window; parse locally for targeted queries |
| **Compliance API** (programmatic) | Long-retention needs (up to 6 years), specific user + date range filtering, regulatory audit | Requires Compliance API enabled + Primary Owner key |
| **OTel / SIEM** (real-time) | Real-time alerts on permission mode changes; unified dashboard with execution events | Only captures from when pipeline was enabled — no backfill; use CSV/Compliance API for pre-pipeline history |

**Access pattern decision rule:**
- One-off governance question → CSV export
- Long retention (>180 days) or programmatic user/date filter → Compliance API
- Real-time alerting → OTel SIEM (`claude_code.permission_mode_changed` event)

### 32.3 — Audit Logs vs OTel vs Compliance API (flip card content)

| Surface | Answers | Retention | Access |
|---|---|---|---|
| **Audit logs** | Who joined/left/changed settings · sign-in history · project creation/deletion · admin config changes | 180 days | Any Owner, CSV, no setup |
| **OTel stream** | Every tool call · bash command · MCP invocation · permission mode change · API request | Set by SIEM | Opt-in pipeline, real-time |
| **Compliance API** | Conversation content · activity events with user/date filtering | Up to 6 years | Primary Owner key, programmatic |

**Hard stops per surface:**
- Audit logs stop at: tool calls, bash, conversation content, events >180 days
- OTel stops at: org admin changes not in schema, events before pipeline started, conversation content
- Compliance API stops at: execution-level metadata, real-time delivery

### 32.4 — Your scenario debrief (2/6 first attempt ⚠️ — audit log default instinct)

| # | Decision | Correct call | Your call | Why |
|---|---|---|---|---|
| 1 — Bash commands past week | OTel SIEM (`OTEL_LOG_TOOL_DETAILS=1`), filter by user + date | ❌ 0 | CSV audit log export | **TRAP:** Audit logs have zero bash/tool-call data. Execution → OTel. |
| 2 — 18 months of conversations | Compliance API (user ID + date range filter) | ❌ 0 | CSV audit log export | **TRAP:** Audit logs max 180 days AND have no conversation content. Long retention + content = Compliance API only. |
| 3 — Real-time permission mode alert | SIEM rule on `claude_code.permission_mode_changed` OTel event | ✅ +2 | ✅ OTel SIEM | Real-time execution event → OTel SIEM rule. Correct. |

**Pattern of errors:** Both misses were "audit logs" for questions that needed execution data (OTel) or conversation content with long retention (Compliance API). Audit logs are governance-only.

**Memory anchor — the 3-lane rule:**
- "Who changed the API key last week?" → Audit logs
- "What bash commands did this dev run?" → OTel
- "What did this dev say to Claude for the past 18 months?" → Compliance API
- Audit logs ≠ activity feed. Audit logs ≠ conversation log.

---

## Block 44 — Capstone L4: Troubleshooting Playbook and Activation Plan ⭐⭐

**One-liner:** Weeks 3–4 surface quiet problems: context drift, permission creep, plateau developers, variable pipeline output. "Suggestions feel off" + nothing in metrics = CLAUDE.md hasn't kept up with the codebase.

Cross-refs: Block 41 (setup) · Block 42 (adoption curve) · Block 43 (CI/CD) · Block 38 (champion handoff) · Block 39 (failure modes).

### 44.1 — Four Late-Stage Failure Modes ⭐

| Failure | Symptoms | Fix |
|---|---|---|
| **Context drift** | Suggestions feel "off" — not wrong, just not quite right for the current codebase. No metric flags it. | Review CLAUDE.md with champion. Update architecture + conventions sections to reflect codebase as it is now, not as it was on Day 3. |
| **Permission creep** | Tool permissions widened over the pilot as devs needed broader access. Tight Day 3 scope has grown. Worst in CI pipeline. | Confirm `--allowedTools` scope still matches the actual workflow. Tighten back to minimum needed. |
| **Adoption plateau** | Early adopters at Stage 3–4. A cohort segment still at Stage 1 (supervised only, low task completion, moderate acceptance rate). They haven't flagged it because they're not visibly stuck. | Surface from measurement stack **before Day 30 readout, not after**. Give structured task to move them forward. |
| **Pipeline variability** | GitHub Actions mostly works but not always. Same prompt, variable output across runs. | Check context length and output format constraints. Usually a context/format issue, not a pipeline bug. Consistency > performance at this stage. |

### 44.2 — Champion Readiness: Not Ready vs Ready ⭐

| State | What it looks like | What to do |
|---|---|---|
| **Not ready** | Can use the tool on their own tasks. Defers to you for troubleshooting. Hasn't touched CLAUDE.md. Can't explain the measurement stack to their manager. | More time or structured ownership tasks before you leave. |
| **Ready to hand off** | Has updated CLAUDE.md at least once **without prompting** · can answer basic troubleshooting questions · knows the four scorecard metrics and where to find them · knows the escalation path for anything beyond their scope | That's the bar. |

### 44.3 — Champion Handoff Checklist

- [ ] Champion updated CLAUDE.md at least once without prompting
- [ ] Champion can answer basic troubleshooting questions from cohort
- [ ] Champion knows what the four scorecard metrics mean and where to find them
- [ ] Named escalation path exists for issues beyond champion's scope
- [ ] CI pipeline documentation written and handed to **the team**, not just the champion
- [ ] Day 30 readout reviewed with champion **before** the sponsor session

### 44.4 — Decision: Week 4 scenario (correct: B)

Developers say suggestions feel "off" — not technically wrong, just not quite right. CI pipeline clean. OTel metrics fine. Nothing broken.

| Option | Call | Why |
|---|---|---|
| A: Model has changed | ❌ | Model changes don't produce this qualitative drift pattern. Wrong escalation path. |
| **B: CLAUDE.md hasn't kept up** | **✅** | Qualitative misalignment + no metric flags = context drift. CLAUDE.md describes codebase as it was on Day 3; codebase has evolved. Fix: CLAUDE.md review + update with champion. |
| C: Scope creep (out-of-scope tasks) | ❌ | Out-of-scope tasks produce errors or incomplete output, not "subtly off" suggestions. Different failure signature. |
| D: Switch to verbose mode | ❌ | More explanation doesn't fix stale context. |

**Diagnostic rule:** "Feels off but not broken" = context drift (stale CLAUDE.md). "Errors or incomplete output" = scope creep or task mismatch. Different symptoms, different fixes.

### 44.5 — Technical Activation Plan (capstone artifact milestones)

| Milestone | Key deliverables |
|---|---|
| **Days 1–3** | CLAUDE.md written + confirmed with real task · permissions scoped · measurement stack active (OTel + 4 scorecard metrics) · baseline captured |
| **Day 8** | Test generation in bash mode · 4 metrics reviewed · looping developers identified + resolved (task scope or CLAUDE.md gap) before Day 14 |
| **Day 14** | GitHub Actions live · API key in secrets · `ANTHROPIC_BASE_URL` explicit · `--allowedTools` scoped · first headless run confirmed · proxy routing verified |
| **Weeks 3–4** | CLAUDE.md updated with champion · plateau devs given structured task · Day 30 readout drafted (headline metric + supporting data + renewal next step) |
| **Day 30** | Readout to sponsor 48h in advance · champion ready (6-item checklist) · renewal conversation = decision, not follow-up |

---

## Block 43 — Capstone L3: CI/CD via GitHub Actions Integration ⭐⭐

**One-liner:** `ANTHROPIC_BASE_URL` doesn't carry over from local config to CI — that's the one missing step that causes most enterprise CI failures. Local works + CI fails + key confirmed = proxy routing, not firewall.

Cross-refs: Block 12 (headless/non-interactive mode) · Block 13 (deployment architecture) · Block 41 (Capstone L1 config scope).

### 43.1 — Four-Step GitHub Actions Pipeline

| Step | What to do | Key decision |
|---|---|---|
| **1. Add workflow file** | `.github/workflows/` YAML, triggers on PR or push. Claude Code runs as a step inside an existing job, not a special runner. | Keep it close to existing CI config — not a foreign object |
| **2. Store API key** | GitHub Actions secrets → exposed as `ANTHROPIC_API_KEY`. | **Personal key vs service account key** — service account for shared CI (controlled rotation, won't break when a dev's access changes) |
| **3. Set proxy env var** | `ANTHROPIC_BASE_URL` must be set explicitly in the workflow step. Does NOT carry over from local config or CLAUDE.md. | **This is the step most often missed.** Enterprise gateway URL goes here. |
| **4. Invoke with flags** | `--print` (non-interactive, output to stdout) + `--allowedTools` (scope to exactly what the workflow needs) | Read + test runner + linter = usually sufficient. Broad permissions in non-interactive = harder to audit. |

### 43.2 — Auth in CI: Four Decisions ⭐

| Decision | Right call | Why |
|---|---|---|
| **API key type** | Dedicated service account key | Personal keys break when developer's access changes; service accounts have controlled rotation |
| **Secret storage** | GitHub Actions secrets (or secrets manager if runner has access). Never hardcoded in YAML or committed to repo. | Keys in YAML = committed to version history |
| **Proxy routing** | `ANTHROPIC_BASE_URL` set explicitly as Actions secret, referenced in workflow step | Local env picks it up automatically; CI runner has no equivalent — must be explicit |
| **Tool permissions** | `--allowedTools` scoped to minimum needed | Broad permissions in non-interactive context = hard to audit, hard to explain to security team |

### 43.3 — The Proxy Failure Pattern ⭐⭐

**Symptoms:** GitHub Action fails with connection timeout or 403. Developer's local session works fine. API key confirmed correct.

**Root cause:** `ANTHROPIC_BASE_URL` never set in the workflow. CI runner makes a direct call to Anthropic's API → enterprise network policy blocks it.

**Why it looks like a network issue:** At the router level, it IS a network issue — the runner is being blocked. But the fix is a missing env variable, not a firewall exception.

**Fix:** Add `ANTHROPIC_BASE_URL` as an Actions secret. Value = the enterprise gateway URL (find it in CLAUDE.md or deployment architecture docs). If still fails after URL is correct → then investigate network policy.

**Diagnostic order:** Fix workflow step first → confirm gateway URL → if still fails, then ask IT about runner outbound policy.

### 43.4 — Decision: Day 14 scenario (correct: B)

| Option | Call | Why |
|---|---|---|
| A: Rotate API key | ❌ | Key is confirmed correct. Rotation doesn't address root cause. |
| **B: Check ANTHROPIC_BASE_URL in workflow** | **✅** | Local works, CI fails, key confirmed = asymmetry points to env config not carried to runner. ANTHROPIC_BASE_URL is the most common culprit. |
| C: Switch to verbose mode | ❌ | Gets more info, but you already have enough to diagnose. Fix first, debug-log if fix doesn't work. |
| D: Check runner's outbound network policy | ❌ | At the router level it looks like a network issue, but root cause is missing env var. Fix the workflow step first; only escalate to IT if the gateway URL is confirmed and it still fails. |

---

## Block 42 — Capstone L2: Test Generation and Debugging Exercise ⭐⭐

**One-liner:** Bash mode = shell pipeline mental model (source in → tests out). Four Day 8 metrics tell a story together. Intervention call turns on one distinction: iterating (each attempt explores something different) vs looping (same attempt, same failure, no variation).

Cross-refs: Block 37 (adoption curve) · Block 33 (cost.usage) · Block 41 (Capstone L1 setup).

### 42.1 — Bash Mode vs IDE Mode

| Aspect | IDE mode | Bash mode |
|---|---|---|
| Interaction model | Conversational back-and-forth | Claude as a component in a shell pipeline |
| Test generation pattern | Edit in context | Pipe source file in → tests come out |
| CI relevance | High for workflow | **Direct bridge to headless CI automation** — once you see it work interactively, the jump to a headless pipeline feels smaller |

**When to demonstrate bash mode:** Test generation is one of the cleaner ways to show it — the pipeline metaphor clicks when developers see it running, not described.

### 42.2 — Four Day 8 Scorecard Metrics ⭐

| Metric | Target | Warning signal | Next action |
|---|---|---|---|
| **Adoption (DAU)** | 60% of cohort by Week 3 | <40% at Day 8 | Check friction source: tool, workflow, or slow starts |
| **Engagement depth (sessions/user)** | 2–3/day | <1.5/day | Developers opening but not integrating; pair with `active_time.total` from OTel |
| **Week 2 retention** | ≥80% | <80% | Drop-off predicts churn at expansion; novelty wore off, not a product failure |
| **Cost/developer** | Track weekly | Spike without matching productivity gain | Investigate before sponsor asks; set up tracking proactively |

### 42.3 — Iterating vs Looping ⭐ (intervention decision key)

| State | What it looks like | Right call |
|---|---|---|
| **Still iterating** | Each attempt explores a different part of the problem. Output isn't right yet but direction is changing. | **Wait.** Stepping in interrupts learning that's actually happening. |
| **Looping** | Same prompt structure, same failure mode, no meaningful variation in approach. | **Step in — assess scope, then decide.** |

**Intervention decision:** Looping trigger = same structural failure across 3 attempts with no variation. Step in means **assess first, not fix**:
- Is the task outside what Claude Code handles well at this stage?
- Is CLAUDE.md missing context that would help Claude understand the codebase?
- Then decide on the intervention.

**OTel data won't help here** — session metrics don't tell you what's happening in this specific session. That takes a conversation.

### 42.4 — Decision: Day 8 scenario (correct: B)

Developer stuck 45 min in bash mode. Tests syntactically valid but targeting wrong behavior. 3 requests with same failure, structure changes but underlying problem doesn't.

| Option | Call | Why |
|---|---|---|
| A: Let them keep going | ❌ | 3 attempts, same failure = looping not iterating. 45 min is enough signal. |
| **B: Step in and assess scope** | **✅** | Looping detected. Assess first: task scope? CLAUDE.md gaps? Then intervene. |
| C: Pull OTel data first | ❌ | OTel shows session metrics, not what's happening in this specific session |
| D: Ask champion to handle it | ❌ | Champion role is Day 30+ ownership, not Day 8 active developer coaching |

---

## Block 41 — Capstone L1: Multi-File Refactor Exercise ⭐⭐

**One-liner:** Get the scaffold right before the first command. Config scope hierarchy, CLAUDE.md specificity, deny-first permissions, parallel orchestration only for isolated/stable modules — don't parallelize when you can't trust the baseline.

Cross-refs: Block 16 (parallel orchestration / subagents) · Block 35 (pilot design) · Block 40 (activation arc).

### 41.1 — Four Pre-Execution Setup Steps

| Step | What to do | Key rule |
|---|---|---|
| **1. Confirm config scope** | Check managed-settings.json isn't silently overriding project-level config. For pilots: project scope does the work, individual devs can still adjust theirs. | Managed settings = top of hierarchy, can't be overridden by anything below |
| **2. Write project CLAUDE.md** | Architecture constraints · testing framework · code conventions · off-limits paths | **Specific beats general.** "Don't modify /billing/legacy/" ✅ vs "be careful with legacy code" ❌ |
| **3. Set permissions model** | Deny → Ask → Allow. Day 3: put file writes in **ask mode** — builds team confidence in what's happening. Lock down out-of-scope directories. Deny wins; an ask rule cannot bypass a deny rule. | Ask mode at Day 3 is not distrust — it's habit-forming for the team |
| **4. Choose output style** | Default = efficient, precise, no commentary (good for Day 3 iteration). Explanatory = adds insights section per output explaining implementation choices (good for group review). | Set explicitly — right style for the session makes a noticeable difference |

### 41.2 — Four CLAUDE.md Fields for Client Projects

| Field | What to include | Bad version | Good version |
|---|---|---|---|
| **Architecture constraints** | What Claude shouldn't change: import patterns, file structure, folder ownership, team-owned modules | "Be careful with architecture" | "Don't modify files in /billing/legacy/ or change import structure in /auth/" |
| **Testing framework** | How tests are written, how to run them, what passing looks like. Name known flaky tests. | "Tests are in Jest" | "Run `npm test`. Tests in /tests/. Legacy billing tests are flaky — don't chase pre-existing failures in /tests/billing/" |
| **Code conventions** | Naming patterns, formatting, linting rules. Specific > generic. | "Follow standard conventions" | "camelCase for variables, PascalCase for components, ESLint config at root" |
| **Off-limits paths** | Explicit directories/files, with reason where possible | "Don't touch sensitive stuff" | "Don't touch /billing/legacy/ — unstable test suite, scoped separately" |

### 41.3 — Parallel Orchestration Decision Rule ⭐

**Pattern:** Orchestrator spawns subagents → each works one isolated module → results feed back up. Orchestrator coordinates, does NOT refactor.

**Key property:** Context isolation — each subagent sees only its module. Failure in one module doesn't cascade. But this only works when **the baseline is reliable.**

**Decision framework for Day 3 billing/auth/API scenario:**

| Option | Call | Reason |
|---|---|---|
| A: All three in parallel | ❌ | Can't trust billing baseline — can't tell if subagent broke something or tests were already broken |
| **B: Auth + API parallel, hold billing** | **✅** | Stable modules get parallelization. Billing gets sequential pass after team reviews the test suite. |
| C: All sequential | ❌ | Leaves time on table; parallel is the right tool for independent stable modules |
| D: Start with billing | ❌ | Fixing billing tests before the refactor is a bigger commitment than Day 3 can absorb |

**Rule:** Don't parallelize when you can't trust the baseline. Context isolation means each subagent fails independently — which sounds ideal until you can't distinguish a new failure from a pre-existing one.

---

## Block 40 — Course 8 L7: 30-Day Claude Code Activation Arc ⭐⭐

**One-liner:** Five phases with hard exit conditions. Two touchpoints scheduled before Day 1. Three-part 30-min showcase with sponsor in the room. Office hours is the handoff mechanism — not a conversation, champion co-facilitates from session 2, runs session 3.

Cross-refs: Block 39 (failure modes) · Block 38 (champion) · Block 35 (pilot design).

### 40.1 — Five Phases + Exit Conditions ⭐

| Phase | Duration | Job | Exit condition |
|---|---|---|---|
| **Pre-kickoff discovery** | Before Day 1 | Use case qualification · cohort selection + availability · baseline data from VCS · draft CLAUDE.md | Baseline captured · CLAUDE.md drafted · cohort confirmed · kickoff date set |
| **Week 1: Onboarding sprint** | Days 1–7 | Full cohort installs Claude Code, connects to approved deployment config, runs first tasks in supervised mode · first office hours Day 3–4 | Full cohort active, zero installation blockers outstanding |
| **Weeks 2–3: Active pilot** | Days 8–21 | Weekly CoE touchpoints Day 8 + Day 15 · usage data review · coaching for stalled devs · champion candidate identified in Week 3 | ≥50% of cohort past supervised mode · champion candidate identified |
| **Week 4: Ramp + showcase prep** | Days 22–29 | Compile metrics vs success criteria · draft readout + CIO narrative · champion conversation · CLAUDE.md review + command catalogue build · escalation path documented · readout to sponsor 48h before showcase | Readout sent · champion briefed · four artifacts complete |
| **Day 30: Showcase + readout** | Day 30 | Live demo · metrics readout · renewal conversation. **Sponsor must be in the room** — if unavailable, reschedule. | — |

### 40.2 — Two Recurring Touchpoints (both calendared before Day 1) ⭐

| Touchpoint | Format | Cadence | Agenda | Exit output |
|---|---|---|---|---|
| **CoE touchpoint** | 30 min, consultant-led | Day 8 + Day 15 | Review previous week's usage data · identify supervised-mode-stalled devs · agree on one concrete coaching action per stalled dev · check CLAUDE.md for updates | Specific intervention OR green light to proceed |
| **Office hours** | 60 min, open attendance | Weekly | Developer Q&A, real tasks + real friction + real code. No fixed agenda. | Consultant-led (session 1) → champion co-facilitates (session 2) → **champion runs it, consultant observes (session 3)** |

**Scheduling rule:** Calendar links + video links created before the kickoff meeting. Post-kickoff scheduling = friction + signals the structure isn't fixed. Treat as immovable until Day 30.

**Office hours = the handoff mechanism.** Not a conversation about handing over office hours — the champion does it while still supported.

### 40.3 — Day 30 Showcase Structure ⭐

Three parts. Thirty minutes. Sponsor in the room (no sponsor = reschedule).

| Part | Duration | Content | Key rules |
|---|---|---|---|
| **Live demo** | 10 min | 2–3 cohort developers on real tasks from the pilot. Real code, real friction, real workflow — not a script, not a recording. | Pick Stage 3–4 developers. Stage 1 devs demo supervised mode = undersells capability. |
| **Metrics readout** | 10 min | Lead with headline number first: "PR cycle time dropped 36% for the migration cohort over 30 days." Then supporting data vs agreed success criteria. | If criteria weren't met, name them and explain WHY before the sponsor asks. |
| **Renewal conversation** | 10 min | Phase 2 scope · champion introduction + role · 90-day health check · specific next step | Sponsor leaves the room with **a decision to make, not a follow-up to schedule**. |

### 40.4 — Key Numbers to Memorize

| Item | Value |
|---|---|
| Readout sent to sponsor | 48 hours before showcase (not during the meeting) |
| CoE touchpoints | Day 8 and Day 15 |
| Champion identified by | Day 15 (Week 2–3 exit condition: Week 3) |
| Supervised mode exit | ≥50% of cohort by end of Week 3 |
| Showcase attendance requirement | Sponsor must be present — reschedule if not |
| Custom command minimum | 3–5 documented commands at handoff |
| Office hours progression | Session 1: consultant · Session 2: co-facilitate · Session 3: champion runs |

---

## Block 39 — Course 8 L6: Preempting Common Failure Modes ⭐⭐

**One-liner:** Six failure modes, all process gaps, all preemptable before Day 1. Four artifacts at Day 30 = deployment survives without you. No baseline + no champion + no commands = three HIGH risk flags.

Cross-refs: Block 38 (champion) · Block 36 (baseline capture) · Block 34 (qualification).

### 39.1 — Six Failure Modes ⭐⭐

| # | Failure | What it looks like | Preemption |
|---|---|---|---|
| **1** | No baseline captured | ROI case falls apart at Day 30 readout — no before state, no defensible number, renewal can't land | **Baseline sprint in the week before kickoff** — non-negotiable |
| **2** | Champion not identified | Adoption drops 30–60 days post-engagement. No one owns CLAUDE.md. New devs not onboarded. Deployment decays to zero within a quarter. | **Name the champion by Day 15**, begin handoff prep in Phase 2 |
| **3** | Use case too marginal | Metrics flat at Day 30 despite high usage. Sponsor expected transformational, saw incremental. Executive support evaporates. | Run structural vs. marginal qualification from L1 **before** scoping pilot |
| **4** | Supervised mode stagnation | Usage plateau after Week 1. Developers say tool is "slow" or "not useful." PR cycle time unchanged. No productivity story. | Weekly CoE touchpoint with usage review; workflow-fit coaching for stalled devs in Phase 2 |
| **5** | CLAUDE.md not maintained | Claude reverts to generic behavior as codebase evolves past initial CLAUDE.md. Team trust erodes. Adoption regresses. | Weekly CLAUDE.md review as **named champion responsibility** — in champion plan artifact |
| **6** | Readout not tied to business outcome | Day 30 presents usage metrics + dev testimonials but no business-level translation. CIO disengaged. Conversation moves to cost, not value. Renewal stalls in procurement. | Align CIO narrative with sponsor in **Week 1** using L3 framework |

### 39.2 — Four Clean-Handoff Artifacts ⭐

All four must be present at Day 30. Missing any one puts 90-day deployment health at risk.

| Artifact | What it covers | Failure modes it prevents |
|---|---|---|
| **Delivery Plan Pack (complete)** | Qualification + pilot design + ROI scorecard + champion plan. Anchors renewal conversation and Phase 2 scoping. | F6 (no business narrative) |
| **CLAUDE.md + custom command catalogue** | Enterprise CLAUDE.md + ≥1 repo-specific CLAUDE.md + 3–5 documented commands (frontmatter + params + examples) | F5 (CLAUDE.md decay) |
| **Day 30 readout with metrics vs success criteria** | Headline number + supporting data + CIO narrative. In client's hands **48 hours before** the showcase meeting, not distributed during it. | F1 (no baseline), F6 (no business outcome) |
| **Named champion + documented escalation path** | Person + role description + consultant escalation line + **30-day post-engagement check-in date** set before you leave | F2 (no champion) |

### 39.3 — HIGH vs LOW Risk Signals (scenario pattern)

**HIGH risk (deployment at risk):**
- No baseline captured — readout has no before state
- No champion identified by Day 28 — post-engagement decay is certain
- No custom commands — empty command catalogue = handoff incomplete (Failure 5)

**LOW risk (concerning but manageable):**
- 4/12 developers still in supervised mode at Day 28 — not ideal; flag for post-engagement check-in, but doesn't block renewal
- PR cycle time +20% — positive signal
- 3 high-session-count developers — positive signal

**Memory anchor for HIGH vs LOW:** The three HIGH flags map directly to the three pre-Day-1 non-negotiables: **baseline + champion + commands**. If any of those three are missing at Day 28, the deployment is at risk.

---

## Block 38 — Course 8 L5: Champion Enablement and Internal Documentation ⭐

**One-liner:** Champion = influence + intrinsic motivation, not just tech skill. CLAUDE.md is a living artifact, not a deliverable. Custom commands at handoff are required infrastructure. 3-artifact handoff is non-negotiable.

Cross-refs: Block 37 (adoption curve) · Block 39 (failure modes).

### 38.1 — Champion Role Definition

| Dimension | What it means |
|---|---|
| **What they do** | Maintain + evolve CLAUDE.md · run weekly office hours or standing channel · onboard new devs · escalate blockers to consultant |
| **What they don't do** | Be the team's help desk / sole knowledge holder — fragile deployment if knowledge doesn't distribute |
| **What they need** | Populated CLAUDE.md · custom command catalogue (3–5 commands) · clear escalation path to consultant. Handoff conversation happens **before Day 30**, not on it. |
| **Best candidate profile** | Senior enough to influence team norms · technical enough to write CLAUDE.md and evaluate commands · **intrinsically motivated, not assigned** |

**Best candidates identify themselves during Phase 2** by engaging deeply without being asked.

### 38.2 — CLAUDE.md as Living Artifact ⭐

CLAUDE.md is not documentation. It is **institutional memory Claude reads every session.**
- Generic CLAUDE.md → generic Claude behavior
- Well-maintained CLAUDE.md → encodes conventions, patterns, preferred tools, domain context; every developer benefits from every update
- Unlike a Confluence guide, it is **active** — shapes Claude's behavior in real time
- Champion's job: treat it as a living artifact, not a one-time deliverable

**Handoff principle:** "The quality of a deployment 90 days after you leave is determined by the quality of the CLAUDE.md you hand over."

### 38.3 — Three Mandatory Handoff Artifacts ⭐

1. **Enterprise-level CLAUDE.md** — company conventions
2. **Repo-specific CLAUDE.md** — for the project the pilot cohort worked on
3. **Custom command catalogue** — minimum 3–5 commands, with frontmatter + parameter descriptions + example invocations

If pilot team hasn't built these → that is the work of Phase 3 and the handoff session, not something to skip.

### 38.4 — Three True/False Anchors (all False)

| Statement | Answer | Why |
|---|---|---|
| "Champion = most technically advanced developer" | **False** | Tech fluency matters, but **influence + intrinsic motivation > tech skill**. Most technical dev may have unusual workflows that don't generalize. Champion shapes team norms. |
| "CLAUDE.md should be finalized and stable before engagement ends" | **False** | Living document. "Finalized" = wrong framing. Handoff CLAUDE.md should be **good enough to produce immediate improvement** + have a named owner to evolve it. |
| "Custom commands optional for small teams" | **False** | Encode best practices in reusable form that survives personnel changes. Small teams that skip commands in first 30 days typically never build them. **Non-negotiable at handoff.** |

---

## Block 37 — Course 8 L4: Phased Rollout and Change Management ⭐⭐

**One-liner:** Adoption follows a predictable 3-phase curve. Week 1 dip = calibration (don't intervene). Plateau after Week 2 = delegation ceiling (intervene with Code 201). Day 16 is NOT too early — it's exactly when plateau becomes visible.

Cross-refs: Block 35 (pilot design) · Block 38 (champion enablement).

### 37.1 — Three-Phase Adoption Curve

| Phase | Duration | What's happening | Intervention |
|---|---|---|---|
| **Supervised use** | Week 1 | Manual approval for every action. Slower velocity than without Claude. Calibrating prompting style. | Don't intervene on velocity. Expectation-set only. |
| **Increasing autonomy** | Weeks 2–3 | More advance approvals. Larger task chunks. Plan mode usage increases. Some auto-accept on low-risk tasks. CLAUDE.md quality starts to matter. | Watch for plateau. Code 201 if pattern stalls. |
| **Agentic mode** | Weeks 3–4 | Defined task classes handed off with minimal supervision. PR cycle time improvement becomes visible. | Auto-accept mode, hook config, agentic task structuring. |
| **Institutionalized** | Day 30+ | Usage is routine. Informal norms about delegation, supervision, briefing. This is target state — can't be forced earlier. | Document patterns. Update CLAUDE.md. |

### 37.2 — Two AI-Specific Adoption Dynamics ⭐

**1. The Week 1 dip**
- Velocity slows before it accelerates
- Developers are learning a new interaction model (prompting loop, supervision decisions, delegation judgment)
- Output looks inconsistent, usage looks low
- **NOT a signal to intervene with training.** It's calibration happening.

**2. The Plateau effect**
- After Week 1, developers find comfortable usage patterns and stop experimenting
- 45 min/day with flat PR cycle time = tool is in workflow but delegation ceiling hasn't been raised
- Usage looks like adoption but ceiling is much lower than it should be
- **Needs champion intervention or structured Code 201 session to break**
- Rule: "A developer who has stopped experimenting is not a success story. Plateau ≠ adoption."

### 37.3 — Intervention Test ⭐

**The question:** Is the developer stuck on a Claude Code problem or a workflow design problem?

| Problem type | Signal | Correct intervention |
|---|---|---|
| **Technical** | Hallucinated output, prompt failures, context issues | Help now — CLAUDE.md setup, prompting calibration |
| **Workflow design** | Same tasks as before, Claude = faster autocomplete | Rethink delegation pattern, not prompting technique |

**Week-by-week intervention map:**
- **Week 1:** Technical calibration, CLAUDE.md setup, first commit. Don't push velocity.
- **Week 2:** Delegation pattern review, plan mode encouragement, Code 201 session. Watch for plateau.
- **Week 3:** Auto-accept for defined task classes, hook config, agentic task structuring. Track whose usage is still climbing vs. plateaued.
- **Week 4:** Document what worked, what broke, what CLAUDE.md should say that it doesn't.

### 37.4 — Champion Activation

Peer demonstration > feature in report > individual mentoring.
- **Peer demo:** 30-min session showing CLAUDE.md setup, delegation patterns, 2 before/after PR examples. Concrete, credible, replicable.
- **CTO report:** stakeholder management — use alongside demo, not instead of it.
- **Individual mentoring:** scales poorly; one group demo > ten 1:1s.

### 37.5 — Your scenario debrief (5/6 — Decision 1 was the trap)

| # | Decision | Correct call | Your call | Why |
|---|---|---|---|---|
| 1 — Reading Day 16 data | Plateau signature — needs Code 201 | ❌ +1 | "Too early to draw conclusions" | **TRAP:** Day 16 is NOT too early. 2 weeks of consistent data = plateau is visible. Waiting to Day 25 leaves 5 days to change a 30-day trajectory. Flat PR cycle time + consistent usage + unchanged prompting pattern = plateau, not "still calibrating." |
| 2 — Intervention choice | Code 201: plan mode + auto-accept for low-risk tasks | ✅ +2 | ✅ | Directly addresses delegation ceiling |
| 3 — Champion activation | Priya 30-min peer demo (CLAUDE.md + patterns + before/after) | ✅ +2 | ✅ | Highest-leverage adoption lever; replicable method, not just a success story |

**Memory anchor:** Day 16 data pattern = flat PR cycle time + real usage (45 min/day) + unchanged prompting = **plateau**. Resist "too early." The intervention window is exactly now.

---

## Block 36 — Course 8 L3: Baseline Capture and ROI Measurement ⭐⭐

**One-liner:** Baseline before Day 1 = objective data. Baseline reconstructed after = contested negotiation. One headline metric + one scoped business translation = defensible Day 30 story.

Cross-refs: Block 35 (pilot design) · Block 34 (qualification).

### 36.1 — Baseline Capture Rule

**Common failure mode:** Start the pilot, then try to reconstruct a baseline from memory/estimates. That reconstruction is always contested — sponsors remember the past as better or worse depending on whether they want the pilot to succeed.

**Rule:** A baseline captured after the pilot starts is already contaminated. Data collection is pre-work, not post-work.

**Minimum baseline set (2–3 data points):**
1. PR cycle time (ticket-to-merge) for the target use case — objective, auditable
2. Self-reported hours on the specific task category — objective
3. Developer NPS / satisfaction score — directional, supporting only

### 36.2 — Four Metric Categories

| Category | What to track | Collection source |
|---|---|---|
| **Developer Productivity** | New feature dev time · prototyping velocity · suggested code acceptance rate | PR analytics · JIRA · sprint data |
| **Code Quality** | First-pass review success rate · security fix velocity · code coverage changes | PR review data · static analysis tools |
| **Usage and Adoption** | DAU/WAU · % using after 30 days · hours in tool | Claude usage analytics |
| **Sentiment and Culture** | Developer NPS · qualitative feedback · other-team interest | 3–5 question survey |

### 36.3 — Day 30 Readout Structure ⭐

**Principle:** One headline number, one business implication — give the sponsor a number they can repeat in their next leadership meeting.

| Step | What to do | Weak version | Strong version |
|---|---|---|---|
| **1. Lock headline metric** | One metric most directly tied to the use case | "Developer productivity improved" | "PR cycle time: 8.2 → 5.4 days (34%)" |
| **2. Business translation** | Convert metric to roadmap language | "Developers are 34% more productive" ❌ | "Team ships features in 5.4 days that previously took 8.2 — roughly 35% roadmap acceleration for this use case" ✅ |
| **3. Day 30 Scorecard** | One-pager with all elements | Bullet list of metrics | Use case story + headline + supporting metrics + champion anecdote + Day 60 goal |

**Business translation rule:** Scope the claim to the metric. "PR cycle time dropped 34%" → "roadmap velocity for this use case." NOT "overall developer productivity." Overstating = credibility risk if other metrics are flat.

### 36.4 — Expansion Decision Framework

| Option | When to choose | Risk |
|---|---|---|
| **Expand same use case + one new use case with its own baseline** | Strong pilot data, CTO asks for next step | None — this is the controlled expansion |
| **Roll out to all developers** | — | Broad but thin data; loses clean measurement structure |
| **Run another 30-day pilot with same cohort** | — | Delay risks losing sponsor momentum; existing data is sufficient |

### 36.5 — Your scenario debrief (5/6 — Decision 2 cost you a point)

| # | Decision | Correct call | Your call | Why |
|---|---|---|---|---|
| 1 — Headline metric | PR cycle time: 34%, 8.2→5.4 days | ✅ +2 | ✅ | Objective, auditable, tied to use case |
| 2 — Business translation | "Ships features in 5.4 days that took 8.2 — ~35% roadmap acceleration for this use case" | ❌ +1 | "Developers are 34% more productive" | **TRAP:** PR cycle time = one productivity signal. "34% more productive" generalizes to overall productivity — a skeptical CIO will immediately ask "but what about code quality, support time, etc." Scope the claim to the metric. |
| 3 — Expansion recommendation | Expand same use case (20 devs) + new use case with own baseline | ✅ +2 | ✅ | Controlled expansion; original story accumulates evidence; Phase 2 starts clean |

**Memory anchor for business translation:** "PR cycle time improved X% → roadmap velocity for *this use case* improved X%." Never generalize one metric to overall productivity. Precision protects credibility.

---

## Block 35 — Course 8 L2: Pilot Design ⭐⭐

**One-liner:** Cohort = use case owners (not enthusiasts). Success criterion = baseline + threshold + measurement method + target date, locked before Day 1. Scope creep mid-pilot = diluted ROI story.

Cross-refs: Block 34 (qualification) · Block 36 (baseline capture + ROI measurement).

### 35.1 — Cohort Selection Rule

| Wrong cohort | Right cohort |
|---|---|
| Willing participants / early adopters | Use case owners |
| High usage metrics, positive sentiment, not representative | Active tickets, familiar patterns, attributable before/after data |
| Fails CIO scrutiny — doesn't extrapolate to broader team | Metric story writes itself at Day 30 |

**Rule:** Cohort selection is a design decision, not an availability decision.

### 35.2 — Four Scoping Decisions (Before Day 1)

1. **Use case precision:** Not "code modernization" — "Java-to-Spring Boot migration of the auth service module." Specific scope = clean ROI attribution.
2. **Cohort by ownership:** Developers actively working on the scoped use case, not those with calendar space.
3. **Duration by task cycle:** Long enough for ≥2 complete task cycles (ticket-to-merge) per developer. Migration work: 25–30 days is enough.
4. **Lock scope before Day 1:** New use cases that emerge → log for Phase 2. Protect original scope.

### 35.3 — Four Success Criteria Components ⭐

| Component | What it means | Weak version | Strong version |
|---|---|---|---|
| **Baseline metric** | Metric to move, measured before Day 1 | "PR cycle time" (tracked generally) | PR cycle time captured for this cohort on this backlog before kickoff |
| **Target threshold** | Specific number that constitutes a win | "PR cycle time improved" | "25% reduction in PR cycle time" |
| **Measurement method** | How data is captured | Self-reporting | Existing tooling (git, JIRA, PR analytics) — auditable |
| **Target date** | Named date for assessment | "Around Day 30" | "2026-09-15 — readout date locked in kickoff" |

**Design rule:** A success criterion you can't measure before Day 1 is a hypothesis, not a commitment. **Set the baseline before the kickoff meeting.**

### 35.4 — Scope Protection

Mid-pilot expansion dilutes the ROI story. One strong use case with clean data > two mixed stories with thin attribution. New opportunities → Phase 2 queue, not current pilot. This is a feature, not a limitation — it's what makes the Day 30 readout defensible.

### 35.5 — Your scenario debrief (6/6 ✅)

All correct. Anchors:
- 8 migration owners > 15 mixed > 45 all-hands — depth beats breadth at Day 30
- PR cycle time > satisfaction score (not a business case) > LOC (vanity metric)
- Scope protection: log documentation for Phase 2, don't split focus mid-pilot

---

## Block 34 — Course 8 L1: Use Case Identification and Qualification ⭐⭐

**One-liner:** Structural gain (changes what work is possible) = defensible ROI. Marginal gain (same work faster) = adoption momentum only. Qualify before scoping — measurability is non-negotiable.

Cross-refs: Block 35 (Pilot design) · Block 37 (Day 30 ROI scorecard).

### 34.1 — Qualification Filter: Marginal vs Structural

| Type | What happens | ROI story | Examples |
|---|---|---|---|
| **Marginal gain** | Same work, faster. Unit of work doesn't change. | Diffuse, hard to isolate in 30 days. Good for adoption momentum, not CIO readout. | Autocomplete, boilerplate, inline docs |
| **Structural gain** | Unit of work itself shifts. Fewer people, shorter time, for the same or greater output. | Measurable before Day 30, defensible at readout, anchors renewal. | Legacy migration at scale, full-feature loops, framework modernization |

**Decision rule:** If it can't anchor a CIO readout at Day 30, it's not a pilot use case — it's an adoption metric.

### 34.2 — Engagement Modes

| Mode | Format | What you get | What you don't get |
|---|---|---|---|
| **Mode 1** | 2-day training activation (Code 101 + admin setup) | Adoption signals | No ROI data — no measurement period, no use case owner, no baselined metrics |
| **Mode 2** | 30–45 day structured program | Pre-kickoff setup + use case definition + Day 20–25 midpoint check + Day 30 closeout readout | — |

**Mode 2 is the only mode that produces ROI data.** Measurement infrastructure must be built before Day 1 or the loop can't close.

### 34.3 — Three Engagement Patterns That Consistently Win ⭐

| Pattern | What Claude does | Core metric |
|---|---|---|
| **Code modernization** | Migrate legacy stacks, translate languages, upgrade dependencies at volume | Claude-assisted commits / total commits |
| **New feature build** | Full feature loop: scaffold → implement → tests → review prep | PR cycle time (ticket-to-merge) |
| **Code migration** | Move between frameworks, cloud providers, or architectural patterns. Well-scoped, high-volume, low-ambiguity. | Velocity gain visible within first 2 weeks |

### 34.4 — Four Qualification Criteria ⭐

| Criterion | What it means | Fail signal |
|---|---|---|
| **Volume** | Task recurs frequently enough to generate meaningful data in 30 days | One-off project = not qualifying, regardless of complexity |
| **Complexity** | Claude adds real leverage, not just speed | Junior dev could do it in an afternoon = marginal |
| **Measurability** | Can capture a baseline before Day 1 | Can't baseline it = can't close the loop = NOT a pilot candidate |
| **Developer readiness** | Team willing to change workflow, not just try a tool | "Occasional use around existing habits" = flat metrics |

**Qualification rule:** A use case that scores on complexity but fails on measurability is **a risk, not a pilot candidate**.

### 34.5 — Pilot Design Decisions

**Cohort size:** 8–10 developers who own the scoped backlog. Tight cohort = deep, traceable signal. 60 devs = too broad, no attribution. 20 across 4 teams = mixed tasks, thin ROI story.

**Baseline metric:** PR cycle time (ticket-to-merge). Why: auditable, already in tooling, captures the full loop. Avoid: dev hours (self-reported, estimation bias), lines of code (vanity metric).

**Use case selection:** High volume + pre-scoped + all 4 criteria = go. Mixed structural + marginal in same pilot = diluted attribution.

### 34.6 — Your scenario debrief (6/6 ✅)

All correct. Clean sweep. Anchors to remember:
- Migration over test coverage (82% coverage = marginal gain, migration = structural)
- PR cycle time over dev hours or LOC (auditable, existing tooling, full loop)
- Tight cohort (8–10) over broad (20+) — depth over breadth for Day 30 signal

---

## Block 33 — Course 7 L6: Cost Monitoring, Attribution, and Spend Controls ⭐⭐

**One-liner:** Three cost layers (Admin dashboard / Analytics API / OTel cost.usage), one charge-back surface (OTel + OTEL_RESOURCE_ATTRIBUTES), one authoritative billing source (API provider console). OTel is an estimate — never quote it as the invoice.

Cross-refs: Block 31 (OTel pipeline + cost.usage attributes) · Block 32 (audit logs) · Block 26 (scorecard metrics).

### 33.1 — Three Visibility Layers

| Layer | What it answers | Access | Granularity |
|---|---|---|---|
| **Admin dashboard** | Executive spend overview — Spend by model and feature | Organization settings, any Owner, no setup | Org-wide, daily update |
| **Analytics API** | Programmatic spend by workspace, date range, BI export | Admin API key required | By workspace, daily snapshots |
| **OTel cost.usage** | Per-team attribution, real-time, charge-back | OTel pipeline + OTEL_RESOURCE_ATTRIBUTES MDM | Per session, per team label, real-time |

**Decision rule per stakeholder:**
- CTO wants monthly summary → **Admin dashboard** (no setup, visual, any Owner can share)
- Finance needs per-team charge-back → **OTel cost.usage + OTEL_RESOURCE_ATTRIBUTES labels**
- Finance reconciling the invoice → **API provider billing console** (Anthropic / Bedrock / Vertex)
- Internal BI report by workspace → **Analytics API**

### 33.2 — cost.usage Metric Deep Dive ⭐

`claude_code.cost.usage` — emits estimated USD spend at end of each session (accumulates across all API requests in that session).

**Built-in attributes on every data point:**
- `model` — which Claude model was used
- `query_source` — `human` | `subtask` | `tool_use`
- `agent.name`, `skill.name`, `plugin.name`, `mcp_server.name`, `mcp_tool.name` — tagged when those features are used

**Custom labels via MDM:**
```
OTEL_RESOURCE_ATTRIBUTES="department=engineering,team.id=platform,cost_center=eng-123"
```
Scope different attribute blocks per team in MDM → every metric from that device carries the label → SIEM groups cost.usage by `team.id` → charge-back report.

**Companion metric:** `claude_code.token.usage` — breaks spend into token counts by type (input / output / cacheRead / cacheCreation). Use when client needs to understand cost composition, not just total. Cache read:creation ratio tells you whether session design is efficient.

**Query tip:** metric emits per session (not per request). Query SIEM for session totals, not individual data points, when building cost reports.

### 33.3 — Approximation Caveat ⭐ (mandatory in every finance briefing)

`cost.usage` is a **client-side approximation** based on published model pricing × token counts.

| Use for | Do NOT use for |
|---|---|
| Team charge-back allocation | Authoritative invoice amount |
| Budget trend monitoring | Quoting billable figures to finance |
| SIEM alerting thresholds | Reconciling provider invoices |

**Authoritative billing source:** Anthropic Console | AWS Bedrock billing | GCP Vertex billing.

**Standard variance:** typically small; can appear during model pricing changes or caching behavior shifts. **Reconcile against official billing quarterly.**

Briefing script: "The SIEM figure is an estimate — use it to allocate spend across teams. For the actual invoice, the source of truth is [provider] billing. A small variance like 3% is expected and normal."

### 33.4 — Spend Controls

| Control | Mechanism | When to use |
|---|---|---|
| **Hard cap** | Admin API `POST /v1/organizations/spend_limits` — monthly cap **per user**, body `{"scope":{"type":"user","user_id":...},"amount":"75000"}`. **Claude Enterprise only — not available on Claude Platform/Console.** Needs `write:spend_limits` scope. Amounts are strings in minor units (cents) | Budget enforcement; prevent runaway usage |
| **Charge-back** | `OTEL_RESOURCE_ATTRIBUTES` team labels via MDM → SIEM groups `cost.usage` by label | Multi-team monthly allocation to finance |
| **Proactive alert** | SIEM rule on `claude_code.cost.usage` rolling total by team label → Slack/email | Early warning before hard cap hits |
| **Finance note** | OTel = estimate; provider console = invoice | Every finance briefing, every time |

**Hard cap setup:** set limits per team workspace, not at org level — org-level caps are too blunt for multi-team deployments.

**Alert + cap design:** alert fires first (threshold below cap) → team adjusts → hard cap is the backstop if alert is missed.

### 33.5 — Day 1 DevOps handoff artifact (4-panel dashboard spec)

| Panel | Metric | Group by | Purpose |
|---|---|---|---|
| Sessions | `session.count` | day | Adoption signal |
| Active developers | `active_time.total` | user | Engagement depth |
| Token volume | `token.usage` | model, type (input/output/cache) | Cost composition + efficiency |
| **Cost by team** | `cost.usage` | `team.id` (OTEL_RESOURCE_ATTRIBUTES) | Charge-back; secondary attributes: model, query_source |

Spend alert: SIEM rule on weekly `cost.usage` per `team.id` → threshold fires Slack notification before Admin API spend limit triggers hard stop.

### 33.6 — Your scenario debrief (2/6 first attempt ⚠️ — over-engineering instinct)

| # | Decision | Correct call | Your call | Why |
|---|---|---|---|---|
| 1 — CTO monthly summary | **Admin dashboard** (Org settings, any Owner, no setup) | ❌ 0 | API provider billing console | **TRAP:** Provider console = authoritative invoice, but it's not the CTO's first tool. Admin dashboard is inside the Claude experience, visual, no setup. Save provider console for finance reconciliation. |
| 2 — Finance charge-back, 8 teams | **OTel cost.usage + OTEL_RESOURCE_ATTRIBUTES via MDM** | ❌ 0 | Analytics API + 8 workspaces | **TRAP:** 8 workspaces = org restructure, extra admin overhead. OTEL_RESOURCE_ATTRIBUTES = lightweight MDM label, zero restructure. Same pattern as the "separate orgs" mistake in Block 31. |
| 3 — 3% SIEM vs Console variance | OTel is estimate; Console is authoritative; 3% variance is normal | ✅ +2 | ✅ | Correct. OTel = allocation. Provider = invoice. |

**Your recurring pattern across Blocks 31–33:** When cost or attribution is the question, you reach for the heavyweight org-restructuring answer (separate orgs, 8 workspaces) instead of the lightweight label/config answer (OTEL_RESOURCE_ATTRIBUTES, MDM). And when a stakeholder needs a dashboard, you reach for the most technical surface instead of the simplest one that answers their question.

**Memory anchor — "which surface for which stakeholder":**
- CTO / exec → Admin dashboard (simplest, inside Claude, no setup)
- Finance charge-back → OTel + MDM labels (no restructure)
- Finance reconciliation → Provider billing console (authoritative)
- Engineering teams / BI → Analytics API

---

