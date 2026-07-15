# CCAR-F Official Exam Guide (Anthropic, v1.0)

**Source**: `official_exam_guide_v1.0.pdf` — downloaded directly from Anthropic's partner S3 (`everpath-course-content.s3-accelerate.amazonaws.com`, path `/instructor/6nizmqk8tpzpfjvt6qmmav7rh/public/1783542750/Claude+Certified+Architect+–+Foundations+Exam+Guide.pdf`).
**Version**: 1.0 · Effective July 2026 · **This is the authoritative reference — every exam item is written against these objectives.**

---

## 1 · Exam Details

| Field | Value |
|---|---|
| Credential | Claude Certified Architect – Foundations |
| Exam code | **CCAR-F** |
| # items | **60** |
| Item format | **Multiple-choice AND multiple-response**; each item states how many responses to select |
| Structure | **4 scenarios drawn from a bank of 6** |
| Time limit | 120 minutes |
| Delivery | Online proctored OR Pearson VUE test center |
| Passing score | **720 / 1000** (scaled) |
| Fee | $125 USD |
| Validity | 12 months from award date |
| Result reporting | Pass/Fail + scaled score + **percent-correct by domain** |
| Retake waiting | 14 days after 1st fail, 30 after 2nd, 90 after 3rd. Max 4 attempts / 12 months |
| Renewal | Free non-proctored assessment on Partner Academy; if lapsed → full re-take |

**⚠️ Multi-response items**: some items require selecting more than one correct answer. Each item states how many. Your quiz UI currently supports single-select only.

---

## 2 · Blueprint (Domain Weights)

| Domain | Weight |
|---|---|
| **D1** Agentic Architecture & Orchestration | **27%** |
| **D2** Tool Design & MCP Integration | **18%** |
| **D3** Claude Code Configuration & Workflows | **20%** |
| **D4** Prompt Engineering & Structured Output | **20%** |
| **D5** Context Management & Reliability | **15%** |

**Total: 100%.** D1+D3 = 47%. Focus study weight accordingly.

---

## 3 · The 6 Scenarios (4 drawn at random)

Each scenario is a realistic production context that frames its questions.

### Scenario 1: Customer Support Resolution Agent
Building a customer-support agent with the Claude Agent SDK. High-ambiguity requests (returns, billing disputes, account issues). Backend tools: `get_customer`, `lookup_order`, `process_refund`, `escalate_to_human`. Target: 80%+ first-contact resolution.
**Primary domains**: D1 · D2 · D5

### Scenario 2: Code Generation with Claude Code
Using Claude Code for code generation, refactoring, debugging, documentation. Integrating into the dev workflow via custom slash commands, CLAUDE.md configurations, plan mode vs direct execution.
**Primary domains**: D3 · D5

### Scenario 3: Multi-Agent Research System
Multi-agent research system with Claude Agent SDK. Coordinator delegates to specialised subagents (web search / document analysis / synthesis / report generation) to produce cited reports.
**Primary domains**: D1 · D2 · D5

### Scenario 4: Developer Productivity with Claude
Developer-productivity tools with Claude Agent SDK. Engineers explore unfamiliar codebases, understand legacy systems, generate boilerplate, automate repetitive tasks. Uses built-in tools (Read, Write, Bash, Grep, Glob) + MCP servers.
**Primary domains**: D2 · D3 · D1

### Scenario 5: Claude Code for Continuous Integration
Integrating Claude Code into CI/CD pipelines. Automated code reviews, test generation, PR feedback. Design prompts that provide actionable feedback and minimize false positives.
**Primary domains**: D3 · D4

### Scenario 6: Structured Data Extraction
Structured data extraction from unstructured documents. JSON-schema validation. Edge cases handled gracefully. Downstream system integration.
**Primary domains**: D4 · D5

---

## 4 · Domain Objectives (Task Statements)

Every exam item is written against one of these task statements. This is the single most authoritative study reference.

### Domain 1: Agentic Architecture & Orchestration (27%)

