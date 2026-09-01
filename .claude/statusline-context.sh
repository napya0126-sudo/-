#!/usr/bin/env bash
# Claude Code status line: show this conversation's context-window usage.
#
# Claude Code pipes a JSON payload into this script on stdin. The
# `context_window` object in it is per-session (this chat), not the
# 5-hour/weekly plan usage shown by the usage gauge in the app UI.
#
# Install (user-level ~/.claude/settings.json):
#   { "statusLine": { "type": "command",
#                     "command": "~/.claude/statusline-context.sh" } }
#
# Output example:  ~/myrepo | opus | ctx ███████░░░ 68% (136.0k/200k)

set -uo pipefail

payload=$(cat)

read_fields() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$payload" | jq -r '
      [ (.workspace.current_dir // ""),
        (.model.display_name // ""),
        (.context_window.current_usage // 0),
        (.context_window.context_window_size // 0),
        (.context_window.used_percentage // 0)
      ] | @tsv'
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$payload" | python3 -c '
import json,sys
d=json.load(sys.stdin)
c=d.get("context_window") or {}
print("\t".join(str(x) for x in [
    (d.get("workspace") or {}).get("current_dir",""),
    (d.get("model") or {}).get("display_name",""),
    c.get("current_usage",0) or 0,
    c.get("context_window_size",0) or 0,
    c.get("used_percentage",0) or 0,
]))'
  else
    return 1
  fi
}

fields=$(read_fields) || { echo "ctx n/a (install jq or python3)"; exit 0; }
IFS=$'\t' read -r cwd model used total pct <<<"$fields"

# Older Claude Code builds do not send context_window at all.
if [ "${total%%.*}" -le 0 ] 2>/dev/null || [ -z "${total:-}" ]; then
  printf '%s | %s | ctx n/a\n' "${cwd/#$HOME/\~}" "$model"
  exit 0
fi

pct_int=${pct%%.*}
[ -z "$pct_int" ] && pct_int=0
[ "$pct_int" -gt 100 ] && pct_int=100

# 10-cell bar
filled=$(( (pct_int + 5) / 10 ))
bar=""
for i in $(seq 1 10); do
  if [ "$i" -le "$filled" ]; then bar="${bar}█"; else bar="${bar}░"; fi
done

# Colour by how full the window is: green < 60%, yellow < 85%, red above.
if   [ "$pct_int" -lt 60 ]; then colour=$'\033[32m'
elif [ "$pct_int" -lt 85 ]; then colour=$'\033[33m'
else                             colour=$'\033[31m'
fi
reset=$'\033[0m'
dim=$'\033[2m'

human() { awk -v n="$1" 'BEGIN{ if (n>=1000) printf "%.1fk", n/1000; else printf "%d", n }'; }

printf '%s%s | %s | %sctx %s %d%%%s %s(%s/%s)%s\n' \
  "$dim" "${cwd/#$HOME/\~}" "$model" \
  "$colour" "$bar" "$pct_int" "$reset" \
  "$dim" "$(human "$used")" "$(human "$total")" "$reset"
