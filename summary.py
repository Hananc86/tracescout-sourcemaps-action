#!/usr/bin/env python3
"""TraceScout upload summary + typed error annotations for GitHub Actions.

Reads the CLI's --json output from TS_UPLOAD_JSON. Emits:
  - ::error annotations for each typed upload failure (file + code, message
    truncated; the CLI already redacts secrets and never includes source
    content, and this script prints ONLY file/code/message fields).
  - a step summary with safe metadata (counts, per-file codes).
Never prints the auth token (it is not in the JSON at all) or map contents.
"""
import json
import os
import sys

code = int(sys.argv[1]) if len(sys.argv) > 1 else 1
raw = os.environ.get("TS_UPLOAD_JSON", "") or "{}"
try:
    j = json.loads(raw)
except Exception:
    j = {}

up = j.get("uploaded", 0)
idem = j.get("idempotent", 0)
failed = j.get("failed", 0)
dry = j.get("dryRun", False)

lines = [
    "### TraceScout source maps",
    f"- uploaded: **{up}** · idempotent: **{idem}** · failed: **{failed}**"
    + (" · _(dry-run)_" if dry else ""),
]
for r in j.get("results") or []:
    if not r.get("ok"):
        msg = str(r.get("message", ""))[:180].replace("\n", " ")
        print(f"::error title=TraceScout upload {r.get('code', 'error')}::{r.get('file')}: {msg}")
        lines.append(f"- ❌ `{r.get('file')}` — `{r.get('code')}`")
    elif r.get("dryRun"):
        lines.append(f"- 📝 `{r.get('file')}` (planned)")

summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
if summary_path:
    with open(summary_path, "a", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
else:
    print("\n".join(lines))
