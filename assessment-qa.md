# Partner Specialization: Claude Code Assessment — Q&A Log
34 questions total. Captured as Winston works through the assessment.
Format: question → correct answer(s) → cross-ref block.

---

## Q1 (multi-select)
**A developer requests access to a new MCP server mid-activation. Which steps are part of the correct governance process?**

- A. Route the request through the standing MCP review process established at kickoff
- B. Add the server to allowedMcpServers in managed-settings.json after approval
- C. Allow the developer to install it directly — user-installed servers are self-governing
- D. Verify the server against the org-deployed allowlist before enabling access

**Correct: A, B, D**

C is the trap — user-installed MCP servers are NOT self-governing. Any new server goes through the review process first, is verified against the allowlist, then added to managed-settings.json post-approval.

Cross-ref: Block 17 (MCP governance)

---

## Q2
**A client wants all engineers to have three approved internal MCP servers available from Day 1, without each developer configuring them manually. What is the correct architecture?**

- A. Add the MCP servers to allowedMcpServers in managed-settings.json so all users can connect
- B. Add the MCP server configs to the shared .mcp.json file in the team's main repository
- C. Bundle the MCP server configs into a plugin, assign the engineering SCIM group to it via RBAC, and deploy org-wide
- D. Send each developer the configuration file and include setup steps in the onboarding doc

**Correct: C — Plugin + SCIM group + RBAC**

`allowedMcpServers` = permits access (allowlist). `.mcp.json` = repo-level config. Neither *deploys* servers to all engineers automatically. Only plugin + SCIM group assignment distributes MCP configurations org-wide without manual setup.

**Core distinction: Allowlist determines what is permitted. Plugin + RBAC determines what is delivered and to whom.**

Cross-ref: Block 17 (MCP config), Block 21 (SCIM/RBAC groups)

---

## Q3
**In Claude Code's permission model, what is the correct evaluation order?**

- A. Allow → Ask → Deny
- B. Ask → Allow → Deny
- C. Deny → Ask → Allow
- D. Allow → Deny → Ask

**Correct: C — Deny → Ask → Allow**

"Block first, challenge second, permit last." An explicit prohibition wins before Claude considers prompting or automatically allowing. Winston selected a wrong option on exam day — C was always right.

```
DENY  = prohibited, no override
ASK   = permitted only after confirmation  
ALLOW = automatically permitted
```

Cross-ref: Block 41 (Capstone L1 permissions)

---

## Q4
**A client is going live in two weeks. SSO is configured but SCIM provisioning is not ready. What is the right recommendation?**

- A. Delay go-live until SCIM is fully configured — it is required for enterprise deployments
- B. Use manual provisioning — SCIM is only necessary at large scale
- C. Proceed with JIT provisioning now, with a clear plan to migrate to SCIM before full rollout
- D. Use IP allowlisting as a temporary substitute for user provisioning

**Correct: C**

JIT (Just-in-Time) provisioning is the bridge — users are provisioned on first login via SSO without SCIM being ready. It's a legitimate interim state, not a workaround, as long as there's a clear migration plan before full rollout.

Cross-ref: Block 21 (SSO/SCIM identity)

---

## Q5
**A client asks whether enabling the "no training" opt-out means Anthropic stores nothing from their Claude Code sessions. What is the correct response?**

- A. Yes — opting out of training means Anthropic retains no session data
- B. No — no-training, custom retention, and Zero Data Retention are three separate controls with different scopes
- C. Correct, but only for Claude for Enterprise direct deployments
- D. It depends on the deployment path — Bedrock and Vertex handle retention differently

**Correct: B**

Three separate controls, three different scopes:
- **No-training opt-out**: data not used for model training
- **Custom retention**: controls how long data is stored
- **Zero Data Retention (ZDR)**: data not persisted at all (Enterprise direct only)

None of these is a superset of the others.

Cross-ref: Block 22 (data controls / ZDR / retention)

---

## Q6
**During Week 4 readout prep, a client's admin flags that three developers account for 38% of total Claude Code spend. The rest of the cohort's usage looks normal. What is the most likely explanation and the right response?**

- A. Incorrect seat types: audit and correct their assignments
- B. Using Claude Code most effectively: position them as internal champions
- C. Likely running powerful models on all tasks regardless of complexity: coach on matching model to task type
- D. Misconfigured org-level spend limit: reset and redistribute

**Correct: B**

