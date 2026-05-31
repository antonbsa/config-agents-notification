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
