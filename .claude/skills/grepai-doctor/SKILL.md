---
name: grepai-doctor
description: "Single entry point for the whole grepai stack: install, initialize, self-heal, and benchmark semantic code search in any repo. The trigger is BROKEN OR MISSING GREPAI — never switch search tools silently. Use when: grepai search errors ('failed to load index', 'unexpected EOF'); search returns empty results in a repo that should be indexed; 'Watcher: not running'; grepai or ollama is not installed; setting up grepai in a fresh repo end-to-end; or deciding whether grep or grepai fits a task in this repo (bench mode measures both). Also use proactively the moment grepai misbehaves — heal it or switch to grep explicitly, never silently."
metadata:
  version: 1.0.0
---

# grepai doctor — install, heal, benchmark

grepai's worst failure mode is not the error itself — it's the **silent tool switch**. When `grepai search` breaks (corrupted `index.gob` after a crash, dead watcher, missing model), agents quietly degrade to ad-hoc grep without telling anyone, and the repo's chosen search setup stays broken for weeks. Silence is bad in both directions: silently abandoning a broken tool, and silently over-trusting a working one (grepai's top-10 is a ranking that can miss files — see the bench section). This skill makes the state visible and the fix one call: heal grepai when it's broken, and choose grep vs grepai per task on measured numbers.

Everything runs through one idempotent script, `doctor.sh`, located **next to this SKILL.md**. No daemons, no launchd, no root. Run it from the target repo's root.

Three non-negotiable rules:

1. **Never switch search tools silently.** If grepai errors, run the matching doctor mode and say so. Choosing Grep deliberately (exact identifiers, syntax anchors, recall-critical checks — see the bench section) is a valid measured decision, not a fallback to hide.
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
- `bench` — measures `git grep` vs `grepai search` on this repo (exact-symbol probe + keyword-decomposed intent queries): hit counts, line/file volumes, timings. It measures **volume and speed, not per-query relevance** — grepai's top-10 can still miss files keyword grep finds (see 'bench → agent memory'). Writes `.grepai/bench.md`, appends `grepai stats`.

## Verify after any healing mode

```bash
grepai status --no-ui   # Files indexed > 0, Watcher: running
```
Then one test search. A full reindex takes minutes (scales with repo size and embedder speed); status shows progress, and search works partially before it finishes.

## bench → agent memory

`bench` produces real per-repo numbers, and it compares **fairly**: the exact-symbol row is grep's home turf, and the intent rows pit grepai against *keyword-decomposed* grep (stemmed OR-pattern — what a skilled agent would actually type), NOT against a literal full-sentence grep. Literal-sentence grep trivially finds 0 and proves nothing; if you see that comparison anywhere, treat it as a strawman. Token-savings figures from `grepai stats` are also measured against naive grep dumps — quote them as such, not as "grep can't do this".

One more honesty caveat: the bench measures **volume** (chunks vs lines), not **relevance**. grepai's top-10 is a ranking, not an exhaustive result set — measured on real repos it can miss ground-truth files that keyword grep finds trivially. The rule that saves tokens *without losing recall*:

- exact identifiers, imports, string literals, syntax anchors (`@main`, `func main(`) → `git grep` / Grep tool (fastest, exhaustive; many "intent" questions are anchor queries in disguise)
- intent questions ("where is X handled") → the **recall-safe combo**: `grepai search --json --compact` for ~10 ranked chunks **plus** `git grep -ilE 'kw1|kw2'` for the exhaustive candidate file list (names only — grep's full recall at ~1% of a content dump). Read ranked hits first, then relevant-looking checklist files grepai didn't rank. Never dump full grep content for an intent query, and never treat grepai top-10 as complete coverage.
- before modifying a function → `grepai trace callers|callees <sym> --json`
- grepai errors → this skill, not a silent grep fallback

Include the repo name and the measured numbers (line volumes, timings) in the memory entry.

## Gotchas

- `.gitignore` is respected natively. For **extra** ignores use a committable `.grepaiignore` in the repo root (gitignore syntax, grepai ≥ 0.35). Ignores in `.grepai/config.yaml` work but are machine-local — they don't travel with the repo.
- If search results are polluted by docs/reports/generated markdown instead of code: scope the query with `grepai search "<q>" --path <srcdir>`, or add those files to `.grepaiignore`. This is the most common cause of "grepai found nothing useful" in repos with lots of prose.
- The watcher auto-indexes **all linked git worktrees** (issue #211). If `watch.discover_worktrees` is available (PR #270), set it to `false` in the main worktree's config; otherwise prune stale worktrees (`git worktree remove` + `git worktree prune`) to cut RAM and index time.
- Corruption signature: `index.gob` under ~1 KB = truncated by a crash mid-write (issue #178). Versions with PR #269 self-heal on load (quarantine + atomic writes); for older versions the script sweeps truncated indexes. The sweep is harmless either way.
- `force` wipes only the vector index (`index.gob`); the symbol index (`symbols.gob`) is left alone on purpose — the watcher detects a corrupt one and rebuilds it in place.
- `install` starts `ollama serve` via nohup if it's down; on macOS the Ollama.app or `brew services start ollama` is the persistent option.