**1.1 Design and implement agentic loops for autonomous task execution**
- Agentic loop lifecycle: send → inspect `stop_reason` (`tool_use` vs `end_turn`) → execute tools → return results for next iteration
- Tool results appended to conversation history for model reasoning
- Model-driven decision-making vs pre-configured decision trees
- **Anti-patterns**: parsing natural-language signals for termination · arbitrary iteration caps as primary stop · checking assistant text for completion

**1.2 Orchestrate multi-agent systems with coordinator-subagent patterns**
- **Hub-and-spoke**: coordinator manages ALL inter-subagent communication, error handling, information routing
- Subagents operate with **isolated context** — do NOT inherit coordinator's conversation history automatically
- Coordinator role: task decomposition, delegation, result aggregation, dynamic subagent selection based on query complexity
- Risk: overly narrow task decomposition → incomplete coverage
- Iterative refinement loops: coordinator evaluates synthesis for gaps, re-delegates targeted queries

**1.3 Configure subagent invocation, context passing, and spawning**
- **Task tool** = mechanism to spawn subagents. `allowedTools` must include `"Task"` for coordinator to invoke.
- Subagent context must be **explicitly** provided in the prompt (no automatic inheritance)
- AgentDefinition config: descriptions, system prompts, tool restrictions
- **Fork-based session management** for divergent exploration
- **Parallel spawning** = multiple Task tool calls in ONE coordinator response (not across turns)
- Structured data formats to separate content from metadata (source URLs, doc names, page numbers)

**1.4 Multi-step workflows with enforcement and handoff patterns**
- **Programmatic enforcement** (hooks, prerequisite gates) vs prompt-based guidance
- When deterministic compliance required (identity verification before financial ops) → prompt alone has non-zero failure rate → use code
- Programmatic prerequisites blocking downstream calls (e.g. `process_refund` blocked until `get_customer` returns verified ID)
- Structured handoff summaries (customer ID, root cause, refund amount, recommended action) for human escalation

**1.5 Agent SDK hooks for tool call interception and data normalization**
- **PostToolUse** hooks intercept tool results before model processes them (normalize timestamps, formats)
- Hooks intercepting outgoing tool calls enforce compliance (block refunds > threshold)
- **Deterministic guarantees** via hooks vs **probabilistic compliance** via prompts

**1.6 Task decomposition strategies for complex workflows**
- **Fixed sequential pipelines (prompt chaining)** for predictable multi-aspect reviews
- **Dynamic adaptive decomposition** for open-ended investigation based on intermediate findings
- Split large code reviews: per-file local analysis + separate cross-file integration pass (avoid attention dilution)

**1.7 Manage session state, resumption, and forking**
- `--resume <session-name>` for named session resumption
- **`fork_session`** for independent branches from shared analysis baseline
- Inform agent about file changes when resuming after code modifications
- New session with structured summary > resuming with stale tool results

---

### Domain 2: Tool Design & MCP Integration (18%)

**2.1 Design effective tool interfaces with clear descriptions and boundaries**
- Tool descriptions = **primary mechanism** LLMs use for tool selection
- Include: input formats, example queries, edge cases, boundary explanations
- Ambiguous/overlapping descriptions → misrouting (`analyze_content` vs `analyze_document`)
- Split generic tools into purpose-specific (`analyze_document` → `extract_data_points`, `summarize_content`, `verify_claim_against_source`)
- Keyword-sensitive system-prompt wording can override well-written tool descriptions

**2.2 Structured error responses for MCP tools**
- **`isError` flag** for communicating tool failures back to agent
- Error categories: transient (timeout, unavailable) · validation (invalid input) · business (policy violation) · permission
- Structured metadata: `errorCategory`, `isRetryable` boolean, human-readable descriptions
- `retriable: false` flags + customer-friendly explanations for business rule violations
- Local recovery within subagents for transient failures; propagate only unresolvable errors + partial results
- **Access failures vs valid empty results** — distinguish these; they require opposite responses

