---
name: grepai-doctor
description: "Single entry point for the whole grepai stack: install, initialize, self-heal, and benchmark semantic code search in any repo. The trigger is BROKEN OR MISSING GREPAI — never silently fall back to plain grep. Use when: grepai search errors ('failed to load index', 'unexpected EOF'); search returns empty results in a repo that should be indexed; 'Watcher: not running'; grepai or ollama is not installed; setting up grepai in a fresh repo end-to-end; or deciding whether grep or grepai fits a task in this repo (bench mode measures both). Also use proactively the moment grepai misbehaves, before reaching for the Grep tool."
metadata:
  version: 1.0.0
---

# grepai doctor — install, heal, benchmark

grepai's worst failure mode is not the error itself — it's what agents do about it. When `grepai search` breaks (corrupted `index.gob` after a crash, dead watcher, missing model), the default agent behavior is a **silent fallback to plain grep**: semantic search and its ~96% token savings quietly disappear, and nobody notices for weeks. Healing takes one script call; this skill makes healing cheaper than falling back.

Everything runs through one idempotent script, `doctor.sh`, located **next to this SKILL.md**. No daemons, no launchd, no root. Run it from the target repo's root.

Three non-negotiable rules:

1. **Never fall back to grep silently.** If grepai errors, run the matching doctor mode first; use Grep only while a reindex is in flight, and come back.
2. **Trust `grepai watch --status`, never exit codes.** `watch --background` exits 1 with "timeout waiting for process to become ready after 30s" while the daemon is actually fine (large initial scans outlive the readiness window). And match the status line anchored — `^Status: running` — because a bare "running" grep also matches `Status: not running`.
3. **A bench verdict belongs in memory.** `.grepai/` is gitignored; measurements die with it. After `bench`, persist the numbers and the grep-vs-grepai rule to your agent memory.

## Which mode

| Symptom | Mode |
|---|---|
| `grepai: command not found` / no ollama / no model | `install` |
| Fresh repo, no `.grepai/` yet | `init` (runs install first) |
| `failed to load index` / `unexpected EOF` | `force` |
| Empty search results / watcher not running | `ensure` (default) |
| "Should I use grep or grepai here?" | `bench` |

```bash
bash <dir-of-this-SKILL.md>/doctor.sh [ensure|force|init|install|bench]
```

- `ensure` — exits instantly when healthy; otherwise sweeps truncated indexes (repo + all linked worktrees) and starts the background watcher. Safe as a SessionStart hook: exits silently in repos without `.grepai/`.
- `force` — stops the watcher (verifies it actually stopped — never wipes under a live one), deletes the vector index, full reindex.
- `init` — end-to-end for a new repo: install stack → `grepai init --yes` → watcher.
- `install` — grepai (brew tap or official install.sh) + ollama + `nomic-embed-text`; fails loudly on any missing piece.
- `bench` — times `git grep` vs `grepai search` on this repo (exact-symbol probe + natural-language queries), writes `.grepai/bench.md`, appends `grepai stats`.

## Verify after any healing mode

```bash
grepai status --no-ui   # Files indexed > 0, Watcher: running
```
Then one test search. A full reindex takes minutes (scales with repo size and embedder speed); status shows progress, and search works partially before it finishes.

## bench → agent memory

`bench` produces real per-repo numbers: exact-symbol queries (grep territory — fast, exhaustive, noisy) vs natural-language queries (grep finds ~0; grepai returns top-10 focused chunks). Persist the verdict so future sessions pick the right tool without re-measuring:

- exact identifiers, imports, string literals → `git grep` / Grep tool
- intent questions ("where is X handled") → `grepai search`
- before modifying a function → `grepai trace callers|callees <sym> --json`
- grepai errors → this skill, not a silent grep fallback

Include the repo name and measured numbers in the memory entry.

## Gotchas

- `.gitignore` is respected natively. For **extra** ignores use a committable `.grepaiignore` in the repo root (gitignore syntax, grepai ≥ 0.35). Ignores in `.grepai/config.yaml` work but are machine-local — they don't travel with the repo.
- The watcher auto-indexes **all linked git worktrees** (issue #211). If `watch.discover_worktrees` is available (PR #270), set it to `false` in the main worktree's config; otherwise prune stale worktrees (`git worktree remove` + `git worktree prune`) to cut RAM and index time.
- Corruption signature: `index.gob` under ~1 KB = truncated by a crash mid-write (issue #178). Versions with PR #269 self-heal on load (quarantine + atomic writes); for older versions the script sweeps truncated indexes. The sweep is harmless either way.
- `force` wipes only the vector index (`index.gob`); the symbol index (`symbols.gob`) is left alone on purpose — the watcher detects a corrupt one and rebuilds it in place.
- `install` starts `ollama serve` via nohup if it's down; on macOS the Ollama.app or `brew services start ollama` is the persistent option.
