#!/usr/bin/env bash
# Claude Code status line: show THIS conversation's context-window usage.
#
# Claude Code pipes a JSON payload into this script on stdin. Its
# `context_window` object is per-session (this chat) -- unlike the circular
# gauge in the app UI, which reports plan usage (5-hour / weekly windows).
#
# Install:  ~/.claude/install-statusline.sh
# Manual:   add to ~/.claude/settings.json
#   { "statusLine": { "type": "command",
#                     "command": "~/.claude/statusline-context.sh",
#                     "padding": 0 } }
#
# Output example:  ~/myrepo | Opus 5 | ctx |#######---| 68% (136.0k/200k)

set -uo pipefail

payload=$(cat)

# Fields, tab-separated: cwd, model, used, total, percent.
# jq is preferred; python3 and node are fallbacks so the script works on a
# machine with any one of the three.
have_parser=0
for candidate in jq python3 node; do
  if command -v "$candidate" >/dev/null 2>&1; then have_parser=1; break; fi
done

extract() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$payload" | jq -r '
      [ (.workspace.current_dir // ""),
        (.model.display_name // "?"),
        (.context_window.current_usage // 0),
        (.context_window.context_window_size // 0),
        (.context_window.used_percentage // 0)
      ] | @tsv' 2>/dev/null && return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$payload" | python3 -c '
import json,sys
d = json.load(sys.stdin)
c = d.get("context_window") or {}
print("\t".join(str(x) for x in [
    (d.get("workspace") or {}).get("current_dir", ""),
    (d.get("model") or {}).get("display_name", "?"),
    c.get("current_usage") or 0,
    c.get("context_window_size") or 0,
    c.get("used_percentage") or 0,
]))' 2>/dev/null && return 0
  fi
  if command -v node >/dev/null 2>&1; then
    printf '%s' "$payload" | node -e '
let s = "";
process.stdin.on("data", (d) => (s += d));
process.stdin.on("end", () => {
  const d = JSON.parse(s), c = d.context_window || {};
  process.stdout.write([
    (d.workspace || {}).current_dir || "",
    (d.model || {}).display_name || "?",
    c.current_usage || 0,
    c.context_window_size || 0,
    c.used_percentage || 0,
  ].join("\t") + "\n");
});' 2>/dev/null && return 0
  fi
  return 1
}

if ! fields=$(extract) || [ -z "$fields" ]; then
  # Never fail loudly: a broken status line would replace every prompt.
  if [ "$have_parser" -eq 0 ]; then
    echo "ctx n/a (needs jq, python3, or node)"
  else
    echo "ctx n/a"
  fi
  exit 0
fi

IFS=$'\t' read -r cwd model used total pct <<<"$fields"

short_cwd="$cwd"
[ -n "${HOME:-}" ] && short_cwd="${cwd/#$HOME/\~}"

int() { local n="${1%%.*}"; [[ "$n" =~ ^-?[0-9]+$ ]] && printf '%s' "$n" || printf '0'; }

total_i=$(int "$total")
if [ "$total_i" -le 0 ]; then
  # Builds before context_window was added to the payload land here.
  printf '%s | %s | ctx n/a\n' "$short_cwd" "$model"
  exit 0
fi

pct_i=$(int "$pct")
[ "$pct_i" -lt 0 ] && pct_i=0
[ "$pct_i" -gt 100 ] && pct_i=100

filled=$(( (pct_i + 5) / 10 ))
bar=""
for ((i = 1; i <= 10; i++)); do
  if [ "$i" -le "$filled" ]; then bar="${bar}█"; else bar="${bar}░"; fi
done

# Green while there is room, yellow as auto-compact approaches, red when close.
if   [ "$pct_i" -lt 60 ]; then colour=$'\033[32m'
elif [ "$pct_i" -lt 85 ]; then colour=$'\033[33m'
else                           colour=$'\033[31m'
fi
reset=$'\033[0m'
dim=$'\033[2m'

human() {
  awk -v n="$1" 'BEGIN {
    if (n >= 1000000)  { v = n / 1000000; u = "M" }
    else if (n >= 1000) { v = n / 1000;    u = "k" }
    else { printf "%d", n; exit }
    if (v == int(v)) printf "%d%s", v, u; else printf "%.1f%s", v, u
  }'
}

printf '%s%s | %s | %sctx %s %d%%%s %s(%s/%s)%s\n' \
  "$dim" "$short_cwd" "$model" \
  "$colour" "$bar" "$pct_i" "$reset" \
  "$dim" "$(human "$(int "$used")")" "$(human "$total_i")" "$reset"
