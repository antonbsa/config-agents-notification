#!/usr/bin/env bash
set -euo pipefail

# Idempotent installer for Codex CLI and Claude Code desktop notifications.

HOME_DIR="${HOME}"
LOCAL_BIN="${HOME_DIR}/.local/bin"
CODEX_DIR="${HOME_DIR}/.codex"
CODEX_HOOKS_DIR="${CODEX_DIR}/hooks"
CLAUDE_DIR="${HOME_DIR}/.claude"

AI_NOTIFY="${LOCAL_BIN}/ai-notify"
CLAUDE_FILTER="${LOCAL_BIN}/claude-notify-filter"
CODEX_NOTIFY="${CODEX_HOOKS_DIR}/notify.sh"
CLAUDE_SETTINGS="${CLAUDE_DIR}/settings.json"
CODEX_CONFIG="${CODEX_DIR}/config.toml"
CODEX_LOG="${CODEX_DIR}/notify.log"

RUN_TESTS=0

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--test] [--help]

Options:
  --test     Run notification tests against an existing installation.
  --help     Show this help message.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --test) RUN_TESTS=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

log() { printf '[ai-notifications] %s\n' "$*"; }
warn() { printf '[ai-notifications][warn] %s\n' "$*" >&2; }
fail() { printf '[ai-notifications][error] %s\n' "$*" >&2; exit 1; }

confirm() {
  local prompt="$1"
  local reply

  while true; do
    printf '%s (Y/n) ' "$prompt"
    IFS= read -r reply || fail "Could not read user confirmation."

    case "$reply" in
      ""|[Yy]|[Yy][Ee][Ss]|[Ss]|[Ss][Ii][Mm]) return 0 ;;
      [Nn]|[Nn][Oo]) return 1 ;;
      *) warn "Please answer y or n." ;;
    esac
  done
}

collect_missing_dependencies() {
  REQUIRED_MISSING=()
  OPTIONAL_MISSING=()

  command -v notify-send >/dev/null 2>&1 || REQUIRED_MISSING+=(libnotify-bin)
  command -v jq >/dev/null 2>&1 || REQUIRED_MISSING+=(jq)
  command -v python3 >/dev/null 2>&1 || REQUIRED_MISSING+=(python3)
  command -v paplay >/dev/null 2>&1 || OPTIONAL_MISSING+=(pulseaudio-utils)
}

