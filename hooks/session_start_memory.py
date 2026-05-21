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


def main():
    lines = []

    try:
        f = (_req("/api/context") or {}).get("data", {}).get("fleet") or {}
        if f:
            lines.append(f"Fleet: {f.get('total_tables','?')} tables / "
                         f"{f.get('total_rows','?')} rows / {f.get('db_size','?')}")
    except Exception:
        pass

    try:
        d = (_req("/api/memory/recall?limit=6") or {}).get("data", {})
        for r in d.get("rows") or []:
            meta = r.get("metadata") or {}
            who = meta.get("principal", r.get("node_id", "?"))
            when = (r.get("created_at") or "")[:16].replace("T", " ")
            lines.append(f"{when} {who}/{meta.get('kind','note')} "
                         f"{{{meta.get('space','—')}}}: {r.get('title','')}")
    except Exception:
        pass

    if lines:
        ctx = (f"{BRAND} MEMORY — continued context (atlas.axe.observer, SessionStart):\n- "
               + "\n- ".join(lines)
               + f"\n(save new context with: {BRAND.lower()}-memory save \"...\")")
        print(json.dumps({"additionalContext": ctx}))
    else:
        print("{}")


if __name__ == "__main__":
    main()
