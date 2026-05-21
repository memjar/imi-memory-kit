# IMI Memory — continued context for any AI coding session

One shared memory layer (`atlas.axe.observer`) that every teammate's model
reads at the start of a session and writes to at the end. Mike, Daniel —
anyone on the IMI team with a key — saves with their **own identity**, and
everyone on the team recalls the **shared IMI** context. Works in Claude Code,
Cursor, or any tool that can run a shell command. No fleet/server dependency.

```
recall ──► your model starts the session already knowing what the team decided
save   ──► what you figured out this session is there for the next one (anyone's)
```

Your saves land in the **IMI tenant** (`team/imi`) — separate from any other
team's memory. The pool is derived server-side from your key identity; you never
assert it from the client.

---

## Setup — one command (recommended)

```bash
IMI_API_KEY="bnk_...your personal key..." ./install.sh
```

That attaches the memory layer to your terminal **and** Claude Code in one shot:
it writes `~/.imi-memory.env` (your key + PATH + a per-session id, `chmod 600`),
sources it from your shell profile, installs the SessionStart auto-recall hook
into `~/.claude/settings.json`, and drops the protocol below into
`~/.claude/CLAUDE.md`. It's idempotent (safe to re-run) and `./install.sh
--uninstall` reverses everything. Open a new terminal (or `source
~/.imi-memory.env`), then `imi-memory recall`.

Ask James for your personal key (one per person, e.g. `imi-mike`). Your key
is your identity — every save is attributed to you; the installer keeps it in a
`chmod 600` file, not in your committed dotfiles.

### Manual setup (what `install.sh` does, if you'd rather wire it by hand)

1. Copy `imi-memory-kit/` somewhere on your machine.
2. Export your key + put the CLI on PATH in your shell profile:
   ```bash
   export IMI_API_KEY="bnk_...your personal key..."
   export PATH="$HOME/imi-memory-kit:$PATH"
   export AXE_SESSION_ID="$(uuidgen)"   # optional: per-session scoping
   ```
3. Wire it into your tool (pick yours below). `imi-memory whoami` should print
   your name.

---

## The protocol (drop this into your tool's rules file)

> **IMI Memory protocol.** This project shares continued context through the IMI
> memory layer.
> - **At the start of a task**, run `imi-memory recall` (or `imi-memory search
>   <keyword>` to focus) and treat the results as prior context.
> - **When you make a decision, learn something non-obvious, or finish a unit of
>   work**, persist it: `imi-memory save "<one or two sentences>" --kind decision`
>   (kinds: `decision`, `context`, `note`). Add `--tags area1,area2`.
> - Saves land in **your own space by default** (private to your sessions). To
>   share with the IMI team, add `--share`.
> - Save the *why* and the *outcome*, not a play-by-play. One good memory per
>   meaningful step beats ten noisy ones.

Paste that block into:
- **Claude Code** → your `CLAUDE.md` (project or `~/.claude/CLAUDE.md`).
- **Cursor** → `.cursorrules` (or `.cursor/rules/imi-memory.md`).
- **Windsurf / others** → that tool's rules/system-prompt file.

---

## Per-tool wiring

### Claude Code
Auto-recall at session start — add to `~/.claude/settings.json`:
```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [
        { "type": "command",
          "command": "/usr/local/bin/python3 ~/imi-memory-kit/hooks/session_start_memory.py" }
      ] }
    ]
  }
}
```
The hook injects fleet state + the latest IMI memories as `additionalContext`,
so the model starts every session already caught up. Saving happens via the
protocol block above (the model calls `imi-memory save`).

### Cursor / Windsurf / Cline
No SessionStart hook, so make recall the first agent step: keep the protocol
block in `.cursorrules`. The agent runs `imi-memory recall` in its terminal at
the start and `imi-memory save "..."` as it works.

### Any tool / raw (no CLI)
The whole thing is typed REST calls against `atlas.axe.observer` with your key:
```bash
# recall (your spaces + the shared IMI pool, newest first)
curl -s "https://atlas.axe.observer/api/memory/recall?limit=10" \
  -H "X-API-Key: $IMI_API_KEY"

# save (lands in YOUR space by default; add "share":true to share with IMI)
curl -s -X POST https://atlas.axe.observer/api/memory/save \
  -H "X-API-Key: $IMI_API_KEY" -H "Content-Type: application/json" \
  -d '{"content":"<text>","kind":"note","tags":["area"]}'

# search
curl -s "https://atlas.axe.observer/api/memory/search?q=campaign&k=10" \
  -H "X-API-Key: $IMI_API_KEY"
```

---

## CLI reference
```
imi-memory whoami                       # who am I (from my key)
imi-memory recall                       # my spaces + shared IMI pool (newest first)
imi-memory recall --mine                # only my own spaces
imi-memory recall --session ID          # scope to one session
imi-memory recall --limit 20            # more rows
imi-memory search "keyword"             # keyword search across what I can see
imi-memory save "..." --kind decision --tags pulse,segmentation  # → my space
imi-memory save "..." --share                                    # → IMI team pool
```
Spaces: saves default to `person/<you>` (private to your sessions); `team/imi`
is the shared IMI pool. `AXE_SESSION_ID` auto-stamps your saves so you can later
filter with `recall --session <id>`; plain `recall` stays broad (team + your
spaces) so a fresh session starts caught up.

## Identities (per-person keys)
Each teammate gets one key named `imi-<name>`; saves are attributed to that
name and grouped per person for the overseer. Mint a new one (admin):
```bash
curl -s -X POST https://atlas.axe.observer/api/keys \
  -H "X-API-Key: $ADMIN_KEY" -H "Content-Type: application/json" \
  -d '{"name":"imi-<name>","permissions":["read","write"]}'
# → returns the raw bnk_ key ONCE; hand it to that teammate.
```
Any key whose name contains `imi` (or is Mike/Daniel) lands in the `team/imi`
tenant automatically — that's how IMI memory stays separate from other teams'.

## How it works
Clients call typed endpoints — `POST /api/memory/save`, `GET /api/memory/recall`,
`GET /api/memory/search` — never raw SQL. The server resolves your identity
(principal) from your key and stamps each memory with a `space`
(`person/<you>` by default, `team/imi` to share), `principal`, and optional
`session_id`. Recall returns your spaces + the shared IMI pool, newest first;
`--mine` narrows to your spaces, `--session` to one session.

This is the **Step-0 seam** of the CASTLE memory plan: storage today is the
`events` table (`event_type='memory'`, zero schema change), but the client
contract (spaces / principal / session) is the final one — so it upgrades to
the governed `MemoryRecord` ontology entity with Rego + RLS isolation later
without changing how you use it. See
`axe-edge/docs/CASTLE_FOUNDRY_BLUEPRINT_ADDENDUM_memory_tenancy.md`.

**Today's limit:** partitioning is *scoping*, not yet *enforced isolation* — a
broad key can still read across spaces via the raw DB API. Hard isolation
(one teammate literally cannot read another's `person/` space) lands at CASTLE
Phase 3.
