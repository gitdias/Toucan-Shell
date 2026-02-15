#!/usr/bin/env bash
set -Eeuo pipefail

# ========== Config ==========
MIN_QUICKSHELL="${MIN_QUICKSHELL:-0.2.1}"
MIN_HYPRLAND="${MIN_HYPRLAND:-0.53.3}"

REPO_URL="${REPO_URL:-https://github.com/gitdias/Toucan-Shell.git}"
REPO_REF="${REPO_REF:-main}"

INSTALL_GLOBAL="${INSTALL_GLOBAL:-/usr/share/toucan_shell}"
GLOBAL_QUICKSHELL_DIR="$INSTALL_GLOBAL/quickshell"

# Opção B: aplicar para usuários existentes (sem sobrescrever)
APPLY_EXISTING_USERS="${APPLY_EXISTING_USERS:-1}"

# ========== Arrays (limpam o código) ==========
REQUIRED_CMDS=(
  bash
  pacman
  git
  mktemp
  find
  grep
  sed
  id
)

REQUIRED_PKGS=(
  git
  quickshell
  hyprland
  qt6-base
  qt6-declarative
  qt6-wayland
)

# ========== Utils ==========
log()  { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die()  { printf '[ERRO] %s\n' "$*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1; }

require_cmds() {
  local missing=()
  local c
  for c in "${REQUIRED_CMDS[@]}"; do
    if ! need_cmd "$c"; then
      missing+=("$c")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    die "Comandos ausentes: ${missing[*]}"
  fi
}

cleanup_tmp=""
on_exit() {
  local rc=$?
  if [[ -n "${cleanup_tmp:-}" && -d "${cleanup_tmp:-}" ]]; then
    rm -rf "$cleanup_tmp" || true
  fi
  exit "$rc"
}
trap on_exit EXIT

ver_norm() {
  # extrai x.y.z no começo e ignora sufixos (ex.: 0.53.3-1)
  printf '%s' "$1" | grep -Eo '^[0-9]+(\.[0-9]+){1,2}' || true
}

semver_ge() {
  local a b a1 a2 a3 b1 b2 b3
  a="$(ver_norm "$1")"
  b="$(ver_norm "$2")"
  [[ -n "$a" && -n "$b" ]] || return 2

  IFS=. read -r a1 a2 a3 <<<"${a}.0.0"
  IFS=. read -r b1 b2 b3 <<<"${b}.0.0"
  a3="${a3:-0}"; b3="${b3:-0}"

  if (( a1 != b1 )); then (( a1 > b1 )); return; fi
  if (( a2 != b2 )); then (( a2 > b2 )); return; fi
  (( a3 >= b3 ))
}

# ========== Phase: root escalation (pipe-safe) ==========
as_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    need_cmd sudo || die "sudo ausente (necessário para instalação global)"

    # Se veio via stdin (curl|bash), reexecuta lendo do stdin
    if [[ ! -f "${BASH_SOURCE[0]:-}" ]] || [[ "${BASH_SOURCE[0]:-}" == "-" ]]; then
      exec sudo -E bash -s -- "$@"
    fi

    exec sudo -E bash "${BASH_SOURCE[0]}" "$@"
  fi
}

# ========== Phase: distro gate ==========
detect_distro() {
  [[ -r /etc/os-release ]] || die "Não encontrei /etc/os-release"
  # shellcheck disable=SC1091
  . /etc/os-release

  local id="${ID:-}"
  local like="${ID_LIKE:-}"

  case "$id" in
    arch|manjaro|endeavouros|cachyos|biglinux) return 0 ;;
  esac

  if [[ " $like " == *" arch "* ]]; then
    return 0
  fi

  die "Distro não suportada (precisa ser base Arch). ID=$id ID_LIKE=$like"
}

# ========== Phase: pacman deps ==========
check_pkg_exists() {
  pacman -Si "$1" >/dev/null 2>&1
}

require_repo_pkgs() {
  local missing=()
  local p
  for p in "${REQUIRED_PKGS[@]}"; do
    if ! check_pkg_exists "$p"; then
      missing+=("$p")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    die "Pacotes não encontrados no repo do pacman (pacman-only falhou): ${missing[*]}"
  fi
}

pacman_install() {
  log "Instalando/atualizando dependências via pacman (pacman-only): ${REQUIRED_PKGS[*]}"
  pacman -Syu --needed --noconfirm "${REQUIRED_PKGS[@]}"
}

pkg_version() {
  local pkg="$1"
  pacman -Qi "$pkg" 2>/dev/null | sed -n 's/^Version *: *//p' | head -n1
}

check_pins() {
  local vq vh
  vq="$(pkg_version quickshell || true)"
  [[ -n "$vq" ]] || die "Não consegui obter versão instalada do quickshell via pacman -Qi"
  semver_ge "$vq" "$MIN_QUICKSHELL" || die "Quickshell $vq < mínimo $MIN_QUICKSHELL"

  vh="$(pkg_version hyprland || true)"
  [[ -n "$vh" ]] || die "Não consegui obter versão instalada do hyprland via pacman -Qi"
  semver_ge "$vh" "$MIN_HYPRLAND" || die "Hyprland $vh < mínimo $MIN_HYPRLAND"

  log "Pins OK: quickshell $vq >= $MIN_QUICKSHELL; hyprland $vh >= $MIN_HYPRLAND"
}

# ========== Phase: install global + users ==========
install_global() {
  local src_repo="$1"

  log "Instalando globalmente em: $GLOBAL_QUICKSHELL_DIR"
  rm -rf "$GLOBAL_QUICKSHELL_DIR"
  mkdir -p "$INSTALL_GLOBAL"
  cp -a "$src_repo/quickshell" "$GLOBAL_QUICKSHELL_DIR"
}

apply_existing_users() {
  [[ "$APPLY_EXISTING_USERS" == "1" ]] || return 0

  log "Aplicando para usuários existentes (somente se ~/.config/quickshell não existir)"
  local home user cfg
  for home in /home/*; do
    [[ -d "$home" ]] || continue
    user="$(basename "$home")"
    id "$user" >/dev/null 2>&1 || continue

    cfg="$home/.config/quickshell"
    mkdir -p "$home/.config"

    if [[ -e "$cfg" ]]; then
      log "SKIP: $user já possui $cfg (não vou sobrescrever)"
      continue
    fi

    ln -s "$GLOBAL_QUICKSHELL_DIR" "$cfg"
    chown -h "$user:$user" "$cfg" || true
  done
}

# ========== Main ==========
main() {
  as_root "$@"
  detect_distro
  require_cmds

  require_repo_pkgs
  pacman_install
  check_pins

  cleanup_tmp="$(mktemp -d -p /tmp toucan-shell.XXXXXX)"
  log "Clonando repo em: $cleanup_tmp"
  git clone --depth 1 --branch "$REPO_REF" "$REPO_URL" "$cleanup_tmp/repo"

  # Guardrail 2 (layouts flat)
  local guard="$cleanup_tmp/repo/quickshell/scripts/guardrail_layouts.sh"
  [[ -f "$guard" ]] || die "Guardrail não encontrado no repo clonado: $guard"
  bash "$guard" "$cleanup_tmp/repo/quickshell/customize/layouts"

  install_global "$cleanup_tmp/repo"
  apply_existing_users

  log "SUCESSO: Toucan Shell instalado."
  log "Global: $GLOBAL_QUICKSHELL_DIR"
  log "Usuários existentes: aplicado quando ~/.config/quickshell estava ausente (sem sobrescrever)."
}

main "$@"
