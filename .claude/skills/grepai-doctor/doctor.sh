#!/bin/bash
# grepai-doctor: install, heal, and benchmark grepai in the current repo. Idempotent. No daemons, no root.
# usage: doctor.sh [ensure|force|init|install|bench]
#   ensure (default) — if watcher is down: sweep truncated indexes, start background watcher
#   force            — stop watcher, wipe vector indexes, full reindex (for "unexpected EOF" corruption)
#   init             — end-to-end for a new repo: install stack, grepai init --yes, start watcher
#   install          — install grepai (brew or install.sh) + ollama + embedding model, nothing else
#   bench            — measure grep vs grepai on THIS repo's index, write .grepai/bench.md
set -u
MODE="${1:-ensure}"
have() { command -v "$1" >/dev/null 2>&1; }
# `grepai watch --status` prints "Status: not running" when down — anchor the
# match, a bare "running" grep would match both states.
watcher_running() { grepai watch --status 2>/dev/null | grep -q '^Status: running'; }

install_all() {
    if ! have grepai; then
        if have brew; then brew install yoanbernabeu/tap/grepai
        else curl -sSL https://raw.githubusercontent.com/yoanbernabeu/grepai/main/install.sh | sh; fi
        have grepai || { echo "grepai install failed — see https://github.com/yoanbernabeu/grepai"; exit 1; }
    fi
    if ! have ollama; then
        if have brew; then brew install ollama; fi
        have ollama || { echo "install ollama manually: https://ollama.com/download"; exit 1; }
    fi
    if ! curl -s --max-time 2 http://localhost:11434/api/tags >/dev/null; then
        nohup ollama serve >/dev/null 2>&1 &
        for _ in 1 2 3 4 5; do sleep 1; curl -s --max-time 2 http://localhost:11434/api/tags >/dev/null && break; done
        curl -s --max-time 2 http://localhost:11434/api/tags >/dev/null \
            || { echo "ollama API not reachable at localhost:11434 — start it manually (ollama serve)"; exit 1; }
    fi
    if ! ollama list 2>/dev/null | grep -q nomic-embed-text; then
        ollama pull nomic-embed-text || { echo "failed to pull nomic-embed-text"; exit 1; }
    fi
}

# time a command, print bash `real` time (e.g. 0m0.042s)
t() { { time "$@" >/dev/null 2>&1; } 2>&1 | awk '/^real/{print $2}'; }

# intent sentence -> OR-pattern of stemmed content words, i.e. the grep a
# skilled agent would actually type (never benchmark literal sentences).
kw() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cs '[:lower:]' '\n' \
      | grep -vwE 'the|and|are|is|how|where|what|when|why|to|of|in|on|for|a|an|be|by|with|that|this|it|its' \
      | sed -E 's/(es|ed|ing|s)$//; s/(.)\1$/\1/' | awk 'length>=3' | sort -u | paste -sd'|' -
}

