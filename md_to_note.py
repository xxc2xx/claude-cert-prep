#!/usr/bin/env python3
"""md_to_note — pipe a markdown file into Apple Notes.

Usage:
  python md_to_note.py --file notes.md --title "My Note" --folder "Claude"

First run will trigger a one-time macOS Automation permission prompt
(System Settings → Privacy & Security → Automation → grant access to Notes).
"""
import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

import markdown


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--file", required=True, help="Path to markdown file")
    p.add_argument("--title", required=True, help="Note title (also used as H1)")
    p.add_argument("--folder", default="Notes", help='Notes folder name (default: "Notes")')
    p.add_argument("--account", default="iCloud", help='Notes account (default: "iCloud")')
    args = p.parse_args()

    md_path = Path(args.file).expanduser().resolve()
    if not md_path.is_file():
        print(f"error: file not found: {md_path}", file=sys.stderr)
        return 1

    html_body = markdown.markdown(
        md_path.read_text(encoding="utf-8"),
        extensions=["extra", "sane_lists"],
    )
    full_html = f"<h1>{args.title}</h1>\n{html_body}"

    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".html", delete=False, encoding="utf-8"
    ) as tmp:
        tmp.write(full_html)
        tmp_path = tmp.name

    applescript = f'''
    set noteBody to read POSIX file "{tmp_path}" as «class utf8»
    tell application "Notes"
        tell account "{args.account}"
            set targetFolder to folder "{args.folder}"
            make new note at targetFolder with properties {{name:"{args.title}", body:noteBody}}
        end tell
    end tell
    '''

    result = subprocess.run(
        ["osascript", "-e", applescript], capture_output=True, text=True
    )
    Path(tmp_path).unlink(missing_ok=True)

    if result.returncode != 0:
        print(f"AppleScript error:\n{result.stderr}", file=sys.stderr)
        print(
            "If this is the first run, grant Automation access:\n"
            "  System Settings → Privacy & Security → Automation → "
            "your terminal app → enable Notes.",
            file=sys.stderr,
        )
        return 1

    print(f"created note '{args.title}' in '{args.account}' / '{args.folder}'")
    return 0


if __name__ == "__main__":
    sys.exit(main())
