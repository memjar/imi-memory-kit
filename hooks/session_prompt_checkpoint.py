#!/usr/bin/env python3
"""UserPromptSubmit hook — periodic mid-session save checkpoint.

Fires before every user prompt. Tracks turn count per session in a temp file.
Every SAVE_INTERVAL turns, checks if anything was saved this session.
If nothing saved: injects an additionalContext reminder so Claude saves before
continuing. Entirely silent to the user — only the model sees the injection.

Wire it (per teammate, via install.sh into ~/.claude/settings.json):
  "hooks": { "UserPromptSubmit": [ { "hooks": [ {
      "type": "command",
      "command": "python3 ~/imi-memory-kit/hooks/session_prompt_checkpoint.py"
  } ] } ] }
"""
import json
import os
import pathlib
import ssl
import sys
import urllib.parse
import urllib.request

SAVE_INTERVAL = 10   # remind every N turns if nothing saved yet
ATLAS = os.environ.get("AXE_MEMORY_URL", "https://atlas.axe.observer").rstrip("/")
SESSION = os.environ.get("AXE_SESSION_ID", "").strip()
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
KEY = (os.environ.get(BRAND + "_MEMORY_KEY")
       or os.environ.get(BRAND + "_API_KEY")
       or os.environ.get("AXE_API_KEY") or "").strip()


def _turn_count() -> int:
    """Increment and return the turn counter for this session."""
    if not SESSION:
        return 0
    p = pathlib.Path(f"/tmp/imi_session_{SESSION}_turns")
    try:
        count = int(p.read_text().strip()) + 1 if p.exists() else 1
    except Exception:
        count = 1
    try:
        p.write_text(str(count))
    except Exception:
        pass
    return count


def _session_has_saves() -> bool:
    if not KEY or not SESSION:
        return True
    try:
        headers = {"Content-Type": "application/json", "X-API-Key": KEY}
        qs = urllib.parse.urlencode({"session": SESSION, "limit": 1, "mine": "1"})
        req = urllib.request.Request(
            ATLAS + "/api/memory/recall?" + qs, method="GET", headers=headers
        )
        d = json.loads(urllib.request.urlopen(req, timeout=4, context=_SSL).read())
        count = (d.get("data") or {}).get("count") or 0
        return count > 0
    except Exception:
        return True  # on error, don't interrupt


def main():
    # Consume stdin payload (UserPromptSubmit may send context — discard gracefully)
    try:
        if not sys.stdin.isatty():
            json.load(sys.stdin)
    except Exception:
        pass

    turn = _turn_count()

    # Only fire at checkpoint turns; skip if already saved or no key
    if turn % SAVE_INTERVAL != 0 or not KEY:
        print("{}")
        return

    if _session_has_saves():
        print("{}")
        return

    cli = BRAND.lower() + "-memory"
    tags = BRAND.lower()
    print(json.dumps({
        "additionalContext": (
            f"[{BRAND} Memory — turn {turn} checkpoint] {turn} turns have passed "
            f"without a team memory save this session. Before responding, check: "
            f"have any decisions, findings, or client preferences come up that a "
            f"teammate would want to know? If yes, run:\n"
            f"`{cli} save \"<1-2 sentences>\" --kind decision|finding --share --tags {tags}`\n"
            f"Then continue with the user's request. If nothing is worth saving, proceed normally."
        )
    }))


if __name__ == "__main__":
    main()
