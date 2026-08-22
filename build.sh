#!/usr/bin/env bash
# Build offline.html from quiz.html
# - Replaces CDN marked.js with bundled inline version
# - Inlines assessment-qa.md, cheatsheet.md, official_exam_guide.md
#   so offline.html works with zero network requests
# - Updates the title
# Usage: ./build.sh

set -euo pipefail

QUIZ="quiz.html"
OUT="offline.html"
BUNDLE="marked.bundle.js"

if [[ ! -f "$QUIZ" ]]; then echo "ERROR: $QUIZ not found"; exit 1; fi
if [[ ! -f "$BUNDLE" ]]; then echo "ERROR: $BUNDLE not found"; exit 1; fi

python3 - <<'PYEOF'
import sys, json

with open('quiz.html', 'r') as f:
    content = f.read()

with open('marked.bundle.js', 'r') as f:
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
    print("ERROR: CDN script tag not found in quiz.html", file=sys.stderr)
    sys.exit(1)
content = content.replace(cdn_tag, bundle, 1)

# 3. Inline markdown files so fetch() calls work offline
#    Strategy: inject a window.__MD_CACHE__ map before the first <script> in body,
#    then patch loadSplittable to check cache before fetching.
md_files = {
    './assessment-qa.md': 'assessment-qa.md',
    './cheatsheet.md': 'cheatsheet.md',
    './official_exam_guide.md': 'official_exam_guide.md',
}
cache = {}
for url, path in md_files.items():
    try:
        with open(path, 'r') as f:
            cache[url] = f.read()
        print(f"  inlined {path} ({len(cache[url])} chars)")
    except FileNotFoundError:
        print(f"  WARNING: {path} not found — skipping", file=sys.stderr)

cache_js = f'<script>window.__MD_CACHE__={json.dumps(cache)};</script>\n'

# Inject right before </head>
content = content.replace('</head>', cache_js + '</head>', 1)

# 4. Patch loadSplittable to hit cache first
patch = '''
// Offline cache patch — injected by build.sh
const __origFetch = window.fetch.bind(window);
window.fetch = function(url, opts) {
  if (window.__MD_CACHE__ && window.__MD_CACHE__[url]) {
    return Promise.resolve(new Response(window.__MD_CACHE__[url], {status: 200}));
  }
  return __origFetch(url, opts);
};
'''
content = content.replace('// ----- state -----', patch + '\n// ----- state -----', 1)

with open('offline.html', 'w') as f:
    f.write(content)

print(f"Built offline.html from quiz.html ({len(content)} bytes)")
PYEOF
