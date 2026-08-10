#!/bin/bash
# review.sh — run after hard gates pass, before requesting Winston approval.
# Thin wrapper: all review logic lives in the shared script, so this can't
# drift from the git pre-push hook or the /dispatch code-domain pre-flight
# the way the old inline copy did (it used `origin/$BRANCH` as BASE, which
# silently skips review with no upstream — fixed 2026-08-09).
#
# Usage: bash review.sh [--force]
# Prerequisite: codex login (done once)

exec "$HOME/busy-brain/claude-config/hooks/codex-review-run.sh" "$(cd "$(dirname "$0")" && pwd)" "$@"
