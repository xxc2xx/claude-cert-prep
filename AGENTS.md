# AGENTS.md — Reviewer Entry Point (claude-cert-prep)

This file is read by Codex. Your role is **reviewer only** — not implementer.
Claude implements changes guided by CLAUDE.md. You review the complete PR diff.

Shared invariants, severity definitions, and the escalation table: `~/my-agent/QUALITY.md`.
Rules in this file are additive — they extend QUALITY.md for claude-cert-prep specifically.

This is a personal cert-prep repo — static quiz SPA (`quiz.html`), offline build script,
study notes in Markdown, and a progress sync shell script.
No server, no PII, no external API keys.

---

## When you are triggered

- After any commit to `build_offline.py`, `quiz.html`, or `sync-progress.sh`
- Via `bash review.sh` locally (uses `--base main`)

---

## Review guidelines

### Output format

```
FILE: <path>
PASS | FLAG
  [if FLAG]
  RULE: <rule name>
  LINE: <line number or range>
  ISSUE: <one sentence — what is wrong>
  SEVERITY: critical | major | minor
```

Final line:
```
VERDICT: APPROVE | REQUEST_CHANGES
```

`REQUEST_CHANGES` if any critical or major finding. `APPROVE` with findings listed if minor only.

---

## Rules

### BUILD — offline.html write safety `[major]`
- `build_offline.py` must write to a temp file and rename atomically — direct `open(out_path, 'w')` risks a truncated `offline.html` if the script is interrupted mid-write
- The `assert old_script in html` guard must remain in place — removing it makes silent corruption possible
- Any new embedded resource (JS library, markdown file) must be validated non-empty before base64 encoding

### PUSH — sync-progress.sh dispatch `[major]`
- `sync-progress.sh` does `git push` — this is a dispatch action; the QC gate applies
- Flag if any new script adds `git push`, `gh`, or external upload without a comment explaining it is intentional
- `mv "$FILE" "$DEST/$BASENAME"` is irreversible — flag if the script loses the rollback path (e.g. `cp` before `mv` is preferred)

### CONTENT — study note accuracy `[minor]`
- Flag obvious factual errors in Markdown study notes only if clearly wrong (wrong model name, wrong API parameter name)
- Do not flag phrasing, formatting, or study-style choices

### CRED — credential safety `[critical]`
- No API keys, tokens, or secrets as string literals anywhere in the repo
- `.env` must not appear in the diff
- `md_to_note.py` uses AppleScript only — no auth tokens expected; flag if anyone adds one inline

---

## Key files to focus on

- `build_offline.py` — offline.html write, assert guards, embedded content pipeline
- `quiz.html` — SPA source; CDN script tag must remain (offline build patches it out)
- `sync-progress.sh` — git push dispatch; mv is irreversible
- `md_to_note.py` — AppleScript runner; no secrets expected

---

## What NOT to flag

- Code style, formatting, naming conventions
- Missing docstrings or comments
- Study note wording, question phrasing, or answer explanations
- `offline.html` itself — it is generated output; review the generator, not the artifact
- Anything marked `# approved` in a comment
