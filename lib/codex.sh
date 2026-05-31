write_codex_notify() {
  log "Installing Codex hook: $CODEX_NOTIFY"
  write_rendered_template "codex-notify.sh" "$CODEX_NOTIFY"
  bash -n "$CODEX_NOTIFY"
}

update_codex_config() {
  log "Updating Codex TOML config: $CODEX_CONFIG"
  if [[ -f "$CODEX_CONFIG" ]]; then
    backup_file "$CODEX_CONFIG"
  else
    touch "$CODEX_CONFIG"
  fi

  local tmp managed_tmp
  tmp="$(mktemp "${CODEX_CONFIG}.tmp.XXXXXX")"
  managed_tmp="$(mktemp "${CODEX_CONFIG}.managed.XXXXXX")"
  render_template "codex-config-managed.toml" > "$managed_tmp"

  python3 - "$CODEX_CONFIG" "$tmp" "$managed_tmp" "$CODEX_NOTIFY" <<'PY'
import re
import sys
from pathlib import Path

config_path = Path(sys.argv[1])
tmp_path = Path(sys.argv[2])
managed_path = Path(sys.argv[3])
notify_path = sys.argv[4]

text = config_path.read_text(encoding="utf-8") if config_path.exists() else ""
lines = text.splitlines()
managed_lines = managed_path.read_text(encoding="utf-8").splitlines()

def section_of_header(line: str):
    m = re.match(r"^\s*\[([^\[\]]+)\]\s*$", line)
    return m.group(1).strip() if m else None

def top_key(line: str):
    m = re.match(r"^\s*([A-Za-z0-9_.\-]+)\s*=", line)
    return m.group(1) if m else None

def is_array_of_tables(line: str):
    return bool(re.match(r"^\s*\[\[", line))

def trim_blank_edges(items):
    result = list(items)
    while result and not result[0].strip():
        result.pop(0)
    while result and not result[-1].strip():
        result.pop()
    return result

managed_top_entries = []
managed_sections = {}
section = None
for line in managed_lines:
    header = section_of_header(line)
    if header is not None:
        section = header
        managed_sections.setdefault(section, [])
        continue

    if section is None:
        managed_top_entries.append(line)
    else:
        managed_sections.setdefault(section, []).append(line)

managed_top_entries = trim_blank_edges(managed_top_entries)
managed_sections = {
    name: trim_blank_edges(entries)
    for name, entries in managed_sections.items()
}
managed_top = {
    key for key in (top_key(line) for line in managed_top_entries) if key
}
managed_by_section = {
    name: {key for key in (top_key(line) for line in entries) if key}
    for name, entries in managed_sections.items()
}
legacy_managed_by_section = {
    "features": {"hooks"},
    "hooks": {"PermissionRequest", "Stop"},
}
for name, keys in legacy_managed_by_section.items():
    managed_by_section.setdefault(name, set()).update(keys)

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

    if "/home/antonbsa/local/bin/codex-notify" in line and "notify" in line:
        i += 1
        continue

    if line.strip() in {"# Managed by install-ai-notifications.sh", "# Managed by install.sh"}:
        i += 1
        continue

    out.append(line)
    i += 1

def insert_top_level(lines, entries):
    if not entries:
        return lines

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
    if not entries:
        return lines

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

out = insert_top_level(out, managed_top_entries)
for section_name, section_entries in managed_sections.items():
    out = ensure_section_entries(out, section_name, section_entries)

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
  rm -f "$managed_tmp"
}