Rest of cohort normal + high spend from a few developers = likely high usage, not misconfiguration (eliminates D). Seat types don't affect spend patterns (eliminates A). High spend from a small group with normal cohort = early adopters doing more — surface as champion candidates. C (model coaching) is valid follow-up if review confirms Opus-for-everything, but not the primary diagnosis.

Cross-ref: Block 37 (adoption curve), Block 33 (cost monitoring)

---

## Q7
**Which element of a Skill definition determines whether Claude invokes it for a given request?**

- A. The Skill's filename in the .claude/skills directory
- B. The list of allowed_tools defined in the Skill manifest
- C. The description field — it functions as the trigger
- D. The Skill's load order in the skills directory

**Correct: C**

The description field is the primary selection mechanism — same pattern as MCP tool descriptions. Claude reads descriptions to decide which skill matches a request.

Cross-ref: Block 5 (hooks vs skills), Block 15 (tool description as selection mechanism)

---

## Q8
**A client's platform team asks: "If we connect Claude Code to our internal Jira instance via MCP, does that give it access to all our project data?"**

- A. Yes — MCP provides Claude Code with read access to all data in connected systems
- B. Yes, but access can be scoped by configuring permissions on the MCP server side
- C. No — MCP creates a controlled connection where Claude can only use explicitly defined tools and resources
- D. It depends on the MCP server implementation — some are read-only, some are read-write

**Correct: C**

MCP is a controlled protocol — Claude can only use tools and resources the MCP server explicitly exposes. Connecting to Jira via MCP ≠ open access to all Jira data.

Cross-ref: Block 17 (MCP architecture)

---

## Q9 (multi-select)
**Which of the following are valid uses of hooks in an enterprise Claude Code deployment?**

- A. Blocking edits to a protected directory before they execute
- B. Overriding Claude's model selection on a per-session basis
- C. Sending a notification when a Claude Code session starts
- D. Logging all tool calls to an external audit system

**Correct: A, C, D**

B is wrong — hooks cannot change model selection. Hooks are shell middleware (PreToolUse/PostToolUse): A = PreToolUse with exit 2 blocks the action; C = session-start hook triggers a notification; D = PostToolUse logs to external system.

Cross-ref: Block 5 (hooks), Block 27 (observability)

---

## Q10
**What is the primary architectural advantage of subagents over running multiple parallel Claude Code instances?**

- A. Subagents use a lighter-weight model, reducing cost and latency
- B. Subagents share the orchestrator's full context, enabling better coordination
- C. Subagents provide context isolation — each sees only what it needs for its specific task
- D. Subagents can bypass the permission model for fully autonomous operation

**Correct: C**

Context isolation is the key property — each subagent sees only its module, so failures don't cascade. B is the opposite of correct. D is false (permissions still apply).

Cross-ref: Block 16 (subagents/parallel orchestration), Block 41 (Capstone L1)

---

## Q11
**A client team uses Claude Code for high-volume routine tasks (boilerplate, formatting) and lower-volume complex architectural refactoring. What is the correct model configuration?**

- A. Haiku for all tasks
- B. Opus for all tasks
- C. Sonnet as default, with Opus available for complex architectural tasks
- D. Haiku for routine tasks, Sonnet for complex tasks, with Opus disabled

**Correct: C**

Sonnet as default handles the broad workload efficiently. Opus available for complex architectural work ensures the ceiling is high enough. D disables Opus — wrong for genuinely complex refactoring.

Cross-ref: Block 26 (model tiers / scorecard)

---

## Q12
**When designing the pilot cohort, which factor most determines the quality of data from the pilot?**

- A. The seniority of the developers selected
- B. The size of the cohort — larger pilots produce more statistically reliable data
- C. Who is in the pilot — cohort selection determines the data you get
- D. The complexity of the use case — harder problems produce more meaningful results

**Correct: C**

Cohort selection = design decision, not availability decision. Use case owners produce attributable, defensible data. Size (B) is a distractor — a tight cohort of owners beats a broad cohort of interested observers every time.

Cross-ref: Block 35 (pilot design), Block 34 (qualification)

---

## Q13
**A client's security team wants near-real-time inspection of developer prompts and the ability to automatically delete conversations containing sensitive financial data. Which Compliance API use case does this map to?**

- A. SIEM monitoring: ingest activity feed events
- B. DLP / CASB: near-real-time prompt and response inspection with deletion capability
- C. eDiscovery and legal hold: preserve conversation content for flagged users
- D. AI security posture management: validate org configuration settings

**Correct: B**

