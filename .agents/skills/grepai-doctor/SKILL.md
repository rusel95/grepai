---
name: grepai-doctor
description: Install, fix, or benchmark grepai semantic search in any repo — the single entry point for the whole grepai stack. Use when grepai search errors ("failed to load index", "unexpected EOF"), returns empty results, "Watcher: not running", when grepai/ollama isn't installed, to set up a fresh repo end-to-end, or to measure where grep beats grepai on a project.
---

# grepai doctor

One idempotent script — install → init → heal → benchmark. No daemons/launchd/root. `doctor.sh` lives next to this SKILL.md; run it from the target repo's root:

```bash
bash /path/to/skill-dir/doctor.sh          # ensure: start watcher if down, sweep truncated indexes
bash /path/to/skill-dir/doctor.sh force    # corruption: stop watcher, wipe vector index, full reindex
bash /path/to/skill-dir/doctor.sh init     # new repo end-to-end: install stack + grepai init + watcher
bash /path/to/skill-dir/doctor.sh install  # just install grepai + ollama + nomic-embed-text model
bash /path/to/skill-dir/doctor.sh bench    # measure grep vs grepai HERE, writes .grepai/bench.md
```

## Which mode

| Symptom | Mode |
|---|---|
| `grepai: command not found` / no ollama / no model | `install` |
| Fresh repo, no `.grepai/` yet | `init` (runs install first) |
| `failed to load index` / `unexpected EOF` | `force` |
| Empty search results / watcher not running | default (`ensure`) |
| "Should I use grep or grepai here?" | `bench` |

## Verify after running

```bash
grepai status --no-ui   # Files indexed > 0, Watcher: running
```
Then one test search. A full reindex takes minutes (scales with repo size and embedder speed) — status shows progress; search works partially before it finishes.

## bench → agent memory (do this after bench)

`bench` writes real numbers for THIS repo to `.grepai/bench.md`: exact-symbol query (grep territory) vs natural-language queries (grep finds ~0 there). After running it, **persist the verdict in your memory** so future sessions pick the right tool without re-measuring, e.g.:

- exact identifiers, imports, string literals → `git grep` / Grep tool (ms, exhaustive)
- intent / "where is X handled" questions → `grepai search` (grep literally returns 0)
- `grepai trace callers|callees` before modifying any function
- if grepai errors → run this skill, don't fall back silently

Include the repo name and the measured numbers in the memory entry. `.grepai/` is not committed — the memory is what survives.

## Gotchas

- `.gitignore` is respected natively. For **extra** ignores use a `.grepaiignore` in the repo root (gitignore syntax, grepai ≥ 0.35) — it's committable and portable. Custom ignores in `.grepai/config.yaml` work too, but that file is gitignored and machine-local, so they don't travel with the repo.
- The watcher auto-indexes **all linked git worktrees** (issue #211). If `watch.discover_worktrees` is available (PR #270), set it to `false` in the main worktree's config; otherwise prune stale worktrees (`git worktree remove` + `git worktree prune`) to cut RAM and index time.
- Corruption signature: `index.gob` under ~1 KB = truncated by a crash mid-write (issue #178). Versions with PR #269 self-heal on load (quarantine to `.corrupt` + atomic writes); for older versions the script sweeps truncated indexes automatically. The sweep is harmless either way.
- `force` wipes only the vector index (`index.gob`); the symbol index (`symbols.gob`) is left alone on purpose — the watcher detects a corrupt one and rebuilds it in place.
- Optional auto-heal on session start (Claude Code): add a `SessionStart` hook running `doctor.sh` — it exits instantly when the repo has no `.grepai/`.
- `install` starts `ollama serve` via nohup if it's down; on macOS the Ollama.app or `brew services start ollama` is the persistent option.
