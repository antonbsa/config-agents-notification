backup_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  local ts backup
  ts="$(date +%Y%m%d%H%M%S)"
  backup="${file}.bak.${ts}"
  cp -p "$file" "$backup"
  log "Backup created: $backup"
}

ensure_dirs() {
  log "Ensuring required directories exist."
  mkdir -p "$LOCAL_BIN" "$CODEX_HOOKS_DIR" "$CLAUDE_DIR"
}

write_rendered_template() {
  local template="$1"
  local target="$2"

  [[ -f "$target" ]] && backup_file "$target"
  render_template "$template" > "$target"
  chmod +x "$target"
}