**2.3 Distribute tools appropriately across agents and configure tool choice**
- Too many tools (18 vs 4-5) → degrades tool selection reliability
- Agents with off-specialization tools misuse them (synthesis agent doing web searches)
- **tool_choice** options: `"auto"` (may return text or tool) · `"any"` (must call some tool) · `{"type": "tool", "name": "..."}` (forced specific tool)
- Scoped cross-role tools for high-frequency needs (`verify_fact` on synthesis agent)

**2.4 Integrate MCP servers into Claude Code and agent workflows**
- **Project-level** `.mcp.json` (shared team tooling) vs **user-level** `~/.claude.json` (personal/experimental)
- Environment variable expansion in `.mcp.json` (`${GITHUB_TOKEN}`) — never commit secrets
- All configured MCP tools discovered at connection time, available simultaneously
- **MCP Resources** expose content catalogs (issue summaries, doc hierarchies, schemas) → reduce exploratory tool calls
- Prefer community MCP servers over custom for standard integrations (Jira)

**2.5 Select and apply built-in tools effectively**
- **Grep** — content search (function names, error messages, imports)
- **Glob** — file path patterns (`**/*.test.tsx`)
- **Read/Write** — full file operations · **Edit** — targeted modifications via unique text match
- When Edit fails (non-unique match) → **Read + Write fallback**
- Build codebase understanding incrementally: Grep → find entry points → Read to follow imports

---

### Domain 3: Claude Code Configuration & Workflows (20%)

**3.1 Configure CLAUDE.md files with hierarchy, scoping, modular organization**
- **Hierarchy**: user-level (`~/.claude/CLAUDE.md`) · project-level (`.claude/CLAUDE.md` or root `CLAUDE.md`) · directory-level (subdirectory `CLAUDE.md`)
- User-level = personal; **NOT shared with teammates via version control**
- **`@import`** syntax for modular external file references
- **`.claude/rules/`** directory for topic-specific rule files (alternative to monolithic CLAUDE.md)
- **`/memory`** command verifies which memory files are loaded

**3.2 Custom slash commands and skills**
- Project commands: `.claude/commands/` (shared, version-controlled) · User commands: `~/.claude/commands/`
- **Skills** in `.claude/skills/` with `SKILL.md` frontmatter supporting: `context: fork`, `allowed-tools`, `argument-hint`
- **`context: fork`** → skill runs in isolated sub-agent context; verbose output doesn't pollute main conversation
- `allowed-tools` in frontmatter restricts tool access during skill execution
- `argument-hint` prompts for required parameters
- Skills = on-demand for task-specific · CLAUDE.md = always-loaded universal standards

**3.3 Apply path-specific rules for conditional convention loading**
- `.claude/rules/` files with YAML frontmatter `paths:` glob patterns
- Load ONLY when editing matching files → reduces irrelevant context, saves tokens
- Advantage over subdirectory CLAUDE.md: conventions that span directories (e.g. all test files anywhere)
- Example: `paths: ["**/*.test.tsx"]` for test conventions regardless of location

**3.4 Plan mode vs direct execution**
- **Plan mode**: complex tasks · large-scale changes · multiple valid approaches · architectural decisions · multi-file modifications
- **Direct execution**: simple, well-scoped changes (single validation check, single-file bug fix with clear stack trace)
- **Explore subagent** for verbose discovery phases — isolates verbose output, returns summary
- Combine: plan mode for investigation + direct execution for implementation

**3.5 Iterative refinement techniques**
- Concrete input/output examples > prose descriptions
- Test-driven iteration: write tests first, iterate by sharing failures
- **Interview pattern**: have Claude ask questions to surface considerations before implementing
- All-at-once (interacting problems) vs sequential (independent problems) — pick right based on issue interaction

**3.6 Integrate Claude Code into CI/CD pipelines**
- **`-p`** (or `--print`) flag for non-interactive mode (prevents hangs)
- **`--output-format json`** + **`--json-schema`** for structured CI output
- CLAUDE.md carries project context (testing standards, fixtures, review criteria) to CI-invoked Claude Code
- **Session context isolation**: same session that generated code is less effective at reviewing its own changes (self-review bias) → use independent review instance

---

### Domain 4: Prompt Engineering & Structured Output (20%)

