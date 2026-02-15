#!/usr/bin/env bash
set -Eeuo pipefail

# ===== Config =====
readonly REPO_URL="https://github.com/gitdias/Toucan-Shell.git"
readonly REPO_REF="${REPO_REF:-main}"

readonly INSTALL_PREFIX="/usr/share/toucan-shell"
readonly INSTALL_QUICKSHELL_DIR="$INSTALL_PREFIX/quickshell"

# Pin mínimo (o único que dá pra cravar agora sem inventar baseline do Hyprland/Qt)
readonly MIN_QUICKSHELL="${MIN_QUICKSHELL:-0.2.1}"

# IDs comuns em variantes Arch (não confio 100% nos IDs; por isso também aceito ID_LIKE=arch)
readonly ALLOW_IDS_REGEX='^(arch|manjaro|endeavouros|cachyos|biglinux)$'

# ===== Utils =====
log() { printf '%s\n' "$*"; }
die() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Comando ausente: $1"; }

semver_ge() {
  # retorna 0 se $1 >= $2
  # suporta x.y.z (ignora sufixos)
  local a b
  a="$(printf '%s' "$1" | grep -Eo '[0-9]+(\.[0-9]+){1,2}' | head -n1 || true)"
  b="$(printf '%s' "$2" | grep -Eo '[0-9]+(\.[0-9]+){1,2}' | head -n1 || true)"
  [[ -n "$a" && -n "$b" ]] || return 2
  # normaliza para 3 campos
  IFS=. read -r a1 a2 a3 <<<"${a}.0.0"
  IFS=. read -r b1 b2 b3 <<<"${b}.0.0"
  a3="${a3:-0}"; b3="${b3:-0}"
  if (( a1 != b1 )); then (( a1 > b1 )); return; fi
  if (( a2 != b2 )); then (( a2 > b2 )); return; fi
  (( a3 >= b3 ))
}

#as_root() {
#  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
#    need_cmd sudo
#    exec sudo -E bash "$0" "$@"
#  fi
#}
as_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    need_cmd sudo

    # Se o script está sendo executado via stdin (ex.: curl|bash),
    # não existe um arquivo para "$0". Nesse caso, preserve o stdin e eleve assim:
    if [[ ! -f "${BASH_SOURCE[0]:-}" ]] || [[ "${BASH_SOURCE[0]:-}" == "-" ]]; then
      exec sudo -E bash -s -- "$@"
    fi

    # Caso normal (arquivo local)
    exec sudo -E bash "${BASH_SOURCE[0]}" "$@"
  fi
}

detect_distro() {
  [[ -r /etc/os-release ]] || die "Não encontrei /etc/os-release"
  # shellcheck disable=SC1091
  . /etc/os-release

  local id="${ID:-}"
  local like="${ID_LIKE:-}"

  # Permite: IDs explicitamente allowlist OU ID_LIKE contendo arch
  if [[ "$id" =~ $ALLOW_IDS_REGEX ]] || [[ " $like " == *" arch "* ]] || [[ "$id" == "arch" ]]; then
    log "OK: Distro detectada: ID=$id (ID_LIKE=$like)"
    return 0
  fi

  die "Distro não suportada para este instalador pacman-only: ID=$id (ID_LIKE=$like)"
}

pacman_install() {
  need_cmd pacman

  # Evita "partial upgrade": usa -Syu (sim, isso pode atualizar o sistema; mas é o menos perigoso)
  # --needed evita reinstalação inútil
  local -a pkgs=("$@")
  log "Instalando dependências via pacman: ${pkgs[*]}"
  pacman -Syu --needed --noconfirm "${pkgs[@]}"
}

check_pkg_exists() {
  local pkg="$1"
  if ! pacman -Si "$pkg" >/dev/null 2>&1; then
    die "Pacote não encontrado no repositório do pacman: $pkg (requisito pacman-only falhou)"
  fi
}

check_quickshell_version() {
  need_cmd quickshell

  local v raw
  raw="$(quickshell --version 2>/dev/null || true)"
  v="$(printf '%s' "$raw" | grep -Eo '[0-9]+(\.[0-9]+){1,2}' | head -n1 || true)"
  [[ -n "$v" ]] || die "Não consegui detectar versão do quickshell (saida: $raw)"

  if ! semver_ge "$v" "$MIN_QUICKSHELL"; then
    die "Quickshell versão $v < mínimo suportado $MIN_QUICKSHELL"
  fi

  log "OK: Quickshell version pin: $v >= $MIN_QUICKSHELL"
}

main() {
  as_root "$@"
  detect_distro

  need_cmd git
  need_cmd mktemp
  need_cmd find
  need_cmd grep
  need_cmd id

  # Checa se quickshell existe no repo antes de tentar instalar
  check_pkg_exists quickshell

  # Dependências mínimas (pacman-only)
  pacman_install \
    git \
    quickshell \
    hyprland \
    qt6-base \
    qt6-declarative \
    qt6-wayland

  check_quickshell_version

  local tmp
  tmp="$(mktemp -d -p /tmp toucan-shell.XXXXXX)"
  log "Clonando repo em: $tmp"
  git clone --depth 1 --branch "$REPO_REF" "$REPO_URL" "$tmp/repo"

  # Guardrail 2 no clone
  if [[ -x "$tmp/repo/quickshell/scripts/guardrail_layouts.sh" ]]; then
    "$tmp/repo/quickshell/scripts/guardrail_layouts.sh" "$tmp/repo/quickshell/customize/layouts"
  else
    die "guardrail_layouts.sh não encontrado/executável no repo clonado"
  fi

  # Instalação global
  log "Instalando Toucan Shell globalmente em: $INSTALL_QUICKSHELL_DIR"
  rm -rf "$INSTALL_QUICKSHELL_DIR"
  mkdir -p "$INSTALL_PREFIX"
  cp -a "$tmp/repo/quickshell" "$INSTALL_QUICKSHELL_DIR"

  # Futuros usuários: /etc/skel
  log "Configurando /etc/skel para novos usuários"
  mkdir -p /etc/skel/.config
  if [[ -e /etc/skel/.config/quickshell && ! -L /etc/skel/.config/quickshell ]]; then
    log "AVISO: /etc/skel/.config/quickshell já existe e não é symlink; não vou sobrescrever"
  else
    rm -f /etc/skel/.config/quickshell
    ln -s "$INSTALL_QUICKSHELL_DIR" /etc/skel/.config/quickshell
  fi

  # Usuários atuais: aplica somente se não existir ~/.config/quickshell
  log "Aplicando para usuários atuais (somente se não existir ~/.config/quickshell)"
  for home in /home/*; do
    [[ -d "$home" ]] || continue
    local user cfg
    user="$(basename "$home")"
    cfg="$home/.config/quickshell"

    # ignora homes que não são realmente usuários
    id "$user" >/dev/null 2>&1 || continue

    mkdir -p "$home/.config"
    if [[ -e "$cfg" ]]; then
      log "SKIP: $user já possui $cfg (não vou sobrescrever)"
      continue
    fi

    ln -s "$INSTALL_QUICKSHELL_DIR" "$cfg"
    chown -h "$user:$user" "$cfg" || true
  done

  log "OK: Toucan Shell instalado."
  log "Instalação global: $INSTALL_QUICKSHELL_DIR"
}

main "$@"
