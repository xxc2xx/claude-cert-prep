# Claude Builder Cert — Cheatsheet

Started 2026-05-24. Built up live during prep sessions. Companion quiz at `quiz.html`.

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

---

