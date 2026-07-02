---
name: grepai-doctor
description: Install, fix, or benchmark grepai semantic search in any repo — the single entry point for the whole grepai stack. Use when grepai search errors ("failed to load index", "unexpected EOF"), returns empty results, "Watcher - not running", when grepai/ollama isn't installed, to set up a fresh repo end-to-end, or to measure where grep beats grepai on a project.
---

# grepai doctor

One idempotent script — install → init → heal → benchmark. No daemons/launchd/root. Run from the repo root:

```bash
bash "$(dirname "$0")/doctor.sh"          # ensure: start watcher if down, sweep truncated indexes
bash "$(dirname "$0")/doctor.sh" force    # corruption: stop watcher, wipe indexes, full reindex
bash "$(dirname "$0")/doctor.sh" init     # new repo end-to-end: install stack + grepai init + watcher
bash "$(dirname "$0")/doctor.sh" install  # just install grepai + ollama + nomic-embed-text model
bash "$(dirname "$0")/doctor.sh" bench    # measure grep vs grepai HERE, writes .grepai/bench.md
```

(Resolve the script path relative to this SKILL.md's directory.)

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
Then one test search. Full reindex takes ~5–10 min for ~350 files — status shows progress; search works partially before it finishes.

## bench → agent memory (do this after bench)

`bench` writes real numbers for THIS repo to `.grepai/bench.md`: exact-symbol query (grep territory) vs natural-language queries (grep finds ~0 there). After running it, **persist the verdict in your memory** so future sessions pick the right tool without re-measuring, e.g.:

- exact identifiers, imports, string literals → `git grep` / Grep tool (ms, exhaustive)
- intent / "where is X handled" questions → `grepai search` (grep literally returns 0)
- `grepai trace callers|callees` before modifying any function
- if grepai errors → run this skill, don't fall back silently

Include the repo name and the measured numbers in the memory entry. `.grepai/` is not committed — the memory is what survives.

## Gotchas

- `.gitignore` is respected natively. For **extra** ignores use a `.grepaiignore` in the repo root (gitignore syntax, grepai ≥ 0.35) — it's committable and survives restarts. Do NOT put custom ignores in `.grepai/config.yaml`: grepai rewrites it on restart and it's gitignored.
- The watcher auto-indexes **all linked git worktrees** (issue #211). If `watch.discover_worktrees` is available (PR #270), set it to `false` in the main worktree's config; otherwise prune stale worktrees (`git worktree remove` + `git worktree prune`) to cut RAM and index time.
- Corruption signature: `index.gob` under ~1 KB = truncated by a crash mid-write (issue #178). Versions with PR #269 self-heal on load (quarantine to `.corrupt` + atomic writes); for older versions the script sweeps truncated indexes automatically. The sweep is harmless either way.
- Optional auto-heal on session start (Claude Code): add a `SessionStart` hook running `doctor.sh` — it exits instantly when the repo has no `.grepai/`.
- `install` starts `ollama serve` via nohup if it's down; on macOS the Ollama.app or `brew services start ollama` is the persistent option.
