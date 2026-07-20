#!/usr/bin/env bash
# Moves the latest progress export from Downloads into the repo and pushes.
# Run after clicking "Export progress JSON" in the Progress tab.
# Usage: ./sync-progress.sh

set -e

REPO="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DOWNLOADS=~/Downloads
DEST="$REPO/progress"

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
git commit -m "progress: $BASENAME"
git push
echo "Pushed. Progress is now in the repo."
