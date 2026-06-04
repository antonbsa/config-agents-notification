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
message="$(jq_read '.message // .reason // .tool_input.description // .statusMessage' '')"
last_assistant_message="$(jq_read '.last_assistant_message // .["last-assistant-message"]' '')"

if [[ -z "$event" ]]; then event="codex"; fi
if [[ -z "$cwd" ]]; then cwd="$(pwd)"; fi
case "$event" in
  PermissionRequest|approval-requested)
    if [[ -z "$message" ]]; then message="Codex needs your approval"; fi
    ;;
esac

mkdir -p "$(dirname "$LOG_FILE")"
printf '%s\t%s\t%s\t%s\n' "$(date -Is)" "$event" "$cwd" "${last_assistant_message:-$message}" >> "$LOG_FILE"

case "$event" in
  Stop|agent-turn-complete)
    exec "$AI_NOTIFY" "Codex" "finished" "normal" "utilities-terminal" "$cwd" "$last_assistant_message"
    ;;
  PermissionRequest|approval-requested)
    exec "$AI_NOTIFY" "Codex" "waiting for approval" "critical" "dialog-warning" "$cwd" ""
    ;;
  *)
    exit 0
    ;;
esac
