#!/usr/bin/env bash
set -Eeuo pipefail

# ========== Config ==========
INSTALL_GLOBAL="${INSTALL_GLOBAL:-/usr/share/toucan_shell}"

# ========== Utils ==========
log()  { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die()  { printf '[ERRO] %s\n' "$*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1; }

# ========== Phase: root escalation ==========
as_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    need_cmd sudo || die "sudo missing (required for uninstall)"
    exec sudo -E bash "${BASH_SOURCE[0]}" "$@"
  fi
}

# ========== Phase: remove global ==========
remove_global() {
  if [[ ! -d "$INSTALL_GLOBAL" ]]; then
    log "Global installation not found at $INSTALL_GLOBAL (already removed?)"
    return 0
  fi

  log "Removing global installation: $INSTALL_GLOBAL"
  rm -rf "$INSTALL_GLOBAL"
}

# ========== Phase: remove user configs ==========
remove_user_configs() {
  log "Checking user configurations..."
  local home user cfg

  for home in /home/*; do
    [[ -d "$home" ]] || continue
    user="$(basename "$home")"
    id "$user" >/dev/null 2>&1 || continue

    cfg="$home/.config/quickshell"

    if [[ ! -e "$cfg" ]]; then
      continue
    fi

    # Pergunta ao usuário se quer remover
    read -rp "Remove $cfg for user $user? [y/N]: " answer
    case "$answer" in
      [yY]|[yY][eE][sS])
        log "Removing: $cfg"
        rm -rf "$cfg"
        ;;
      *)
        log "SKIP: keeping $cfg"
        ;;
    esac
  done
}

# ========== Phase: remove systemd timers ==========
remove_systemd_timers() {
  log "Checking systemd user timers..."
  local home user

  for home in /home/*; do
    [[ -d "$home" ]] || continue
    user="$(basename "$home")"
    id "$user" >/dev/null 2>&1 || continue

    local timer_file="$home/.config/systemd/user/toucan-update.timer"
    local service_file="$home/.config/systemd/user/toucan-update.service"

    if [[ -f "$timer_file" || -f "$service_file" ]]; then
      log "Found systemd timer for $user"

      # Para e desabilita timer (como usuário)
      sudo -u "$user" systemctl --user stop toucan-update.timer 2>/dev/null || true
      sudo -u "$user" systemctl --user disable toucan-update.timer 2>/dev/null || true

      rm -f "$timer_file" "$service_file"
      log "Removed systemd timer for $user"
    fi
  done
}

# ========== Main ==========
main() {
  as_root "$@"

  remove_global
  remove_systemd_timers
  remove_user_configs

  log "SUCCESS: Toucan Shell uninstalled"
  log "User data preserved if user chose to keep ~/.config/quickshell"
}

main "$@"
