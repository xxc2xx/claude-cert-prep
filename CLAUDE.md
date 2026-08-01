# claude-cert-prep

Personal study repo for the Anthropic Claude Builder certification (CCAR-F).
Static quiz SPA (`quiz.html`), offline build script, Markdown study notes.
No server, no PII, no external API keys.

## Rules

- Never commit secrets or `.env` files (none expected — flag if someone adds one)
- Run `python -m py_compile <file>` after any Python edit
- `offline.html` is a build artifact — regenerate via `build_offline.py`, never hand-edit
- `build_offline.py` must write atomically (temp file + rename); the assert guard must stay
- Never run `git push` without first stating the artifact + target and receiving an explicit "yes" from Winston — "everything looks good" is not a yes
- Before any dispatch: state "Artifact: X / Target: Y — correct? yes to proceed"

## Exam context

CCAR-F exam booked Sun 30 Aug 2026 2pm HKT. Candidate ID: ANTH220651.