Near-real-time inspection + deletion capability = DLP/CASB pattern. SIEM (A) = activity events not content. eDiscovery (C) = preserve, not delete. Security posture (D) = config validation.

Cross-ref: Block 27 (5-mechanism observability), Block 32 (Compliance API patterns)

---

## Q14
**A client's finance team wants to allocate Claude Code spend by business unit. Which approach makes per-team chargeback operationally possible?**

- A. Manually reviewing the admin console usage dashboard at month-end
- B. Deploying OTEL_RESOURCE_ATTRIBUTES labels per team via managed-settings.json and querying cost.usage by team label in the SIEM
- C. Using session headers in an LLM gateway to label and aggregate traffic by team
- D. Creating a separate Claude for Enterprise organisation per business unit

**Correct: B**

OTEL_RESOURCE_ATTRIBUTES deployed per team via MDM → tags every cost.usage data point with team label → SIEM groups by label = charge-back architecture. D (separate orgs) = org restructure trap. C (LLM gateway headers) = not the documented pattern.

Cross-ref: Block 33 (cost attribution), Block 31 (OTel pipeline)

---

## Q15
**A developer has set a personal preference in user-scope settings. IT has configured the same setting in managed-settings.json. Which value takes effect?**

- A. User scope — personal settings always override managed settings
- B. Most recently modified setting takes precedence
- C. Project scope — it sits between managed and user in the hierarchy
- D. Managed scope — it cannot be overridden by any user or project setting

**Correct: D**

managed-settings.json = top of the config hierarchy, cannot be overridden by anything below it.

Cross-ref: Block 41 (Capstone L1 config scope), Block 13 (deployment architecture)

---

## Q16
**In a GitHub Actions workflow, how should the Claude Code API key be managed?**

- A. Hard-coded in the workflow YAML file for reliability
- B. Stored in the repository's .env file and loaded at runtime
- C. Stored as a GitHub Actions secret and referenced via environment variable

**Correct: C** — note: Q16 had a 4th option D ("Passed as a command-line argument") not shown in original paste. Winston chose D (wrong). C is still correct.

Key in YAML = committed to version history. Key in .env = risky + not reliably available to CI runner. GitHub Actions secrets = secure, not logged, referenced as env var in the workflow step. Passing via CLI argument = logged in process list.

Cross-ref: Block 43 (Capstone L3 CI/CD auth)

---

## Q17
**Can Claude Code automatically delete files without asking the developer?**

- A. Yes — file operations are always automatically approved
- B. It depends on how delete operations are classified in the permissions model: allow, ask, or deny
- C. Only with explicit confirmation — all file operations require approval by default

**Correct: B**

Permission model is configurable: Deny → Ask → Allow. Delete operations take whatever classification is set. No blanket rule either way.

Cross-ref: Block 41 (permissions model)

---

## Q18 (multi-select)
**Which of the following are part of a clean Claude Code engagement close?**

- A. A versioned plugin with pinned MCP server dependencies, ready for the client's CoE
- B. A signed SLA covering post-engagement support and model updates
- C. A Day 30 readout delivered with the executive sponsor present
- D. A designated champion who can maintain the CLAUDE.md and onboard future developers

**Correct: A, C, D**

B (signed SLA) is not a documented engagement-close artifact. C and D are explicitly in the four clean-handoff artifacts. A (versioned plugin + pinned MCP deps) maps to the technical handoff artifact (command catalogue + MCP config) for CoE continuity.

Cross-ref: Block 39 (four artifacts), Block 44 (handoff checklist)

---

## Q19 (multi-select)
**A new enterprise deployment requires all developers to authenticate via SSO and prohibits self-installed MCP servers. Which managed-settings.json fields enforce these controls?**

- A. forceLoginMethod
- B. forceLoginOrgUUID
- C. allowedMcpServers
- D. allowManagedMcpServersOnly

**Correct: A, B, D — original prediction was correct**

| Requirement | Field |
|---|---|
| Require enterprise login method | `forceLoginMethod` |
| Force users into the correct Claude org | `forceLoginOrgUUID` |
| Prevent user-installed MCP servers | `allowManagedMcpServersOnly` |
| Define which MCP servers are approved (allowlist only) | `allowedMcpServers` — ❌ not in answer |

Key distinction: `allowedMcpServers` = what's approved. `allowManagedMcpServersOnly` = where servers must come from. Winston missed selecting the correct combination on exam day.

Cross-ref: Block 21 (SSO/SCIM), Block 17 (MCP governance), Block 13 (managed-settings.json)

