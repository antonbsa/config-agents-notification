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
