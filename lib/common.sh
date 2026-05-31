usage() {
  cat <<USAGE
Usage: $(basename "$0") [--test] [--help]

Options:
  --test     Run notification tests against an existing installation.
  --help     Show this help message.
USAGE
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --test) RUN_TESTS=1 ;;
      --help|-h) usage; exit 0 ;;
      *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
  done
}

log() { printf '[ai-notifications] %s\n' "$*"; }
warn() { printf '[ai-notifications][warn] %s\n' "$*" >&2; }
fail() { printf '[ai-notifications][error] %s\n' "$*" >&2; exit 1; }

confirm() {
  local prompt="$1"
  local reply

  if [[ "${AI_NOTIFICATIONS_ASSUME_YES:-0}" == "1" ]]; then
    printf '%s (Y/n) y\n' "$prompt"
    return 0
  fi

  while true; do
    if [[ -t 0 ]]; then
      printf '%s (Y/n) ' "$prompt"
      IFS= read -r reply || fail "Could not read user confirmation."
    elif { exec 3<>/dev/tty; } 2>/dev/null; then
      printf '%s (Y/n) ' "$prompt" >&3
      IFS= read -r reply <&3 || fail "Could not read user confirmation."
      exec 3>&-
    else
      fail "Could not read user confirmation. Run from an interactive terminal or set AI_NOTIFICATIONS_ASSUME_YES=1."
    fi

    case "$reply" in
      ""|[Yy]|[Yy][Ee][Ss]|[Ss]|[Ss][Ii][Mm]) return 0 ;;
      [Nn]|[Nn][Oo]) return 1 ;;
      *) warn "Please answer y or n." ;;
    esac
  done
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

print_manual_tests() {
  cat <<TESTS

Installation complete.

Post-install test command:

Run this installer again with --test.
For a cloned repo:
  ./install.sh --test
For a remote install:
  wget -qO- <same-install.sh-url> | bash -s -- --test

Validation commands:

bash -n $AI_NOTIFY
bash -n $CODEX_NOTIFY
python3 -m json.tool $CLAUDE_SETTINGS >/dev/null
TESTS
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
