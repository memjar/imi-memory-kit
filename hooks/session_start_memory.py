#!/usr/bin/env python3
"""Portable SessionStart hook — inject AXE continued context into any session.

Talks ONLY to the remote memory layer (atlas.axe.observer) via the typed
/api/memory/recall endpoint, so it works on any teammate's machine and carries
the same per-person space scoping as the CLI. Pulls a compact fleet snapshot +
the caller's visible memories (their spaces + the shared team pool) and emits
Claude Code's {"additionalContext": "..."} so the model starts caught up.

Never blocks or breaks session start: any failure prints "{}" and exits 0.

Wire it (per teammate, in ~/.claude/settings.json):
  "hooks": { "SessionStart": [ { "hooks": [ {
      "type": "command",
      "command": "/usr/local/bin/python3 ~/axe-memory-kit/hooks/session_start_memory.py"
  } ] } ] }
and set AXE_API_KEY (and optionally AXE_SESSION_ID) in your shell profile.
"""
import json
import os
import ssl
import urllib.request

ATLAS = os.environ.get("AXE_MEMORY_URL", "https://atlas.axe.observer").rstrip("/")
_SSL = ssl._create_unverified_context()


def _brand():
    p = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "kit.conf")
    try:
        for line in open(p):
            line = line.strip()
            if line.startswith("BRAND=") and "=" in line:
                return line.split("=", 1)[1].strip().strip('"').strip("'")
    except Exception:
        pass
    return "AXE"


BRAND = _brand()
# Key precedence: <BRAND>_MEMORY_KEY → <BRAND>_API_KEY → AXE_API_KEY.
KEY = (os.environ.get(BRAND + "_MEMORY_KEY")
       or os.environ.get(BRAND + "_API_KEY")
       or os.environ.get("AXE_API_KEY") or "").strip()


def _req(path, timeout=8):
    headers = {"Content-Type": "application/json"}
    if KEY:
        headers["X-API-Key"] = KEY
    req = urllib.request.Request(ATLAS + path, method="GET", headers=headers)
    with urllib.request.urlopen(req, timeout=timeout, context=_SSL) as r:
        return json.loads(r.read())


def _author(row: dict) -> str:
    tags = (row.get("metadata") or {}).get("tags") or []
    for t in tags:
        if t.startswith("from:"):
            return t[5:]
    return (row.get("metadata") or {}).get("principal", row.get("node_id", "?"))


def main():
    lines = []

    try:
        d = (_req("/api/memory/recall?limit=8") or {}).get("data", {})
        scope = d.get("scope", "")
        rows = d.get("rows") or []
        if rows:
            lines.append(f"Team pool: {scope} ({d.get('count', len(rows))} memories)")
        for r in rows:
            meta = r.get("metadata") or {}
            who = _author(r)
            when = (r.get("created_at") or "")[:10]
            kind = meta.get("kind", "note")
            lines.append(f"{when} [{who}/{kind}] {r.get('title','')}")
    except Exception:
        pass

    if lines:
        cli = BRAND.lower() + "-memory"
        ctx = (f"{BRAND} MEMORY — team context injected at session start:\n- "
               + "\n- ".join(lines)
               + f"\n\nSave new context: {cli} save \"...\" --kind decision"
               + f"\nSearch: {cli} search \"<keyword>\"")
        print(json.dumps({"additionalContext": ctx}))
    else:
        print("{}")


if __name__ == "__main__":
    main()
