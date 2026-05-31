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
