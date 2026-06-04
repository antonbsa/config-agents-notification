write_ai_notify() {
  log "Installing common notification helper: $AI_NOTIFY"
  write_rendered_template "ai-notify.sh" "$AI_NOTIFY"
  bash -n "$AI_NOTIFY"
}

write_claude_filter() {
  log "Installing Claude notification handler: $CLAUDE_FILTER"
  write_rendered_template "claude-notify-filter.py" "$CLAUDE_FILTER"
  python3 -m py_compile "$CLAUDE_FILTER"
}

update_claude_settings() {
  log "Updating Claude settings JSON: $CLAUDE_SETTINGS"
  if [[ ! -f "$CLAUDE_SETTINGS" ]]; then
    printf '{}\n' > "$CLAUDE_SETTINGS"
  else
    backup_file "$CLAUDE_SETTINGS"
  fi

  local tmp hooks_tmp
  tmp="$(mktemp "${CLAUDE_SETTINGS}.tmp.XXXXXX")"
  hooks_tmp="$(mktemp "${CLAUDE_SETTINGS}.hooks.XXXXXX")"
  render_template "claude-settings-hooks.json" > "$hooks_tmp"

  python3 - "$CLAUDE_SETTINGS" "$tmp" "$hooks_tmp" <<'PY'
import json
import sys
from pathlib import Path

settings_path = Path(sys.argv[1])
tmp_path = Path(sys.argv[2])
hooks_path = Path(sys.argv[3])

try:
    with settings_path.open("r", encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    data = {}

if not isinstance(data, dict):
    data = {}

with hooks_path.open("r", encoding="utf-8") as f:
    managed_hooks = json.load(f)

hooks = data.setdefault("hooks", {})
if not isinstance(hooks, dict):
    hooks = {}
    data["hooks"] = hooks

for name, value in managed_hooks.items():
    hooks[name] = value

with tmp_path.open("w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY

  python3 -m json.tool "$tmp" >/dev/null
  mv "$tmp" "$CLAUDE_SETTINGS"
  rm -f "$hooks_tmp"
}
