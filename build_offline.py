#!/usr/bin/env python3
"""Build offline.html from quiz.html + cheatsheet.md + brief.md + field_manual.md.

Output is a single self-contained HTML file (~350KB) that works with no network:
- marked.js library inlined (no CDN)
- all markdown content base64-embedded in a JS const
- fetch() override intercepts requests for those URLs and serves the embedded data

Usage:
    curl -s "https://cdn.jsdelivr.net/npm/marked@15/marked.min.js" -o /tmp/marked.min.js
    python3 build_offline.py

Keep this script in the repo so re-builds are reproducible after content updates.
"""
import base64
import json
import os
import sys

CERT = os.path.dirname(os.path.abspath(__file__))
MD_FILES = ['cheatsheet.md', 'super_user_brief.md', 'field_manual.md', 'loops_manual.md', 'official_exam_guide.md']
MARKED_JS_PATH = '/tmp/marked.min.js'

if not os.path.exists(MARKED_JS_PATH):
    sys.exit(
        f'ERROR: {MARKED_JS_PATH} not found.\n'
        'Run: curl -s "https://cdn.jsdelivr.net/npm/marked@15/marked.min.js" -o /tmp/marked.min.js'
    )

with open(MARKED_JS_PATH) as f:
    marked_js = f.read()

# Base64-encode each markdown file (avoids JS string escaping issues with
# backticks, em dashes, $, etc. in the content).
md_b64 = {}
for fname in MD_FILES:
    with open(os.path.join(CERT, fname), 'rb') as h:
        md_b64['./' + fname] = base64.b64encode(h.read()).decode('ascii')

with open(os.path.join(CERT, 'quiz.html')) as f:
    html = f.read()

# 1. Replace the CDN marked.js script tag with inlined library
old_script = '<script src="https://cdn.jsdelivr.net/npm/marked@15/marked.min.js"></script>'
new_script = '<script>' + marked_js + '</script>'
assert old_script in html, 'marked.js script tag not found in quiz.html'
html = html.replace(old_script, new_script)

# 2. Title + visual badge so the user knows they have the offline build
html = html.replace(
    '<title>Claude Builder Cert — Study Hub</title>',
    '<title>Claude Builder Cert — Study Hub (Offline)</title>'
)
html = html.replace(
    '<h1>Claude Builder Cert — <span class="accent">Study Hub</span></h1>',
    '<h1>Claude Builder Cert — <span class="accent">Study Hub</span> '
    '<span style="font-size:11px;color:var(--green);font-weight:500;">OFFLINE</span></h1>'
)

# 3. Inject the offline data + fetch override BEFORE </head>
offline_block = f'''
<script>
// === OFFLINE MODE ===
// Markdown sources are embedded as base64 so this file works with no network.
const __OFFLINE_MD__ = {json.dumps(md_b64)};
function __b64decodeUtf8(b64) {{
  const bytes = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
  return new TextDecoder('utf-8').decode(bytes);
}}
// Intercept fetch() calls for known markdown URLs and serve from embedded data.
const __origFetch__ = window.fetch.bind(window);
window.fetch = function(input, init) {{
  const url = typeof input === 'string' ? input : (input && input.url) || '';
  const base = String(url).split('?')[0];
  if (__OFFLINE_MD__[base]) {{
    return Promise.resolve(new Response(__b64decodeUtf8(__OFFLINE_MD__[base]), {{
      status: 200, statusText: 'OK',
      headers: {{ 'Content-Type': 'text/markdown; charset=utf-8' }}
    }}));
  }}
  return __origFetch__(input, init);
}};
</script>
'''
html = html.replace('</head>', offline_block + '</head>')

out_path = os.path.join(CERT, 'offline.html')
with open(out_path, 'w') as f:
    f.write(html)

print(f'offline.html: {os.path.getsize(out_path):,} bytes')
print(f'  marked.js inlined: {len(marked_js):,} chars')
for k, v in md_b64.items():
    print(f'  {k}: {len(v):,} chars (base64)')