---

## Q20
**On Day 28 of an activation, you are deciding what to bundle into the client's plugin. Which should NOT be included?**

- A. The team's custom slash commands built during the engagement
- B. Approved MCP server configurations with pinned version numbers
- C. A developer's personal user-scope settings
- D. The project CLAUDE.md templates built during the engagement

**Correct: C**

Personal user-scope settings are per-developer and belong in the individual's config — not in a shared plugin. A, B, D are all legitimate shared artifacts for CoE continuity.

Cross-ref: Block 38 (handoff artifacts), Block 13 (config scopes)

---

## Q21
**During an enterprise install clinic, a developer receives the error: "self-signed certificate in chain." What does this indicate?**

- A. The Claude Code installation package has a corrupted certificate
- B. The Anthropic API endpoint has a certificate misconfiguration
- C. The developer's machine certificate store needs to be updated
- D. The network proxy is performing TLS inspection — this is expected behaviour

**Correct: D**

Enterprise proxies performing TLS inspection insert their own certificate into the chain. The "self-signed certificate" error is the classic symptom — not a corrupted install, not an Anthropic issue. Fix: add the enterprise CA cert to the system trust store.

Cross-ref: Block 43 (enterprise CI proxy issues)

---

## Q22
**A developer's install command runs but hangs indefinitely with no error message. What is the most likely cause?**

- A. Installed Node.js version below minimum requirement
- B. The developer's machine is running Windows without WSL enabled
- C. A network proxy is intercepting the outbound connection
- D. The Anthropic API endpoint is temporarily unavailable

**Correct: C**

A proxy intercept that doesn't return a response (or silently drops the connection) causes an indefinite hang with no error. Node.js version issues produce specific error messages. API downtime would eventually produce a timeout error.

Cross-ref: Block 43 (proxy failure pattern)

---

## Q23
**During Week 2, a developer has been stuck on the same Claude Code task for 45 minutes with no visible progress. What is the right response?**

- A. Intervene immediately — 45 minutes without progress signals a tool limitation
- B. Let them work through it — this is within the expected supervised-to-agentic progression
- C. Assess whether the task is within appropriate scope for their current skill level, then decide
- D. Escalate to the client's champion — this is a change management issue, not a technical one

**Correct: C**

Same intervention test from Capstone L2: assess first (iterating vs looping?), then decide. 45 minutes alone isn't enough — the question is whether each attempt is exploring something different (iterate → wait) or repeating the same failure (loop → intervene). Champion handles post-engagement issues, not Week 2 active coaching.

Cross-ref: Block 42 (Capstone L2 iterating vs looping)

---

## Q24
**What is the minimum required structure for a functional custom slash command in Claude Code?**

- A. A Python script with a defined entry point and a manifest.json file
- B. A Markdown file with YAML frontmatter
- C. A TypeScript module exported from the .claude/commands directory
- D. A JSON configuration file referencing an existing shell script

**Correct: B**

Custom commands live in `.claude/commands/` as Markdown files with YAML frontmatter (name, description, and the command body). No Python, TypeScript, or JSON config required.

Cross-ref: Block 5 (skills / custom commands)

---

## Q25 (multi-select)
**Which of the following belong in a project-level CLAUDE.md?**

- A. The team's preferred testing framework and naming conventions
- B. A developer's personal API key
- C. Architecture decisions and constraints specific to this codebase
- D. Context Claude would otherwise need to be re-explained every session

**Correct: A, C, D**

B is wrong — API keys must never go in CLAUDE.md (or anywhere committed to a repo). A, C, D are exactly the content CLAUDE.md is designed to hold: team conventions, architectural context, and recurring context Claude shouldn't have to re-derive each session.

Cross-ref: Block 38 (CLAUDE.md as living artifact), Block 41 (project CLAUDE.md fields)

---

## Q26
**A proposed use case produces real efficiency gains (faster boilerplate, fewer copy-paste errors) but the numbers don't hold up in a CIO readout. How should you handle it?**

- A. Build the pilot around it — small wins build internal momentum
- B. Reject it outright — it does not meet the structural gain threshold
- C. Use it as a supporting example within a pilot anchored to a structurally significant use case
- D. Escalate to the Anthropic AE to assess whether the use case qualifies

**Correct: C**

Marginal gains are real but not CIO-defensible on their own. The right move is to bundle them as supporting evidence in a pilot anchored to a structural use case. "Reject outright" (B) throws away legitimate adoption momentum. The AE doesn't qualify use cases — that's the consultant's job.

