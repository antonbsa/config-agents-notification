read_template() {
  local name="$1"

  if declare -F read_embedded_template >/dev/null 2>&1; then
    read_embedded_template "$name"
    return
  fi

  cat "${TEMPLATE_DIR}/${name}"
}

render_template() {
  local name="$1"

  read_template "$name" | sed \
    -e "s|__AI_NOTIFY__|$AI_NOTIFY|g" \
    -e "s|__CLAUDE_FILTER__|$CLAUDE_FILTER|g" \
    -e "s|__CODEX_NOTIFY__|$CODEX_NOTIFY|g"
}
