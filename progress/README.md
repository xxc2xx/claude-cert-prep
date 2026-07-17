# Progress snapshots

This folder holds JSON exports of quiz progress + mock exam history — so
records survive browser cache wipes and are shareable across devices.

## The workflow

1. **In the quiz app (Progress tab)** → click **📥 Export progress JSON**.
   A file downloads to `~/Downloads/progress-YYYY-MM-DD-HHMM.json`.
2. **Move the file into this folder** and commit + push:
   ```bash
   mv ~/Downloads/progress-*.json ~/claude-cert-prep/progress/
   cd ~/claude-cert-prep && git add progress/ && git commit -m "progress snapshot" && git push
   ```
3. **On a new device** — Progress tab → **📤 Import progress JSON** → select the
   latest file from this folder. All answers, blind-spot data, and mock history
   are restored.

## Naming

Filenames are timestamped, so multiple snapshots coexist. The `mockHistory`
inside each file is append-only (with dedup on import by timestamp), so newer
files are strict supersets of older ones. Keep them all — trend data is worth
more than disk space.

## Privacy note

This repo is public. The snapshots contain:
- Which questions you've answered + your chosen index
- Confidence ratings
- Mock exam scores + timestamps

Not sensitive but personally identifying by proxy (your prep trajectory).
Move to a private branch or a gitignored subfolder if that's a concern.

## Schema (v1)

```json
{
  "schema": "claude-cert-progress-v1",
  "exportedAt": "2026-07-17T12:34:56.789Z",
  "progress": {
    "b1-q01": { "chosen": 2, "correct": true, "confidence": "high", "ts": 1721221200000 }
  },
  "lastMock": { "scaledScore": 835, "perDomain": {...}, ... },
  "mockHistory": [ { "timestamp": ..., "scaledScore": 835, ... }, ... ]
}
```
