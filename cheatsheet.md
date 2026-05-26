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

### FAQ — concept questions from prep

#### What's an XML tag vs JSON?

XML = markup that wraps free-form text in named tags. JSON = structured data (keys/values/arrays).

```xml
<document>Raw text with "quotes" and newlines.</document>
```

```json
{"document": "Raw text with \"quotes\" and newlines."}
```

Use **XML for prompt input** (Claude reads it). Use **JSON for output** (your code parses it). XML wins for input because (a) no escaping required, (b) visually scannable, (c) Claude was heavily trained on it.

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

---

