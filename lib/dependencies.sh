collect_missing_dependencies() {
  REQUIRED_MISSING=()
  OPTIONAL_MISSING=()

  command -v notify-send >/dev/null 2>&1 || REQUIRED_MISSING+=(libnotify-bin)
  command -v jq >/dev/null 2>&1 || REQUIRED_MISSING+=(jq)
  command -v python3 >/dev/null 2>&1 || REQUIRED_MISSING+=(python3)
  command -v paplay >/dev/null 2>&1 || OPTIONAL_MISSING+=(pulseaudio-utils)
}

ensure_sudo() {
  command -v sudo >/dev/null 2>&1 || fail "sudo is required to install missing packages, but it was not found. Install missing dependencies manually and rerun this script."
  sudo -v || fail "sudo privileges are required to install missing packages."
}

install_packages_apt() {
  local packages=("$@")
  [[ ${#packages[@]} -gt 0 ]] || return 0
  ensure_sudo
  log "Installing missing packages: ${packages[*]}"
  sudo apt-get update
  sudo apt-get install -y "${packages[@]}"
}

ensure_dependencies() {
  collect_missing_dependencies

  if [[ ${#REQUIRED_MISSING[@]} -eq 0 && ${#OPTIONAL_MISSING[@]} -eq 0 ]]; then
    log "Dependencies already available."
    return 0
  fi

  if ! command -v apt-get >/dev/null 2>&1; then
    local msg="Missing dependencies. Install them manually and rerun this script. Required commands/packages: notify-send/libnotify-bin, jq/jq, python3/python3."
    if [[ ${#OPTIONAL_MISSING[@]} -gt 0 ]]; then
      msg+=" Optional sound command/package: paplay/pulseaudio-utils."
    fi
    fail "$msg"
  fi

  if [[ ${#REQUIRED_MISSING[@]} -gt 0 ]]; then
    install_packages_apt "${REQUIRED_MISSING[@]}"
  fi

  if [[ ${#OPTIONAL_MISSING[@]} -gt 0 ]]; then
    if install_packages_apt "${OPTIONAL_MISSING[@]}"; then
      log "Optional sound dependency installed."
    else
      warn "Could not install pulseaudio-utils. Visual notifications should still work, but sound hints may not."
    fi
  fi
}
