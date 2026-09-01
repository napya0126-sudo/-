#!/usr/bin/env bash
# Install statusline-context.sh as the Claude Code status line.
#
# Copies the script to ~/.claude/ and merges the `statusLine` key into
# ~/.claude/settings.json, keeping every other setting intact and writing a
# timestamped backup first.
#
# `statusLine` is a trusted-config key, so it belongs in USER settings
# (~/.claude/settings.json), not project settings.
#
# Usage:  ./.claude/install-statusline.sh [--uninstall]

set -euo pipefail

src_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
script_src="$src_dir/statusline-context.sh"
claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
script_dst="$claude_dir/statusline-context.sh"
settings="$claude_dir/settings.json"

uninstall=0
[ "${1:-}" = "--uninstall" ] && uninstall=1

if [ "$uninstall" -eq 0 ] && [ ! -f "$script_src" ]; then
  echo "error: $script_src not found" >&2
  exit 1
fi

mkdir -p "$claude_dir"
[ -f "$settings" ] || echo '{}' > "$settings"

if ! python3 -c '' >/dev/null 2>&1 && ! command -v node >/dev/null 2>&1; then
  echo "error: need python3 or node to edit settings.json safely" >&2
  exit 1
fi

backup="$settings.bak.$(date +%Y%m%d%H%M%S).$$"
cp "$settings" "$backup"

edit_settings() {
  if python3 -c '' >/dev/null 2>&1; then
    python3 - "$settings" "$1" "$uninstall" <<'PY'
import json, sys
path, command, uninstall = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
with open(path) as f:
    text = f.read().strip() or "{}"
try:
    data = json.loads(text)
except json.JSONDecodeError as e:
    sys.exit(f"error: {path} is not valid JSON ({e}); left unchanged")
if not isinstance(data, dict):
    sys.exit(f"error: {path} is not a JSON object; left unchanged")
if uninstall:
    data.pop("statusLine", None)
else:
    data["statusLine"] = {"type": "command", "command": command, "padding": 0}
    if data.get("disableAllHooks") is True:
        print("warning: disableAllHooks is true -- the status line will not run")
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
  else
    node - "$settings" "$1" "$uninstall" <<'JS'
const fs = require("fs");
const [path, command, uninstall] = process.argv.slice(2);
let data;
try {
  data = JSON.parse(fs.readFileSync(path, "utf8").trim() || "{}");
} catch (e) {
  console.error(`error: ${path} is not valid JSON (${e.message}); left unchanged`);
  process.exit(1);
}
if (data === null || typeof data !== "object" || Array.isArray(data)) {
  console.error(`error: ${path} is not a JSON object; left unchanged`);
  process.exit(1);
}
if (uninstall === "1") {
  delete data.statusLine;
} else {
  data.statusLine = { type: "command", command, padding: 0 };
  if (data.disableAllHooks === true) {
    console.log("warning: disableAllHooks is true -- the status line will not run");
  }
}
fs.writeFileSync(path, JSON.stringify(data, null, 2) + "\n");
JS
  fi
}

if [ "$uninstall" -eq 1 ]; then
  edit_settings ""
  rm -f "$script_dst"
  echo "uninstalled: statusLine removed from $settings (backup: $backup)"
  exit 0
fi

cp "$script_src" "$script_dst"
chmod +x "$script_dst"

# Claude Code expands a leading ~ in the command, and the literal keeps the
# settings file portable between machines.
edit_settings "~/.claude/statusline-context.sh"

echo "installed: $script_dst"
echo "settings:  $settings (backup: $backup)"
echo
echo "Preview:"
printf '  '
printf '%s' '{"workspace":{"current_dir":"'"$PWD"'"},"model":{"display_name":"Opus 5"},"context_window":{"current_usage":136000,"context_window_size":200000,"used_percentage":68}}' \
  | "$script_dst"
echo
echo "Restart Claude Code (or start a new session) to pick it up."