**4.1 Explicit criteria for precision, reducing false positives**
- Explicit criteria ("flag only when claimed behavior contradicts actual code") > vague instructions ("check that comments are accurate")
- General instructions ("be conservative", "high-confidence findings only") fail to improve precision
- **High false-positive categories undermine trust in accurate categories** — temporarily disable them while improving

**4.2 Few-shot prompting**
- Few-shot examples > detailed instructions alone for consistent formatted output
- **2-4 targeted examples** for ambiguous scenarios showing reasoning for choice over plausible alternatives
- Enable generalization to novel patterns (not just matching prespecified cases)
- Effective for reducing hallucination in extraction with varied document structures

**4.3 Enforce structured output using tool use and JSON schemas**
- **`tool_use` with JSON schemas** = most reliable structured output; eliminates syntax errors
- `tool_choice`: `"auto"` (may return text) · `"any"` (must call some tool) · forced (must call specific named tool)
- Strict JSON schemas eliminate SYNTAX errors — do NOT prevent SEMANTIC errors (line items not summing to total)
- **Nullable fields** for information that may be absent → prevents fabrication
- Enum patterns: add `"unclear"` for ambiguous, `"other"` + detail for extensible categorization

**4.4 Validation, retry, feedback loops**
- **Retry-with-error-feedback**: append specific validation errors to prompt on retry
- Retry ineffective when info is genuinely absent from source (vs format/structural errors)
- `detected_pattern` field for tracking dismissal patterns
- Self-correction: extract `calculated_total` alongside `stated_total`; add `conflict_detected` booleans

**4.5 Batch processing strategies (Message Batches API)**
- **50% cost savings**, up to **24-hour** processing window, **no latency SLA**
- Appropriate: non-blocking, latency-tolerant (overnight reports, weekly audits, nightly test gen)
- Inappropriate: blocking workflows (pre-merge checks)
- **Does NOT support multi-turn tool calling** within a single request
- **`custom_id`** for correlating request/response pairs
- Batch submission math: if SLA = 30h, use 4-6h windows (interval + 24h ≤ 30h)
- Refine prompts on sample set BEFORE batch-processing large volumes

**4.6 Multi-instance and multi-pass review architectures**
- Self-review limitations: model retains reasoning context → won't question its own decisions in same session
- **Independent review instances** catch subtle issues > self-review instructions or extended thinking
- **Multi-pass**: per-file local passes + separate cross-file integration pass (avoids attention dilution + contradictory findings)

---

### Domain 5: Context Management & Reliability (15%)

