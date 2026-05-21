# imi-memory-kit

Portable, attributed continued-context for the IMI team (Mike, Daniel) — works
in any AI coding session (Claude Code, Cursor, Windsurf, raw curl). One shared
memory layer (`atlas.axe.observer`); each teammate saves with their own
identity, gets a private space by default, and shares through the **IMI** team
pool (`team/imi`).

## Install (one command)
```bash
IMI_API_KEY="bnk_...your personal key..." ./install.sh
```
Attaches the memory layer to your terminal **and** Claude Code:
- writes `~/.imi-memory.env` (your key + PATH + a per-session id, `chmod 600`),
- sources it from your shell profile,
- installs the **SessionStart auto-recall hook** in `~/.claude/settings.json`,
- drops the recall/save **protocol** into `~/.claude/CLAUDE.md`.

Re-runnable (idempotent). `./install.sh --uninstall` removes all of it. Then
open a new terminal (or `source ~/.imi-memory.env`) and run `imi-memory recall`.

Ask James for your personal key (one per person, e.g. `imi-mike`).

## Files
| File | What |
|------|------|
| `kit.conf` | per-deployment branding (BRAND/CLI_NAME/ENV_FILE/MARKER) — the only file that differs from the AXE kit. |
| `install.sh` | one-command attach / `--uninstall`. |
| `imi-memory` | the CLI — `save` / `recall` / `search` / `whoami`. stdlib Python, no fleet deps. |
| `hooks/session_start_memory.py` | portable SessionStart hook (remote; injects continued context). |
| `IMI_MEMORY.md` | manual setup, the rules block, per-tool wiring (Cursor / raw curl), and what `install.sh` does under the hood. |

## CLI
```bash
imi-memory whoami
imi-memory recall                       # my spaces + shared IMI pool
imi-memory recall --mine --session ID   # narrow to me / one session
imi-memory search "keyword"
imi-memory save "..." --kind decision --tags pulse,segmentation   # → my space (private)
imi-memory save "..." --share                                     # → IMI team pool
```
Your **team pool** is derived from your key identity server-side (the IMI kit →
`team/imi`, the AXE kit → `team/axe`) — you never assert it from the client.

## Design
- **No fleet/server dependency.** Talks only to the remote typed endpoints
  (`/api/memory/{save,recall,search}`), so it runs from any teammate's machine.
- **Attributed + partitioned.** The server resolves your identity from your key
  and stamps each memory with a `space` — `person/<you>` by default (private to
  your sessions), `team/imi` to share. Recall returns your spaces + the IMI pool.
- **Step-0 seam.** Storage today is the `events` table (zero schema change), but
  the client contract is final — it upgrades to the governed `MemoryRecord`
  ontology entity (Rego + RLS isolation) per the CASTLE addendum without changing
  how you use it. Today partitioning is scoping, not yet enforced isolation.
- **Fail-closed.** No key or a bad key → nothing is written.

> Same engine as `axe-memory-kit`; only `kit.conf` and the doc branding differ.
> The IMI tenant (`team/imi`) is kept separate from the AXE tenant server-side.
