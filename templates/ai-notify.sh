#!/usr/bin/env bash
set -euo pipefail

agent="${1:-AI Tool}"
status="${2:-finished}"
urgency="${3:-normal}"
icon="${4:-utilities-terminal}"
cwd="${5:-$PWD}"
content="${6:-}"

project="$(basename "${cwd%/}")"
if [[ -z "$project" || "$project" == "." ]]; then
  project="project"
fi

normalize_content() {
  printf '%s' "$1" \
    | tr '\n\r\t' '   ' \
    | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}

body="$(normalize_content "$content")"
if (( ${#body} > 200 )); then
  body="${body:0:197}..."
fi

title="[$project] $agent $status"
expire_time="6000"
if [[ "$urgency" == "critical" ]]; then
  expire_time="0"
fi

notify_args=("$title")
if [[ -n "$body" ]]; then
  notify_args+=("$body")
fi

notify-send "${notify_args[@]}" \
  --app-name="$agent" \
  --icon="$icon" \
  --urgency="$urgency" \
  --expire-time="$expire_time" \
  --hint=string:sound-name:message-new-instant