**5.1 Manage conversation context to preserve critical information**
- **Progressive summarization risk**: condenses numerical values, percentages, dates, customer-stated expectations into vague summaries
- **Lost-in-the-middle**: models process beginning and end reliably; middle sections may be omitted
- Tool results accumulate disproportionately to relevance (40+ fields per order lookup, only 5 relevant)
- Extract transactional facts (amounts, dates, order#, statuses) into a **persistent "case facts" block** included in each prompt, OUTSIDE summarized history
- Trim verbose tool outputs to relevant fields BEFORE they accumulate
- Place key findings summaries at BEGINNING of aggregated inputs (mitigate position effects)

**5.2 Escalation and ambiguity resolution patterns**
- **Escalation triggers**: customer requests human · policy exceptions/gaps (not just complex cases) · inability to progress
- Explicit customer demand → escalate IMMEDIATELY without investigation
- Sentiment-based escalation + self-reported confidence = UNRELIABLE proxies for complexity
- Multiple customer matches → request additional identifiers (NOT heuristic selection)
- Add explicit escalation criteria + few-shot examples

**5.3 Error propagation across multi-agent systems**
- **Structured error context** (failure type, attempted query, partial results, alternatives) enables intelligent coordinator recovery
- **Access failures** (retry decisions needed) ≠ **valid empty results** (successful query, no matches)
- Generic error statuses ("search unavailable") hide context
- Anti-patterns: silently suppressing errors as success · terminating entire workflow on single failure
- Synthesis output with **coverage annotations** for topic areas with gaps

**5.4 Context management in large codebase exploration**
- Context degradation → model references "typical patterns" instead of specific classes discovered earlier
- **Scratchpad files** persist key findings across context boundaries
- Subagent delegation isolates verbose exploration output
- **Crash recovery** via structured state exports (manifests) coordinator loads on resume
- **`/compact`** reduces context usage in extended sessions

**5.5 Human review workflows and confidence calibration**
- Aggregate accuracy (97% overall) may mask poor performance on specific doc types/fields
- **Stratified random sampling** for measuring error rates in high-confidence extractions
- Field-level confidence scores calibrated with labeled validation sets
- Validate accuracy by doc type + field segment BEFORE automating high-confidence extractions

**5.6 Preserve information provenance in multi-source synthesis**
- Source attribution lost during summarization when findings compressed without claim-source mappings
- Require subagents to output **structured claim-source mappings** (URLs, doc names, excerpts) preserved through synthesis
- Conflicting statistics from credible sources: **annotate the conflict** with source attribution — never arbitrarily pick one value
- Temporal data: require publication/collection dates in structured outputs
- Render content types appropriately: financial → tables · news → prose · technical findings → structured lists (not everything uniform)

---

## 5 · Appendix — In-Scope Topics (explicitly tested)

- Agentic loop implementation: control flow based on `stop_reason`, tool result handling, loop termination
- Multi-agent orchestration: coordinator-subagent, task decomposition, parallel subagent execution, iterative refinement
- Subagent context management: explicit context passing, structured state persistence, crash recovery manifests
- Tool interface design: effective descriptions, splitting vs consolidating tools, tool naming to reduce ambiguity
- MCP tool and resource design: resources for content catalogs, tools for actions, description quality
- MCP server config: project vs user scope, env-var expansion, multi-server simultaneous access
- Error handling and propagation: structured error responses, error categories, local recovery before escalation
- Escalation decision-making: explicit criteria, customer preferences, policy gap identification
- CLAUDE.md configuration: hierarchy, `@import`, `.claude/rules/` with glob patterns
- Custom commands and skills: project vs user scope, `context: fork`, `allowed-tools`, `argument-hint`
- Plan mode vs direct execution: complexity assessment, architectural decisions
- Iterative refinement: I/O examples, test-driven iteration, interview pattern
- Structured output via `tool_use`: schema design, `tool_choice`, nullable fields to prevent hallucination
- Few-shot prompting: ambiguous scenarios, format consistency, false-positive reduction
- Batch processing: Message Batches API, latency tolerance, `custom_id` handling
- Context window optimization: trim verbose outputs, structured fact extraction, position-aware ordering
- Human review workflows: confidence calibration, stratified sampling, accuracy segmentation
- Information provenance: claim-source mappings, temporal data, conflict annotation, coverage gaps

## 6 · Appendix — Out-of-Scope Topics (NOT on exam)

- Fine-tuning Claude models or training custom models
- Claude API authentication, billing, account management
- Specific programming languages/frameworks beyond what's needed for tool/schema config
- Deploying/hosting MCP servers (infrastructure, networking, container orchestration)
- Claude's internal architecture, training process, model weights
- Constitutional AI, RLHF, safety training methodologies
- Embedding models, vector database implementation details
- Computer use (browser automation, desktop interaction)
- Vision/image analysis capabilities
- Streaming API / server-sent events
- Rate limiting, quotas, API pricing calculations
- OAuth, API key rotation, authentication protocol details
- Specific cloud provider configs (AWS, GCP, Azure)
- Performance benchmarking, model comparison metrics
- Prompt caching implementation details (beyond knowing it exists)
- Token counting algorithms, tokenization specifics

## 7 · Appendix — Technologies and Concepts

- **Claude Agent SDK** — agent definitions, agentic loops, `stop_reason` handling, hooks (PostToolUse, tool call interception), subagent spawning via Task tool, `allowedTools` config
- **Model Context Protocol (MCP)** — MCP servers, tools, resources, `isError` flag, tool descriptions, tool distribution, `.mcp.json` config, env-var expansion
- **Claude Code** — CLAUDE.md hierarchy (user/project/directory), `.claude/rules/` YAML frontmatter path-scoping, `.claude/commands/`, `.claude/skills/` with SKILL.md frontmatter (`context: fork`, `allowed-tools`, `argument-hint`), plan mode, direct execution, `/memory`, `/compact`, `--resume`, `fork_session`, Explore subagent
- **Claude Code CLI** — `-p` / `--print` flag for non-interactive, `--output-format json`, `--json-schema` for structured CI output
- **Claude API** — `tool_use` with JSON schemas, `tool_choice` options (`auto`/`any`/forced), `stop_reason` values (`tool_use`, `end_turn`), `max_tokens`, system prompts
- **Message Batches API** — 50% cost savings, up to 24h processing window, `custom_id` for correlation, polling for completion, **no multi-turn tool calling support**
- **JSON Schema** — required vs optional fields, enum types, nullable fields, `"other"` + detail string patterns, strict mode
- **Pydantic** — schema validation, semantic validation errors, validation-retry loops
- **Built-in tools** — Read, Write, Edit, Bash, Grep, Glob (purposes + selection criteria)
- **Few-shot prompting** — targeted examples for ambiguous scenarios, format demonstration, generalization
- **Prompt chaining** — sequential task decomposition into focused passes
- **Context window management** — token budgets, progressive summarization, lost-in-the-middle, context extraction, scratchpad files
- **Session management** — session resumption, `fork_session`, named sessions, session context isolation
- **Confidence scoring** — field-level, calibration with labeled validation sets, stratified sampling for error rates

---

## 8 · How to Prepare (Anthropic's Own Recommendation)

- Build an agent with Claude Agent SDK: full agentic loop with tool calling, error handling, session mgmt. Practice spawning subagents and passing context.
- Configure Claude Code for a real project: CLAUDE.md hierarchy, path-specific `.claude/rules/`, skills with `context: fork` + `allowed-tools`, at least one MCP server.
- Design and test MCP tools: differentiating descriptions, structured error responses (categories + retryable flags), test with ambiguous requests.
- Build a structured extraction pipeline: `tool_use` + JSON schemas, validation-retry loops, nullable schemas, batch processing.
- Practice prompt engineering: few-shot for ambiguous, explicit review criteria, multi-pass review architectures.
- Study context management: extracting structured facts, scratchpad files, subagent delegation for context limits.
- Escalation and human-in-the-loop: when to escalate (policy gaps, customer requests, no progress), confidence-based routing.

## 9 · Preparation Exercises (Anthropic's four suggested)

1. **Build a Multi-Tool Agent with Escalation Logic** — 3-4 MCP tools with clear descriptions, agentic loop, structured errors, programmatic hook enforcing business rule. **Reinforces**: D1, D2, D5.
2. **Configure Claude Code for a Team Dev Workflow** — CLAUDE.md hierarchy, `.claude/rules/` glob patterns, skill with `context: fork` + `allowed-tools`, MCP server with env-vars, test plan mode vs direct on varying complexity. **Reinforces**: D3, D2.
3. **Build a Structured Data Extraction Pipeline** — extraction tool with JSON schema (required/optional/nullable, enum with "other"), validation-retry loop, few-shot with varied doc formats, Batch API for 100 docs, field-level confidence + human-review routing. **Reinforces**: D4, D5.
4. **Design and Debug a Multi-Agent Research Pipeline** — coordinator + 2+ subagents, parallel Task calls in single response, structured claim-source metadata, simulated timeout → structured error context, conflicting sources → preserve both with attribution. **Reinforces**: D1, D2, D5.

---

## 10 · Exam-Day Rules (highlights)

- Valid, unexpired, gov-issued photo ID; name must match registration exactly (contact `certifications-support@anthropic.com` to correct)
- Online proctor or Pearson VUE test center
- Prohibited: mobile phones, smart watches, headphones, study materials, recording devices, secondary monitors
- No communication with anyone during exam; no capture/copy/photo of exam content
- Non-disclosure agreement accepted before exam begins
- Cheating/disclosure → invalidated result, revoked credential, banned from future exams