Cross-ref: Block 34 (structural vs marginal gain), Block 36 (ROI measurement)

---

## Q27
**A client's security team asks: "Is it accurate to say Claude Code is sandboxed?" What is the most defensible response?**

- A. Yes — Claude Code runs in an isolated sandbox that prevents all unauthorised filesystem access by default
- B. No — Claude Code has full filesystem access like any terminal application
- C. Sandboxing is layered: isolation depends on configuration in settings.json and whether the deployment uses dev containers ← **CORRECT**
- D. Yes, but only on macOS — Linux and Windows require additional configuration

**Correct: C — Sandboxing is layered**

The precise enterprise answer: sandboxing is not binary. Context isolation ≠ execution sandbox. Permission model controls which actions Claude will take. Dev containers provide stronger OS-level boundary. Winston selected wrong option on exam day — C was always right.

```
Context isolation   = what information an agent sees
Permission model    = which actions are allow/ask/deny
Sandbox             = what the process can technically reach
Dev container       = stronger operating-environment boundary
```

Cross-ref: Block 41 (permissions model), Block 13 (dev containers / deployment architecture)

---

## Q28 ⚠️ EXAM WRONG
**A client needs per-team cost chargeback across a 600-developer Claude Code deployment. Which infrastructure component makes this operationally possible?**

- A. The Claude for Enterprise admin console's built-in usage dashboard
- B. An LLM gateway configured with session headers that label traffic by team ← **CORRECT**
- C. A network proxy with TLS inspection and centralised logging
- D. The OpenTelemetry pipeline's per-user token metrics ← we predicted this — WRONG

**Correct: B — LLM gateway with session headers**

At 600-developer scale, an LLM gateway routing all Claude Code traffic is the operationally practical charge-back architecture: session headers label traffic by team → gateway aggregates by label → finance gets per-team totals. OTel "per-user token metrics" (D) is not the mechanism for per-TEAM chargeback — that's `cost.usage` with `OTEL_RESOURCE_ATTRIBUTES`, which wasn't offered cleanly in any option.

Note: This conflicts with the course content in Block 33 which describes OTel + OTEL_RESOURCE_ATTRIBUTES as the charge-back mechanism. At 600 developers, the LLM gateway is the more operationally robust pattern. Treat gateway + session headers as the SCALE answer.

Cross-ref: Block 33 (cost attribution), Block 13 (LLM gateway)

---

## Q29
**A client wants the data engineering team to access three approved internal database connectors, while keeping those connectors unavailable to all other developers. What is the correct approach?**

- A. Add connectors to allowedMcpServers for all users, then create a deny rule for non-engineering roles
- B. Bundle the connectors in a plugin, assign the data engineering group via RBAC, and leave it out of the org-wide deployment
- C. Configure connector consent to require Owner approval for each data engineering team member individually
- D. Set allowManagedMcpServersOnly to true and list only the data engineering connectors

**Correct: B**

Plugin + RBAC group assignment = correct pattern for team-scoped MCP access. A (allowlist all + deny rule) isn't how MCP governance works. C (individual Owner approval) doesn't scale. D (`allowManagedMcpServersOnly` with restricted list) would give those connectors to everyone.

Cross-ref: Block 17 (MCP governance), Block 21 (RBAC/SCIM groups)

---

## Q30
**A client has signed with Amazon Bedrock. Three weeks before kickoff, their security team asks about a feature that exists only on Enterprise direct. What is the correct response?**

- A. Escalate to the Anthropic AE immediately to explore switching deployment paths
- B. Document the gap in a one-page gap memo and address it before kickoff — not after
- C. Reassure the client the feature is on the roadmap and proceed with kickoff
- D. Recommend a phased deployment starting on Bedrock with a migration plan for later

**Correct: B**

Three weeks before kickoff is the right window to surface and address a deployment path gap. Document it in a gap memo and resolve it before the engagement starts — not during. C (roadmap promise) = misleading. A (immediate escalation to switch paths) = premature. D (phased migration) = defers the problem.

Cross-ref: Block 13 (deployment paths / feature matrix)

---

## Q31
**A client has an existing Microsoft Azure MACC (Azure Consumption Commitment) they want to leverage for this Claude Code deployment. Which deployment path should you recommend?**

- A. Claude for Enterprise direct — most feature-complete
- B. Amazon Bedrock — most widely deployed enterprise path
- C. Google Vertex AI — best compliance and data residency controls
- D. Microsoft Foundry — routes through their existing Azure commitment