bench() {
    [ -d .grepai ] || { echo "no .grepai here — run: doctor.sh init"; exit 1; }
    grepai search "warmup" --json >/dev/null 2>&1   # load embedding model before timing
    HITS=$(grepai search "warmup" --json --compact 2>/dev/null | grep -c '"file_path"')
    [ "$HITS" -gt 0 ] || { echo "index empty or still building — check: grepai status --no-ui"; exit 1; }

    # exact-identifier probe: most common symbol defined in CODE files (grep's
    # home turf). Restricted to code extensions so prose in docs can't win.
    # no \b: git grep -E is POSIX ERE, word boundaries unsupported on macOS
    SYM=$(git grep -hoE '(func|function|def|fn|class|struct|interface) [A-Za-z_][A-Za-z0-9_]{3,}' \
              -- '*.go' '*.py' '*.js' '*.ts' '*.tsx' '*.jsx' '*.swift' '*.rs' '*.java' '*.kt' '*.c' '*.cc' '*.cpp' '*.h' '*.rb' '*.php' '*.cs' 2>/dev/null \
          | awk '{print $2}' | sort | uniq -c | sort -rn | awk 'NR==1{print $2}')
    OUT=.grepai/bench.md
    {
        echo "# grep vs grepai — $(basename "$PWD"), $(date +%F)"
        echo
        echo "| query | kind | git grep | grepai search |"
        echo "|---|---|---|---|"
        if [ -n "$SYM" ]; then
            G_T=$(t git grep -In -e "$SYM"); G_N=$(git grep -Inc -e "$SYM" 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')
            A_T=$(t grepai search "$SYM" --json --compact); A_N=$(grepai search "$SYM" --json --compact 2>/dev/null | grep -c '"file_path"')
            echo "| \`$SYM\` | exact symbol | $G_N hits, $G_T | $A_N hits, $A_T |"
        fi
        for Q in "where errors are handled and logged" "how configuration is loaded and validated" "the main entry point and startup flow"; do
            PAT=$(kw "$Q")
            # keyword-decomposed grep = what an agent would really type; exclude
            # this script's own committed copy (it contains these phrases)
            G_T=$(t git grep -inE "$PAT" -- ':(exclude)*doctor.sh'); G_N=$(git grep -inE "$PAT" -- ':(exclude)*doctor.sh' 2>/dev/null | wc -l | tr -d ' ')
            A_T=$(t grepai search "$Q" --json --compact); A_N=$(grepai search "$Q" --json --compact 2>/dev/null | grep -c '"file_path"')
            echo "| \"$Q\" -> \`$PAT\` | intent vs keyword grep | $G_N lines, $G_T | $A_N chunks, $A_T |"
        done
        echo
        echo "Verdict: exact identifiers/strings -> git grep (fastest, exhaustive)."
        echo "Intent questions -> grepai: ~10 scored chunks in ONE call; keyword grep"
        echo "returns the raw line volume above to triage and usually needs several"
        echo "refinement rounds. (Literal full-sentence grep finds ~0 — that is a"
        echo "strawman, never benchmark or argue with it.)"
        echo "If grepai's top hits are docs/reports instead of code: scope with"
        echo "--path <srcdir>, or add a .grepaiignore for generated content."
        echo "grep also wins while the index is cold/broken; run doctor.sh to heal."
        grepai stats 2>/dev/null | sed 's/^/> /'
    } | tee "$OUT"
    echo; echo "saved -> $OUT"
}

case "$MODE" in
    install) install_all; echo "install: OK ($(grepai version 2>/dev/null))"; exit 0 ;;
    bench)   bench; exit 0 ;;
    init)    install_all
             if [ ! -d .grepai ]; then
                 grepai init --yes || { echo "grepai init failed"; exit 1; }
                 [ -d .grepai ] || { echo "grepai init did not create .grepai"; exit 1; }
             fi ;;
    ensure|force) have grepai || { echo "grepai not installed — run: doctor.sh install"; exit 1; } ;;
    *)       echo "usage: doctor.sh [ensure|force|init|install|bench]"; exit 2 ;;
esac
[ -d .grepai ] || exit 0   # repo hasn't opted into grepai — do nothing (hook safety)

if [ "$MODE" = "force" ]; then
    grepai watch --stop 2>/dev/null
    # never wipe under a live watcher — it could rewrite the index mid-delete
    watcher_running && { echo "watcher still running after --stop — aborting wipe"; exit 1; }
    SIZE_FILTER=""          # wipe everything → full reindex
else
    watcher_running && exit 0   # healthy, done
    # ponytail: <1KB index.gob = truncated by a crash. Byte units: GNU find
    # rounds -1k UP to whole units (matches only 0-byte files); -1024c is
    # exact on both BSD and GNU.
    SIZE_FILTER="-size -1024c"
fi

# sweep main repo + all linked worktrees (watcher indexes them all)
{ git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p'; echo "."; } | sort -u | \
while IFS= read -r root; do
    [ -d "$root/.grepai" ] || continue
    # shellcheck disable=SC2086  # SIZE_FILTER intentionally unquoted (empty in force mode)
    find "$root/.grepai" -maxdepth 1 -name index.gob $SIZE_FILTER -delete 2>/dev/null
    find "$root/.grepai" -maxdepth 1 -name '*.lock' -delete 2>/dev/null
done

# --background exits 1 with "timeout waiting for process to become ready" when the
# initial scan outlives its 30s readiness window — the daemon is fine; trust --status.
grepai watch --background 2>/dev/null
sleep 2
if watcher_running; then
    echo "watcher: running (index builds in background — grepai status --no-ui)"
else
    echo "watcher failed to start — check: grepai watch --status (prints the log path)"
    exit 1
fi
