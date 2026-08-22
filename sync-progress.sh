#!/usr/bin/env bash
# Moves the latest progress export from Downloads into the repo, stages any
# new/modified screenshots, shows what's about to go out, and pushes after
# explicit confirmation.
# Run after clicking "Export progress JSON" in the Progress tab.
# Usage: ./sync-progress.sh [--yes]
#   --yes   skip the confirmation prompt (for non-interactive use)

set -e

REPO="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DOWNLOADS=~/Downloads
DEST="$REPO/progress"
SHOTS="$REPO/screenshots"

# Find the newest progress-*.json in Downloads
FILE=$(ls -t "$DOWNLOADS"/progress-*.json 2>/dev/null | head -1)

if [ -z "$FILE" ]; then
  echo "No progress-*.json found in ~/Downloads."
  echo "Click 'Export progress JSON' in the Progress tab first."
  exit 1
fi

BASENAME=$(basename "$FILE")
echo "Found: $FILE"

mv "$FILE" "$DEST/$BASENAME"
echo "Moved to progress/$BASENAME"

cd "$REPO"
git add "progress/$BASENAME"

# Stage new/modified screenshots ONLY.
#
# A bare `git add screenshots/` also stages DELETIONS — modern git treats a
# pathspec like `git add -A <path>` — so deleting a screenshot locally and
# then running this would silently commit and push that removal, contrary to
# the "new/modified" promise above. --ignore-removal stages additions and
# modifications only; any local deletions are surfaced below instead of
# being acted on automatically.
SHOT_COUNT=0
DELETED_SHOTS=""
if [ -d "$SHOTS" ]; then
  git add --ignore-removal screenshots/ 2>/dev/null || true
  SHOT_COUNT=$(git diff --cached --name-only -- screenshots/ | wc -l | tr -d ' ')
  DELETED_SHOTS=$(git ls-files --deleted -- screenshots/ 2>/dev/null || true)
fi

if [ -n "$DELETED_SHOTS" ]; then
  echo ""
  echo "⚠  Deleted locally but NOT staged (left alone on purpose):"
  echo "$DELETED_SHOTS" | sed 's/^/     /'
  echo "   To actually remove them:  git rm <path>"
fi

# CLAUDE.md: never push without first stating the artifact + target and
# receiving explicit confirmation. This is that gate — nothing is committed
# or pushed until it passes.
BRANCH=$(git rev-parse --abbrev-ref HEAD)
REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "(no origin remote)")

echo ""
echo "── About to commit and push ──────────────────────────"
echo "  Artifact:"
git diff --cached --name-only | sed 's/^/    /'
echo "  Target:   $REMOTE_URL ($BRANCH)"
echo "──────────────────────────────────────────────────────"

if [ "${1:-}" != "--yes" ]; then
  printf "Proceed? [y/N] "
  read -r REPLY || REPLY=""
  case "$REPLY" in
    [yY]|[yY][eE][sS]) ;;
    *)
      echo "Aborted — nothing committed or pushed. Staged changes left in place."
      echo "(Unstage with: git reset)"
      exit 1
      ;;
  esac
fi

if [ "$SHOT_COUNT" -gt 0 ]; then
  git commit -m "progress: $BASENAME + ${SHOT_COUNT} screenshot(s)"
else
  git commit -m "progress: $BASENAME"
fi

git push
echo "Done. Progress + screenshots are in the repo."