**Correct: D**

Microsoft Foundry routes Claude usage through Azure, allowing the client to consume it against their existing MACC. This is the commercial lever — the client has already committed Azure spend, so Foundry is the right path to leverage it.

Cross-ref: Block 13 (deployment paths)

---

## Q32
**A client's admin has drafted: "Always respond in formal English, use bullet points for all lists, and limit responses to 300 words unless asked for more." What is the most accurate assessment?**

- A. Appropriate: it sets a consistent output standard across the org
- B. Appropriate for tone, but word limits belong in managed-settings.json
- C. Inappropriate: these are output preferences that will hamstring legitimate use cases; org instructions should set policy, not constrain how Claude responds
- D. Appropriate only if deployed via claudeMd rather than the admin console

**Correct: C**

Org instructions should set policy (what Claude should/shouldn't do, what context it operates in) — not dictate output format. A 300-word cap breaks any legitimate long-form task. Formatting preferences are user or project level, not org policy.

Cross-ref: Block 25 (org instructions / admin console)

---

## Q33
**What makes the baseline measurement window the most important data collection moment in the engagement?**

- A. It determines which developers are included in the pilot cohort
- B. Without pre-pilot data, there is no denominator for the ROI calculation
- C. It establishes the success criteria that must be agreed before kickoff
- D. It identifies which use cases are structurally significant vs. incremental

**Correct: B**

No baseline = no before state = no before/after comparison = no ROI calculation. The denominator is the baseline. This is why baseline capture is pre-work, not post-work.

Cross-ref: Block 36 (baseline capture), Block 35 (pilot design)

---

## Q34
**A client's legal team requires Zero Data Retention (ZDR) for all Claude Code inference. Which deployment path supports this?**

- A. Amazon Bedrock
- B. Google Vertex AI
- C. Claude for Enterprise direct
- D. All three cloud-native paths support ZDR

**Correct: C**

ZDR is available only on Claude for Enterprise direct. Bedrock and Vertex have their own data handling governed by AWS/GCP, but ZDR as an Anthropic control is Enterprise-direct-only.

Cross-ref: Block 22 (ZDR / data controls), Block 13 (deployment paths)

---

## Summary — All 34 Questions

| Q | Answer | Topic |
|---|---|---|
| 1 | A, B, D | MCP governance (multi) — standing review process applies throughout, not just at kickoff |
| 2 | C ⚠️ | Plugin + SCIM + RBAC — allowlist ≠ deployment |
| 3 | C (Deny→Ask→Allow) | Permission model — deny first |
| 4 | C | JIT provisioning (SSO without SCIM) |
| 5 | B | ZDR / no-training / retention — 3 separate controls |
| 6 | B | High spend = champion candidates |
| 7 | C | Skill description = invocation trigger |
| 8 | C | MCP = controlled, explicitly scoped |
| 9 | A, C, D | Valid hook uses (multi) |
| 10 | C | Subagent context isolation |
| 11 | C | Sonnet default + Opus for complex |
| 12 | C | Cohort selection determines data quality |
| 13 | B | DLP/CASB — near-real-time + deletion |
| 14 | B | OTEL_RESOURCE_ATTRIBUTES charge-back |
| 15 | D | managed-settings.json = highest priority |
| 16 | C | API key → GitHub Actions secret |
| 17 | B | Delete permissions = configurable, not fixed |
| 18 | A, C, D | Clean engagement close (multi) |
| 19 | A, B, D | forceLoginMethod + forceLoginOrgUUID + allowManagedMcpServersOnly |
| 20 | C | Personal user-scope NOT in plugin |
| 21 | D | self-signed cert = TLS inspection by proxy |
| 22 | C | Hang with no error = proxy intercept |
| 23 | C | Assess scope, then intervene |
| 24 | B | Slash command = Markdown + YAML frontmatter |
| 25 | A, C, D | Project CLAUDE.md contents (multi) |
| 26 | C | Marginal use case = supporting example only |
| 27 | C | Sandboxing is layered — depends on config + dev containers |
| 28 | B ⚠️ | LLM gateway + session headers at 600-dev scale |
| 29 | B | Plugin + RBAC for team-scoped MCP |
| 30 | B | Gap memo before kickoff |
| 31 | D | Microsoft Foundry for Azure MACC |
| 32 | C | Org instructions = policy, not output constraints |
| 33 | B | Baseline = denominator for ROI calculation |
| 34 | C | ZDR = Enterprise direct only |

