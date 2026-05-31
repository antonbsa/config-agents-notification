#!/usr/bin/env bash
set -euo pipefail

# Single entrypoint for cloned repo usage and wget/curl pipe installs.

SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
TEMPLATE_DIR="${SCRIPT_DIR}/templates"

REPO_ARCHIVE_URL="${AI_NOTIFICATIONS_REPO_ARCHIVE_URL:-https://github.com/antonbsa/install-ai-agents-push-notifications/archive/refs/heads/main.tar.gz}"

bootstrap_repo_if_needed() {
  [[ -f "${SCRIPT_DIR}/lib/common.sh" && -d "${SCRIPT_DIR}/templates" ]] && return 0
  [[ "${AI_NOTIFICATIONS_BOOTSTRAPPED:-0}" == "1" ]] && {
    printf '[ai-notifications][error] Repository files were not found after bootstrap.\n' >&2
    exit 1
  }

  local tmp archive extract_dir
  tmp="$(mktemp -d)"
  archive="${tmp}/repo.tar.gz"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$REPO_ARCHIVE_URL" -o "$archive"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$archive" "$REPO_ARCHIVE_URL"
  else
    printf '[ai-notifications][error] curl or wget is required to bootstrap the repository files.\n' >&2
    exit 1
  fi

  tar -xzf "$archive" -C "$tmp"
  extract_dir="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  [[ -n "$extract_dir" && -f "${extract_dir}/install.sh" ]] || {
    printf '[ai-notifications][error] Could not find install.sh in downloaded archive: %s\n' "$REPO_ARCHIVE_URL" >&2
    exit 1
  }

  export AI_NOTIFICATIONS_BOOTSTRAPPED=1
  exec bash "${extract_dir}/install.sh" "$@"
}

bootstrap_repo_if_needed "$@"

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

source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/templates.sh"
source "${SCRIPT_DIR}/lib/dependencies.sh"
source "${SCRIPT_DIR}/lib/filesystem.sh"
source "${SCRIPT_DIR}/lib/claude.sh"
source "${SCRIPT_DIR}/lib/codex.sh"
source "${SCRIPT_DIR}/lib/test.sh"

parse_args "$@"
main
