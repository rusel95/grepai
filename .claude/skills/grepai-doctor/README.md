# grepai-doctor

Agent skill: the single entry point for the whole [grepai](https://github.com/yoanbernabeu/grepai) stack — **install → init → self-heal → benchmark** — so your AI coding agent fixes a broken semantic search instead of silently falling back to plain grep.

One idempotent bash script (`doctor.sh`), no daemons, no launchd, no root. Works with any agent that reads `SKILL.md` (Claude Code, Cursor, Codex, Windsurf, …).

## Install

With [`skills`](https://skills.sh) (recommended — picks the right directory for every agent you use):

```bash
# project-level (this repo only)
npx skills add yoanbernabeu/grepai --skill grepai-doctor

# or user-level (all your projects)
npx skills add yoanbernabeu/grepai --skill grepai-doctor -g
```

Useful flags: `-a '*'` installs for every detected agent, `--copy` copies instead of symlinking, `-l` lists available skills without installing.

Manual (Claude Code example):

```bash
git clone --depth 1 https://github.com/yoanbernabeu/grepai /tmp/grepai-skill
cp -r /tmp/grepai-skill/.claude/skills/grepai-doctor ~/.claude/skills/
```

Working **inside the grepai repo itself**? Claude Code picks the skill up automatically from `.claude/skills/`. For other agents (Cursor, Codex, ...), install it into their directories from the repo root:

```bash
npx skills add . --skill grepai-doctor -a '*'
```

## What it does

| You say / agent sees | Mode | Effect |
|---|---|---|
| `grepai: command not found`, no ollama/model | `install` | grepai (brew tap / install.sh) + ollama + `nomic-embed-text` |
| fresh repo, no `.grepai/` | `init` | full stack install → `grepai init --yes` → background watcher |
| `failed to load index` / `unexpected EOF` | `force` | stop watcher → wipe vector index → full reindex |
| empty results / watcher down | `ensure` (default) | sweep truncated indexes (repo + linked worktrees), restart watcher |
| "grep or grepai here?" | `bench` | times `git grep` vs `grepai search` on *your* repo → `.grepai/bench.md` |

```bash
bash .claude/skills/grepai-doctor/doctor.sh [ensure|force|init|install|bench]
```

`ensure` exits instantly when everything is healthy, and exits silently in repos without `.grepai/` — safe to wire into a session-start hook.

## Why

When grepai breaks, agents don't report it — they quietly switch to plain grep, and semantic search (with its ~96% token savings per [`grepai stats`](https://github.com/yoanbernabeu/grepai)) disappears unnoticed. The skill makes healing a one-liner and teaches the agent when each tool actually wins: exact identifiers → grep; intent questions ("where is X handled") → grepai — with `bench` producing the per-repo numbers to prove it.

## Verify

```bash
grepai status --no-ui   # Files indexed > 0, Watcher: running
grepai search "error handling"
```

Full agent instructions, mode selection table, and gotchas (worktrees, corruption signatures, exit-code quirks): [SKILL.md](SKILL.md).
