#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
#  memory kit — one-command install / attach for terminal AI sessions
#
#  Branding (BRAND / CLI_NAME / ENV_FILE / MARKER) comes from kit.conf, so the
#  AXE and IMI kits share this script verbatim. Wires the memory layer into
#  your shell + Claude Code so every new session auto-recalls continued context
#  and the model knows to save:
#    1. writes <ENV_FILE>  (your key + PATH + per-session id, chmod 600)
#    2. sources it from your shell profile (idempotent marked block)
#    3. installs SessionStart + PostCompact + Stop hooks (~/.claude/settings.json)
#    4. drops the "<BRAND> Memory protocol" into ~/.claude/CLAUDE.md
#    5. installs /<brand>-recall and /<brand>-save slash commands (~/.claude/commands/)
#
#  Usage:
#    ./install.sh                      # prompts for your key if none in the env
#    AXE_MEMORY_KEY=bnk_... ./install.sh   # (IMI_MEMORY_KEY=... for the IMI kit)
#    AXE_API_KEY=bnk_... ./install.sh      # also accepted as a fallback
#    ./install.sh --uninstall          # removes everything above
# ──────────────────────────────────────────────────────────────────────────
set -euo pipefail

# Resolve the kit dir (this script's location), following symlinks.
SRC="${BASH_SOURCE[0]}"
while [ -h "$SRC" ]; do DIR="$(cd -P "$(dirname "$SRC")" && pwd)"; SRC="$(readlink "$SRC")"; [[ $SRC != /* ]] && SRC="$DIR/$SRC"; done
KIT_DIR="$(cd -P "$(dirname "$SRC")" && pwd 2>/dev/null || echo "")"

# Bootstrap: when run via `bash <(curl ...)`, BASH_SOURCE[0] is /dev/fd/N so
# KIT_DIR resolves to /dev/fd and kit.conf is unreachable. Detect by checking
# for kit.conf; clone to ~/imi-memory-kit and re-exec from there.
_REPO_URL="${REPO_URL:-https://github.com/memjar/imi-memory-kit.git}"
_KIT_DIR_NAME="${KIT_DIR_NAME:-imi-memory-kit}"
if [ ! -f "$KIT_DIR/kit.conf" ]; then
  _DEST="$HOME/$_KIT_DIR_NAME"
  printf "→ Downloading %s to %s ...\n" "$_KIT_DIR_NAME" "$_DEST" >&2
  if [ -d "$_DEST/.git" ]; then
    git -C "$_DEST" pull --quiet >&2
  else
    git clone --quiet "$_REPO_URL" "$_DEST" >&2
  fi
  exec bash "$_DEST/install.sh" "$@"
fi

# ── Branding (the only per-kit difference) ──
# shellcheck disable=SC1091
[ -f "$KIT_DIR/kit.conf" ] && source "$KIT_DIR/kit.conf"
: "${BRAND:=AXE}"; : "${CLI_NAME:=axe-memory}"; : "${MARKER:=$CLI_NAME}"
: "${ENV_FILE:=$HOME/.${CLI_NAME}.env}"

PROFILE="${ZDOTDIR:-$HOME}/.zshrc"
case "${SHELL:-}" in *bash) PROFILE="$HOME/.bashrc";; esac
SETTINGS="$HOME/.claude/settings.json"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
PYBIN="$(command -v python3 || true)"
HOOK_PATH="$KIT_DIR/hooks/session_start_memory.py"
STOP_HOOK_PATH="$KIT_DIR/hooks/session_stop_memory.py"
CHECKPOINT_HOOK_PATH="$KIT_DIR/hooks/session_prompt_checkpoint.py"
START="# >>> $MARKER >>>"
END="# <<< $MARKER <<<"
MD_START="<!-- $MARKER:start -->"
MD_END="<!-- $MARKER:end -->"

strip_block() { # file start end
  [ -f "$1" ] || return 0
  awk -v s="$2" -v e="$3" '$0==s{f=1} $0==e{f=0;next} !f' "$1" > "$1.kittmp" && mv "$1.kittmp" "$1"
}

uninstall() {
  strip_block "$PROFILE" "$START" "$END"
  strip_block "$CLAUDE_MD" "$MD_START" "$MD_END"
  strip_block "$HOME/.cursor/rules" "<!-- $MARKER:cursor:start -->" "<!-- $MARKER:cursor:end -->"
  rm -f "$ENV_FILE"
  # Remove slash commands
  _BRAND_LOWER="$(echo "$BRAND" | tr '[:upper:]' '[:lower:]')"
  rm -f "$HOME/.claude/commands/${_BRAND_LOWER}-recall.md" \
        "$HOME/.claude/commands/${_BRAND_LOWER}-save.md"
  # Remove all hooks from this kit (SessionStart, PostCompact, Stop)
  if [ -f "$SETTINGS" ] && [ -n "$PYBIN" ]; then
    SETTINGS="$SETTINGS" KIT_DIR="$KIT_DIR" "$PYBIN" - <<'PY'
import json,os
p=os.environ["SETTINGS"]; kit=os.environ["KIT_DIR"]
try: d=json.load(open(p))
except Exception: raise SystemExit
for event in list((d.get("hooks") or {}).keys()):
    groups=d["hooks"][event]
    groups=[g for g in groups if not any(kit in h.get("command","") for h in g.get("hooks",[]))]
    if groups: d["hooks"][event]=groups
    else: d["hooks"].pop(event,None)
json.dump(d,open(p,"w"),indent=2)
PY
  fi
  echo "$BRAND memory uninstalled. Open a new terminal for it to take effect."
  exit 0
}

[ "${1:-}" = "--uninstall" ] && uninstall

[ -n "$PYBIN" ] || { echo "python3 not found on PATH — required." >&2; exit 1; }

# ── Resolve + validate the key ──
# Dedicated memory-key var wins (so it can differ from an ambient AXE_API_KEY a
# tool pins to another identity), then <BRAND>_API_KEY, then plain AXE_API_KEY.
MEM_KEY_VAR="${BRAND}_MEMORY_KEY"
BRAND_KEY_VAR="${BRAND}_API_KEY"
KEY="${!MEM_KEY_VAR:-${!BRAND_KEY_VAR:-${AXE_API_KEY:-}}}"
if [ -z "$KEY" ]; then
  printf "Enter your %s memory key (bnk_...): " "$BRAND" >&2; read -r KEY
fi
WHO="$(env "$MEM_KEY_VAR=$KEY" "$PYBIN" "$KIT_DIR/$CLI_NAME" whoami 2>/dev/null || true)"
[ -n "$WHO" ] || { echo "Key rejected by the memory layer. Check your key." >&2; exit 1; }
echo "✓ identity: $WHO"

# Derive the user's display name for from: attribution on saves.
# Prefer <BRAND>_USER env var, then prompt for email and parse first segment.
USER_VAR="${BRAND}_USER"
IMI_USER_VAL="${!USER_VAR:-}"
if [ -z "$IMI_USER_VAL" ]; then
  printf "Your work email (for memory attribution, e.g. jlewis@consultimi.com): " >&2
  read -r _EMAIL
  # jlewis@consultimi.com → jlewis
  IMI_USER_VAL="${_EMAIL%%@*}"
fi
IMI_USER_VAL="$(echo "$IMI_USER_VAL" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9._-')"
echo "✓ attribution name: $IMI_USER_VAL"

# ── 1. env file (key out of the shell rc; chmod 600) ──
umask 077
cat > "$ENV_FILE" <<EOF
# $BRAND memory — generated by install.sh. Safe to edit your key here.
export ${MEM_KEY_VAR}="$KEY"
export ${USER_VAR}="$IMI_USER_VAL"
export AXE_MEMORY_URL="${AXE_MEMORY_URL:-https://atlas.axe.observer}"
export PATH="$KIT_DIR:\$PATH"
[ -z "\${AXE_SESSION_ID:-}" ] && export AXE_SESSION_ID="\$(uuidgen 2>/dev/null || echo \$\$-\$(date +%s))"
EOF
chmod 600 "$ENV_FILE"
echo "✓ wrote $ENV_FILE"

# ── 2. source it from the shell profile (idempotent) ──
strip_block "$PROFILE" "$START" "$END"
{ echo "$START"; echo "[ -f \"$ENV_FILE\" ] && source \"$ENV_FILE\""; echo "$END"; } >> "$PROFILE"
echo "✓ wired $PROFILE"

# ── 3. Claude Code hooks: SessionStart + PostCompact + Stop + UserPromptSubmit ──
mkdir -p "$(dirname "$SETTINGS")"
START_CMD="$PYBIN $HOOK_PATH"
STOP_CMD="$PYBIN $STOP_HOOK_PATH"
CHECKPOINT_CMD="$PYBIN $CHECKPOINT_HOOK_PATH"
SETTINGS="$SETTINGS" START_CMD="$START_CMD" START_HOOK="$HOOK_PATH" \
  STOP_CMD="$STOP_CMD" STOP_HOOK="$STOP_HOOK_PATH" \
  CHECKPOINT_CMD="$CHECKPOINT_CMD" CHECKPOINT_HOOK="$CHECKPOINT_HOOK_PATH" "$PYBIN" - <<'PY'
import json,os
p=os.environ["SETTINGS"]
start_cmd=os.environ["START_CMD"]; start_hook=os.environ["START_HOOK"]
stop_cmd=os.environ["STOP_CMD"];   stop_hook=os.environ["STOP_HOOK"]
chk_cmd=os.environ["CHECKPOINT_CMD"]; chk_hook=os.environ["CHECKPOINT_HOOK"]
d={}
if os.path.exists(p):
    try: d=json.load(open(p))
    except Exception: d={}
h=d.setdefault("hooks",{})
# SessionStart — inject team context at session open
ss=h.setdefault("SessionStart",[])
if not any(start_hook in c.get("command","") for g in ss for c in g.get("hooks",[])):
    ss.append({"hooks":[{"type":"command","command":start_cmd}]})
# PostCompact — re-inject after context compression so memory survives /compact
pc=h.setdefault("PostCompact",[])
if not any(start_hook in c.get("command","") for g in pc for c in g.get("hooks",[])):
    pc.append({"hooks":[{"type":"command","command":start_cmd}]})
# Stop — nudge Claude to save wrap-up if nothing saved this session
st=h.setdefault("Stop",[])
if not any(stop_hook in c.get("command","") for g in st for c in g.get("hooks",[])):
    st.append({"hooks":[{"type":"command","command":stop_cmd}]})
# UserPromptSubmit — periodic mid-session checkpoint every N turns
up=h.setdefault("UserPromptSubmit",[])
if not any(chk_hook in c.get("command","") for g in up for c in g.get("hooks",[])):
    up.append({"hooks":[{"type":"command","command":chk_cmd}]})
json.dump(d,open(p,"w"),indent=2)
PY
echo "✓ installed SessionStart + PostCompact + Stop + UserPromptSubmit hooks in $SETTINGS"

# ── 4. the protocol block → tells the model to recall/save ──
strip_block "$CLAUDE_MD" "$MD_START" "$MD_END"
mkdir -p "$(dirname "$CLAUDE_MD")"
_BRAND_LOWER="$(echo "$BRAND" | tr '[:upper:]' '[:lower:]')"
cat >> "$CLAUDE_MD" <<EOF
$MD_START
## $BRAND Memory — required protocol

This machine is part of the $BRAND team memory pool. Context is shared across all
teammates' sessions via \`$CLI_NAME\` (backed by atlas.axe.observer).

**Rules — not suggestions:**
- **Session start:** run \`$CLI_NAME recall\` before starting any task. Treat results as prior context.
- **After any significant decision, finding, or client preference:** save it immediately.
  \`$CLI_NAME save "<1-2 sentences>" --kind decision|finding --share --tags ${_BRAND_LOWER},<area>\`
  Do NOT let context die in this session. If in doubt, save it.
- **Search before re-deriving:** \`$CLI_NAME search "<keyword>"\` — a teammate may have already logged it.
- **Use /${_BRAND_LOWER}-recall** and **/${_BRAND_LOWER}-save** slash commands for zero-friction access.
$MD_END
EOF
echo "✓ added protocol to $CLAUDE_MD"

# ── 5. Slash commands → /<brand>-recall and /<brand>-save in Claude Code ──
_BRAND_LOWER="$(echo "$BRAND" | tr '[:upper:]' '[:lower:]')"
_CMD_DIR="$HOME/.claude/commands"
mkdir -p "$_CMD_DIR"
cat > "$_CMD_DIR/${_BRAND_LOWER}-recall.md" <<EOF
Run \`$CLI_NAME recall\` and briefly surface the key team context from the results.
EOF
cat > "$_CMD_DIR/${_BRAND_LOWER}-save.md" <<EOF
Save an important decision or finding to the $BRAND team memory pool.

If the user specified what to save, run immediately:
\`$CLI_NAME save "<their text>" --kind decision --share --tags ${_BRAND_LOWER}\`

If the user did not specify what to save, ask: "What's the key decision or finding? (1-2 sentences)"
then run the command with their answer.

Always include \`--share\` so the whole team sees it. Kind options: note | decision | finding | task
EOF
cat > "$_CMD_DIR/${_BRAND_LOWER}-checkpoint.md" <<EOF
Review this session so far and identify every decision, finding, or client preference worth saving.

For each significant item, run:
\`$CLI_NAME save "<1-2 sentence summary>" --kind decision|finding --share --tags ${_BRAND_LOWER},<area>\`

Save ALL significant items before continuing. If there is genuinely nothing worth saving from
this session so far, say so in one sentence. Do not skip saves out of uncertainty — if in doubt, save it.
EOF
echo "✓ installed /${_BRAND_LOWER}-recall, /${_BRAND_LOWER}-save, and /${_BRAND_LOWER}-checkpoint commands in $_CMD_DIR"

# ── 6. Cursor rules → tells Cursor agent to recall/save ──
CURSOR_RULES="$HOME/.cursor/rules"
CURSOR_START="<!-- $MARKER:cursor:start -->"
CURSOR_END="<!-- $MARKER:cursor:end -->"
strip_block "$CURSOR_RULES" "$CURSOR_START" "$CURSOR_END"
if [ -d "$HOME/.cursor" ] || [ -f "$CURSOR_RULES" ]; then
  mkdir -p "$(dirname "$CURSOR_RULES")"
  cat >> "$CURSOR_RULES" <<EOF

$CURSOR_START
## $BRAND Memory — team continued context

\`$CLI_NAME\` is installed at \`$(command -v "$CLI_NAME" 2>/dev/null || echo "$KIT_DIR/$CLI_NAME")\`.
Use it to share context with teammates across tools and sessions.

**Session start:** \`$CLI_NAME recall\`
**Save a decision:** \`$CLI_NAME save "..." --kind decision --tags <area>\`
**Search:** \`$CLI_NAME search "<keyword>"\`
**Add to team pool:** append \`--share\`

Kind options: note | decision | finding | task
Do this for any cross-session or cross-teammate context — architecture calls,
client preferences, data findings worth remembering.
$CURSOR_END
EOF
  echo "✓ added $BRAND memory protocol to $CURSOR_RULES"
else
  echo "  (Cursor not detected — skipping ~/.cursor/rules)"
fi

_BRAND_LOWER="$(echo "$BRAND" | tr '[:upper:]' '[:lower:]')"
echo ""
echo "Done. $BRAND memory is attached as $WHO."
echo "→ run:  source \"$ENV_FILE\"   (or open a new terminal)"
echo "→ then: $CLI_NAME recall"
echo ""
echo "  Claude Code hooks wired:"
echo "    SessionStart       — injects team context at session open"
echo "    PostCompact        — re-injects after /compact so memory survives compression"
echo "    Stop               — nudges Claude to save a wrap-up if nothing saved this session"
echo "    UserPromptSubmit   — periodic mid-session checkpoint every 10 turns"
echo "  Slash commands: /${_BRAND_LOWER}-recall  /${_BRAND_LOWER}-save  /${_BRAND_LOWER}-checkpoint"
echo "  Cursor:  see ~/.cursor/rules for the $BRAND Memory section"
