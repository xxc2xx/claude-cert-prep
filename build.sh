#!/usr/bin/env bash
# Build offline.html from quiz.html
# - Replaces CDN marked.js script tag with the bundled version
# - Updates the title to include "(Offline)"
# Usage: ./build.sh

set -euo pipefail

QUIZ="quiz.html"
OUT="offline.html"
BUNDLE="marked.bundle.js"

if [[ ! -f "$QUIZ" ]]; then echo "ERROR: $QUIZ not found"; exit 1; fi
if [[ ! -f "$BUNDLE" ]]; then echo "ERROR: $BUNDLE not found"; exit 1; fi

python3 - <<EOF
import sys

with open('$QUIZ', 'r') as f:
    content = f.read()

with open('$BUNDLE', 'r') as f:
    bundle = f.read().rstrip()

# 1. Swap title
content = content.replace(
    '<title>Claude Builder Cert — Study Hub</title>',
    '<title>Claude Builder Cert — Study Hub (Offline)</title>',
    1
)

# 2. Swap CDN script tag with bundled inline version
cdn_tag = '<script src="https://cdn.jsdelivr.net/npm/marked@15/marked.min.js"></script>'
if cdn_tag not in content:
    print("ERROR: CDN script tag not found in $QUIZ", file=sys.stderr)
    sys.exit(1)

content = content.replace(cdn_tag, bundle, 1)

with open('$OUT', 'w') as f:
    f.write(content)

print(f"Built $OUT from $QUIZ ({len(content)} bytes)")
EOF
