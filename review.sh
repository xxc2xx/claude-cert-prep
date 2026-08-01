#!/bin/bash
# review.sh — run after hard gates pass, before requesting Winston approval.
# Writes raw Codex findings to reports/. Claude reads them and writes disposition separately.
# Winston receives: PR diff + raw Codex report + Claude's disposition.
#
# Usage: bash review.sh
# Prerequisite: codex login (done once)

set -e

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
REPORTS="$REPO_ROOT/reports"
STAMP=$(date +%Y%m%d-%H%M)
REVIEW_OUT="$REPORTS/codex-review-${STAMP}.md"

mkdir -p "$REPORTS"

echo "→ Running Codex review (full branch diff vs main)..."
echo "  Output: $REVIEW_OUT"
echo ""

codex review --base main > "$REVIEW_OUT" 2>&1

echo "  ✓ Raw findings written."
echo ""
echo "── What Winston will see ─────────────────────────────"
echo "  1. PR diff on GitHub"
echo "  2. Raw Codex report: $REVIEW_OUT"
echo "  3. Claude's disposition: $REPORTS/disposition-${STAMP}.md"
echo "     (Claude fills this in after reading the report)"
echo "─────────────────────────────────────────────────────"
echo ""
grep "VERDICT:" "$REVIEW_OUT" || echo "  (VERDICT line not found — check output)"