print_install_summary() {
  collect_missing_dependencies

  cat <<SUMMARY
This installer will:
- Install missing Ubuntu packages when needed: libnotify-bin, jq, python3, pulseaudio-utils.
- Create required directories: $LOCAL_BIN, $CODEX_HOOKS_DIR, $CLAUDE_DIR.
- Install or replace notification helpers:
  - $AI_NOTIFY
  - $CLAUDE_FILTER
  - $CODEX_NOTIFY
- Update Claude settings: $CLAUDE_SETTINGS
- Update Codex config: $CODEX_CONFIG

SUMMARY

  if [[ ${#REQUIRED_MISSING[@]} -eq 0 && ${#OPTIONAL_MISSING[@]} -eq 0 ]]; then
    log "All dependencies are already available."
  else
    [[ ${#REQUIRED_MISSING[@]} -gt 0 ]] && warn "Missing required packages: ${REQUIRED_MISSING[*]}"
    [[ ${#OPTIONAL_MISSING[@]} -gt 0 ]] && warn "Missing optional package: ${OPTIONAL_MISSING[*]}"
  fi
}

confirm_installation() {
  print_install_summary
  confirm "Continue installation?" || fail "Installation cancelled by user."
}

confirm_existing_configs() {
  local existing=()

  [[ -f "$CLAUDE_SETTINGS" ]] && existing+=("$CLAUDE_SETTINGS")
  [[ -f "$CODEX_CONFIG" ]] && existing+=("$CODEX_CONFIG")

  [[ ${#existing[@]} -eq 0 ]] && return 0

  warn "Existing configuration files were found and will be backed up before they are updated:"
  printf '  - %s\n' "${existing[@]}" >&2
  confirm "Overwrite/update existing configuration files?" || fail "Installation cancelled by user."
}

backup_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  local ts backup
  ts="$(date +%Y%m%d%H%M%S)"
  backup="${file}.bak.${ts}"
  cp -p "$file" "$backup"
  log "Backup created: $backup"
}

atomic_write() {
  local target="$1"
  local tmp
  tmp="$(mktemp "${target}.tmp.XXXXXX")"
  cat > "$tmp"
  chmod --reference="$target" "$tmp" 2>/dev/null || true
  mv "$tmp" "$target"
}

ensure_sudo() {
  command -v sudo >/dev/null 2>&1 || fail "sudo is required to install missing packages, but it was not found. Install missing dependencies manually and rerun this script."
  sudo -v || fail "sudo privileges are required to install missing packages."
}

install_packages_apt() {
  local packages=("$@")
  [[ ${#packages[@]} -gt 0 ]] || return 0
  ensure_sudo
  log "Installing missing packages: ${packages[*]}"
  sudo apt-get update
  sudo apt-get install -y "${packages[@]}"
}

ensure_dependencies() {
  collect_missing_dependencies

  if [[ ${#REQUIRED_MISSING[@]} -eq 0 && ${#OPTIONAL_MISSING[@]} -eq 0 ]]; then
    log "Dependencies already available."
    return 0
  fi

  if ! command -v apt-get >/dev/null 2>&1; then
    local msg="Missing dependencies. Install them manually and rerun this script. Required commands/packages: notify-send/libnotify-bin, jq/jq, python3/python3."
    if [[ ${#OPTIONAL_MISSING[@]} -gt 0 ]]; then
      msg+=" Optional sound command/package: paplay/pulseaudio-utils."
    fi
    fail "$msg"
  fi

  if [[ ${#REQUIRED_MISSING[@]} -gt 0 ]]; then
    install_packages_apt "${REQUIRED_MISSING[@]}"
  fi

  if [[ ${#OPTIONAL_MISSING[@]} -gt 0 ]]; then
    if install_packages_apt "${OPTIONAL_MISSING[@]}"; then
      log "Optional sound dependency installed."
    else
      warn "Could not install pulseaudio-utils. Visual notifications should still work, but sound hints may not."
    fi
  fi
}

ensure_dirs() {
  log "Ensuring required directories exist."
  mkdir -p "$LOCAL_BIN" "$CODEX_HOOKS_DIR" "$CLAUDE_DIR"
}

write_ai_notify() {
  log "Installing common notification helper: $AI_NOTIFY"
  [[ -f "$AI_NOTIFY" ]] && backup_file "$AI_NOTIFY"
  cat > "$AI_NOTIFY" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

tool="${1:-AI Tool}"
status="${2:-Prompt finalizado}"
urgency="${3:-normal}"
icon="${4:-utilities-terminal}"
session_title="${5:-}"

project="$(basename "$PWD")"

if [[ -n "$session_title" ]]; then
  title="[$project] $session_title"
else
  title="[$project] $status"
fi

body="$tool"

notify-send "$title" "$body" \
  --app-name="$tool" \
  --icon="$icon" \
  --urgency="$urgency" \
  --expire-time=6000 \
  --hint=string:sound-name:message-new-instant
SCRIPT
  chmod +x "$AI_NOTIFY"
  bash -n "$AI_NOTIFY"
}

write_claude_filter() {
  log "Installing Claude permission notification filter: $CLAUDE_FILTER"
  [[ -f "$CLAUDE_FILTER" ]] && backup_file "$CLAUDE_FILTER"
  cat > "$CLAUDE_FILTER" <<'SCRIPT'
#!/usr/bin/env python3
import json
import os
import subprocess
import sys

DEFAULT_MESSAGE = "Claude precisa da sua autorização"

try:
    payload = json.load(sys.stdin)
except Exception:
    sys.exit(0)

if payload.get("notification_type") != "permission_prompt":
    sys.exit(0)

cwd = payload.get("cwd") or os.getcwd()
project = os.path.basename(os.path.abspath(cwd)) or "project"
message = payload.get("message") or DEFAULT_MESSAGE

title = f"[{project}] Aguardando permissão"

subprocess.run(
    [
        "notify-send",
        title,
        str(message),
        "--app-name=Claude Code",
        "--icon=dialog-warning",
        "--urgency=critical",
        "--expire-time=0",
    ],
    check=False,
)
SCRIPT
  chmod +x "$CLAUDE_FILTER"
  python3 -m py_compile "$CLAUDE_FILTER"
}

write_codex_notify() {
  log "Installing Codex hook: $CODEX_NOTIFY"
  [[ -f "$CODEX_NOTIFY" ]] && backup_file "$CODEX_NOTIFY"
  cat > "$CODEX_NOTIFY" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="${HOME}/.codex/notify.log"
AI_NOTIFY="${HOME}/.local/bin/ai-notify"

payload="${1:-}"
if [[ -z "$payload" && ! -t 0 ]]; then
  payload="$(cat || true)"
fi

jq_read() {
  local query="$1"
  local fallback="${2:-}"
  if [[ -z "$payload" ]]; then
    printf '%s' "$fallback"
    return 0
  fi
  printf '%s' "$payload" | jq -r "$query // empty" 2>/dev/null || printf '%s' "$fallback"
}

event="$(jq_read '.hook_event_name // .type' 'codex')"
cwd="$(jq_read '.cwd' "$(pwd)")"
message="$(jq_read '.message // .reason // .["last-assistant-message"] // .statusMessage' '')"
tool="$(jq_read '.tool_name // .tool' '')"

if [[ -z "$event" ]]; then event="codex"; fi
if [[ -z "$cwd" ]]; then cwd="$(pwd)"; fi
if [[ -z "$message" ]]; then message="Codex precisa da sua autorização"; fi

project="$(basename "$cwd")"
mkdir -p "$(dirname "$LOG_FILE")"
printf '%s\t%s\t%s\t%s\n' "$(date -Is)" "$event" "$cwd" "$message" >> "$LOG_FILE"

case "$event" in
  Stop|agent-turn-complete)
    cd "$cwd" 2>/dev/null || true
    exec "$AI_NOTIFY" "Codex" "Prompt finalizado" "normal" "utilities-terminal"
    ;;
  PermissionRequest|approval-requested)
    if [[ -n "$tool" && "$message" == "Codex precisa da sua autorização" ]]; then
      message="Codex precisa da sua autorização para usar: $tool"
    fi
    notify-send "[$project] Aguardando permissão" "$message" \
      --app-name="Codex" \
      --icon="dialog-warning" \
      --urgency="critical" \
      --expire-time=0
    ;;
  *)
    exit 0
    ;;
esac
SCRIPT
  chmod +x "$CODEX_NOTIFY"
  bash -n "$CODEX_NOTIFY"
}

update_claude_settings() {
  log "Updating Claude settings JSON: $CLAUDE_SETTINGS"
  if [[ ! -f "$CLAUDE_SETTINGS" ]]; then
    printf '{}\n' > "$CLAUDE_SETTINGS"
  else
    backup_file "$CLAUDE_SETTINGS"
  fi

  local tmp
  tmp="$(mktemp "${CLAUDE_SETTINGS}.tmp.XXXXXX")"

  python3 - "$CLAUDE_SETTINGS" "$tmp" "$AI_NOTIFY" "$CLAUDE_FILTER" <<'PY'
import json
import sys
from pathlib import Path

settings_path = Path(sys.argv[1])
tmp_path = Path(sys.argv[2])
ai_notify = sys.argv[3]
claude_filter = sys.argv[4]

try:
    with settings_path.open("r", encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    data = {}

if not isinstance(data, dict):
    data = {}

hooks = data.setdefault("hooks", {})
if not isinstance(hooks, dict):
    hooks = {}
    data["hooks"] = hooks

hooks["Stop"] = [
    {
        "matcher": "",
        "hooks": [
            {
                "type": "command",
                "command": f"{ai_notify} 'Claude Code' 'Prompt finalizado' 'normal' 'utilities-terminal'",
            }
        ],
    }
]

hooks["Notification"] = [
    {
        "matcher": "",
        "hooks": [
            {
                "type": "command",
                "command": f"python3 {claude_filter}",
            }
        ],
    }
]

with tmp_path.open("w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY

  python3 -m json.tool "$tmp" >/dev/null
  mv "$tmp" "$CLAUDE_SETTINGS"
}

update_codex_config() {
  log "Updating Codex TOML config: $CODEX_CONFIG"
  if [[ -f "$CODEX_CONFIG" ]]; then
    backup_file "$CODEX_CONFIG"
  else
    touch "$CODEX_CONFIG"
  fi

  local tmp
  tmp="$(mktemp "${CODEX_CONFIG}.tmp.XXXXXX")"

  python3 - "$CODEX_CONFIG" "$tmp" "$CODEX_NOTIFY" <<'PY'
import re
import sys
from pathlib import Path

config_path = Path(sys.argv[1])
tmp_path = Path(sys.argv[2])
notify_path = sys.argv[3]

text = config_path.read_text(encoding="utf-8") if config_path.exists() else ""
lines = text.splitlines()
managed_top = {"notify"}
managed_by_section = {
    "features": {"hooks"},
    "tui": {"notifications"},
    "hooks": {"PermissionRequest", "Stop"},
}

def section_of_header(line: str):
    m = re.match(r"^\s*\[([^\[\]]+)\]\s*$", line)
    return m.group(1).strip() if m else None

def top_key(line: str):
    m = re.match(r"^\s*([A-Za-z0-9_.\-]+)\s*=", line)
    return m.group(1) if m else None

def is_array_of_tables(line: str):
    return bool(re.match(r"^\s*\[\[", line))

out = []
section = None
i = 0
while i < len(lines):
    line = lines[i]

    if is_array_of_tables(line):
        section = None
        out.append(line)
        i += 1
        continue

    header = section_of_header(line)
    if header is not None:
        section = header
        out.append(line)
        i += 1
        continue

    key = top_key(line)
    remove = False
    if key:
        if section is None and key in managed_top:
            remove = True
        elif section in managed_by_section and key in managed_by_section[section]:
            remove = True

    if remove:
        # Remove the full assignment. This also consumes following array/object lines
        # until the next obvious key or section header.
        i += 1
        depth_square = line.count("[") - line.count("]")
        depth_curly = line.count("{") - line.count("}")
        while i < len(lines):
            nxt = lines[i]
            if depth_square <= 0 and depth_curly <= 0:
                if section_of_header(nxt) is not None or top_key(nxt) is not None or is_array_of_tables(nxt):
                    break
            depth_square += nxt.count("[") - nxt.count("]")
            depth_curly += nxt.count("{") - nxt.count("}")
            i += 1
        continue

    # Drop legacy broken Codex notification path if it appears as a stray/commentless line.
    if "/home/antonbsa/local/bin/codex-notify" in line and "notify" in line:
        i += 1
        continue

    out.append(line)
    i += 1

def insert_top_level(lines, entries):
    insert_at = len(lines)
    for idx, line in enumerate(lines):
        if section_of_header(line) is not None or is_array_of_tables(line):
            insert_at = idx
            break

    before = list(lines[:insert_at])
    after = list(lines[insert_at:])
    while before and not before[-1].strip():
        before.pop()

    if before:
        before.append("")
    before.extend(entries)
    if after and after[0].strip():
        before.append("")

    return before + after

def ensure_section_entries(lines, target_section, entries):
    for idx, line in enumerate(lines):
        if section_of_header(line) != target_section:
            continue

        end = idx + 1
        while end < len(lines):
            if section_of_header(lines[end]) is not None or is_array_of_tables(lines[end]):
                break
            end += 1

        insert_at = end
        while insert_at > idx + 1 and not lines[insert_at - 1].strip():
            insert_at -= 1

        before = list(lines[:insert_at])
        after = list(lines[insert_at:])
        if before and before[-1].strip():
            before.append("")
        before.extend(entries)
        if after and after[0].strip():
            before.append("")

        return before + after

    result = list(lines)
    while result and not result[-1].strip():
        result.pop()
    if result:
        result.append("")
    result.append(f"[{target_section}]")
    result.extend(entries)
    return result

out = insert_top_level(
    out,
    [
        "# Managed by install-ai-notifications.sh",
        f'notify = ["{notify_path}"]',
    ],
)
out = ensure_section_entries(out, "features", ["hooks = true"])
out = ensure_section_entries(
    out,
    "tui",
    ['notifications = ["agent-turn-complete", "approval-requested"]'],
)
out = ensure_section_entries(
    out,
    "hooks",
    [
        "PermissionRequest = [",
        f'  {{ matcher = "*", hooks = [{{ type = "command", command = "{notify_path}", statusMessage = "Sending Codex approval notification" }}] }},',
        "]",
        "Stop = [",
        f'  {{ matcher = "*", hooks = [{{ type = "command", command = "{notify_path}", statusMessage = "Sending Codex completion notification" }}] }},',
        "]",
    ],
)

while out and not out[-1].strip():
    out.pop()

result = "\n".join(out) + "\n"

if "/home/antonbsa/local/bin/codex-notify" in result:
    result = result.replace('/home/antonbsa/local/bin/codex-notify', notify_path)

tmp_path.write_text(result, encoding="utf-8")
PY

  python3 - <<'PY' "$tmp"
import sys
from pathlib import Path
try:
    import tomllib
except Exception:
    sys.exit(0)
try:
    tomllib.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
except Exception as exc:
    print(f"TOML validation failed: {exc}", file=sys.stderr)
    sys.exit(1)
PY
  mv "$tmp" "$CODEX_CONFIG"
}

print_manual_tests() {
  cat <<TESTS

Installation complete.

Post-install test command:

./$(basename "$0") --test

Validation commands:

bash -n $AI_NOTIFY
bash -n $CODEX_NOTIFY
python3 -m json.tool $CLAUDE_SETTINGS >/dev/null
TESTS
}

require_test_file() {
  local file="$1"
  [[ -f "$file" ]] || fail "Test mode requires an existing installation. Missing file: $file"
}

require_test_executable() {
  local file="$1"
  [[ -x "$file" ]] || fail "Test mode requires an existing installation. Missing executable: $file"
}

require_config_reference() {
  local file="$1"
  local expected="$2"

  grep -Fq "$expected" "$file" || fail "Test mode requires existing configuration in $file, but it does not reference: $expected"
}

validate_test_installation() {
  log "Validating existing notification installation."

  require_test_executable "$AI_NOTIFY"
  require_test_executable "$CLAUDE_FILTER"
  require_test_executable "$CODEX_NOTIFY"
  require_test_file "$CLAUDE_SETTINGS"
  require_test_file "$CODEX_CONFIG"

  bash -n "$AI_NOTIFY"
  bash -n "$CODEX_NOTIFY"
  python3 -m py_compile "$CLAUDE_FILTER"
  python3 -m json.tool "$CLAUDE_SETTINGS" >/dev/null
  python3 - "$CODEX_CONFIG" <<'PY'
import sys
from pathlib import Path
try:
    import tomllib
except Exception:
    sys.exit(0)
try:
    tomllib.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
except Exception as exc:
    print(f"TOML validation failed: {exc}", file=sys.stderr)
    sys.exit(1)
PY

  require_config_reference "$CLAUDE_SETTINGS" "$AI_NOTIFY"
  require_config_reference "$CLAUDE_SETTINGS" "$CLAUDE_FILTER"
  require_config_reference "$CODEX_CONFIG" "$CODEX_NOTIFY"
}

run_tests() {
  local test_cwd log_lines_before

  log "Running notification tests."
  test_cwd="$(pwd)"
  log_lines_before=0
  if [[ -f "$CODEX_LOG" ]]; then
    log_lines_before="$(wc -l < "$CODEX_LOG")"
  fi

  "$CODEX_NOTIFY" "{\"type\":\"agent-turn-complete\",\"cwd\":\"$test_cwd\",\"last-assistant-message\":\"Teste de fim de prompt Codex\"}"
  printf '%s' "{\"notification_type\":\"permission_prompt\",\"message\":\"Teste de permissao Claude Code\",\"cwd\":\"$test_cwd\"}" | python3 "$CLAUDE_FILTER"

  if [[ -f "$CODEX_LOG" ]]; then
    log "New Codex log entries:"
    tail -n +"$((log_lines_before + 1))" "$CODEX_LOG" || true
  fi
}

main() {
  if [[ $RUN_TESTS -eq 1 ]]; then
    validate_test_installation
    run_tests
    return 0
  fi

  confirm_installation
  confirm_existing_configs
  ensure_dependencies
  ensure_dirs
  write_ai_notify
  write_claude_filter
  write_codex_notify
  update_claude_settings
  update_codex_config

  print_manual_tests
}

main "$@"
