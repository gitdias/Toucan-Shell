#!/usr/bin/env bash
set -Eeuo pipefail

# ========== i18n Detection (BEFORE sudo) ==========
detect_locale() {
  # Detecta idioma do usuário real (antes de sudo)
  local user_lang="${SUDO_USER:+$(sudo -u "$SUDO_USER" printenv LANG 2>/dev/null || true)}"
  user_lang="${user_lang:-$LANG}"

  case "${user_lang:-en_US}" in
    pt_BR*|pt_PT*) echo "pt_BR" ;;
    *)             echo "en_US" ;;
  esac
}

LOCALE="$(detect_locale)"

# ========== i18n Dictionary ==========
msg() {
  local key="$1"
  case "$LOCALE" in
    pt_BR)
      case "$key" in
        bootstrap_missing)     echo "Comandos ausentes (bootstrap)" ;;
        distro_unsupported)    echo "Distro não suportada (precisa ser base Arch)" ;;
        pkg_not_found)         echo "Pacotes não encontrados no repo do pacman (pacman-only)" ;;
        installing_deps)       echo "Instalando/atualizando dependências via pacman" ;;
        quickshell_version)    echo "Não consegui obter versão instalada do quickshell" ;;
        hyprland_version)      echo "Não consegui obter versão instalada do hyprland" ;;
        quickshell_too_old)    echo "Quickshell" ;;
        hyprland_too_old)      echo "Hyprland" ;;
        pins_ok)               echo "Pins OK" ;;
        cloning_repo)          echo "Clonando repositório em" ;;
        guardrail_fail)        echo "Guardrail falhou: layout ausente" ;;
        installing_global)     echo "Instalando globalmente em" ;;
        postcheck_fail_dir)    echo "Pós-check falhou: diretório não criado" ;;
        postcheck_fail_layouts) echo "Pós-check falhou: layouts ausentes em" ;;
        applying_users)        echo "Aplicando para usuários existentes" ;;
        skip_user_exists)      echo "SKIP: usuário já possui" ;;
        success)               echo "SUCESSO: Toucan Shell instalado" ;;
        success_global)        echo "Global" ;;
        success_users)         echo "Usuários: cópia aplicada quando ~/.config/quickshell estava ausente" ;;
        sudo_missing)          echo "sudo ausente (necessário para instalação global)" ;;
        stdin_bootstrap)       echo "Execução via stdin detectada; gerando bootstrap em /tmp" ;;
        install_sh_url_fail)   echo "Não consegui derivar URL do install.sh. Defina INSTALL_SH_URL" ;;
        download_fail)         echo "Não consegui baixar install.sh (precisa curl ou wget)" ;;
        bootstrap_empty)       echo "Bootstrap falhou: arquivo baixado está vazio" ;;
        bootstrap_html)        echo "Bootstrap falhou: baixou HTML ao invés de script" ;;
        bootstrap_no_shebang)  echo "Bootstrap falhou: arquivo sem shebang" ;;
        os_release_missing)    echo "Não encontrei /etc/os-release" ;;
        repo_missing_quickshell) echo "Repo clonado não contém quickshell/" ;;
        git_not_available)     echo "git ainda não está disponível após pacman_install" ;;
        guardrail_missing)     echo "Guardrail não encontrado no repo clonado" ;;
        min_version_below)     echo "< mínimo" ;;
      esac
      ;;
    *)
      case "$key" in
        bootstrap_missing)     echo "Missing bootstrap commands" ;;
        distro_unsupported)    echo "Unsupported distro (needs Arch-based)" ;;
        pkg_not_found)         echo "Packages not found in pacman repo (pacman-only)" ;;
        installing_deps)       echo "Installing/updating dependencies via pacman" ;;
        quickshell_version)    echo "Could not get quickshell installed version" ;;
        hyprland_version)      echo "Could not get hyprland installed version" ;;
        quickshell_too_old)    echo "Quickshell" ;;
        hyprland_too_old)      echo "Hyprland" ;;
        pins_ok)               echo "Pins OK" ;;
        cloning_repo)          echo "Cloning repository at" ;;
        guardrail_fail)        echo "Guardrail failed: missing layout" ;;
        installing_global)     echo "Installing globally at" ;;
        postcheck_fail_dir)    echo "Post-check failed: directory not created" ;;
        postcheck_fail_layouts) echo "Post-check failed: layouts missing at" ;;
        applying_users)        echo "Applying to existing users" ;;
        skip_user_exists)      echo "SKIP: user already has" ;;
        success)               echo "SUCCESS: Toucan Shell installed" ;;
        success_global)        echo "Global" ;;
        success_users)         echo "Users: copy applied when ~/.config/quickshell was absent" ;;
        sudo_missing)          echo "sudo missing (required for global installation)" ;;
        stdin_bootstrap)       echo "Stdin execution detected; generating bootstrap in /tmp" ;;
        install_sh_url_fail)   echo "Could not derive install.sh URL. Set INSTALL_SH_URL" ;;
        download_fail)         echo "Could not download install.sh (needs curl or wget)" ;;
        bootstrap_empty)       echo "Bootstrap failed: downloaded file is empty" ;;
        bootstrap_html)        echo "Bootstrap failed: downloaded HTML instead of script" ;;
        bootstrap_no_shebang)  echo "Bootstrap failed: file has no shebang" ;;
        os_release_missing)    echo "Could not find /etc/os-release" ;;
        repo_missing_quickshell) echo "Cloned repo does not contain quickshell/" ;;
        git_not_available)     echo "git still not available after pacman_install" ;;
        guardrail_missing)     echo "Guardrail not found in cloned repo" ;;
        min_version_below)     echo "< minimum" ;;
      esac
      ;;
  esac
}

# ========== Config ==========
MIN_QUICKSHELL="${MIN_QUICKSHELL:-0.2.0}"
MIN_HYPRLAND="${MIN_HYPRLAND:-0.53.3}"

REPO_URL="${REPO_URL:-https://github.com/gitdias/Toucan-Shell.git}"
REPO_REF="${REPO_REF:-main}"

INSTALL_GLOBAL="${INSTALL_GLOBAL:-/usr/share/toucan_shell}"
GLOBAL_QUICKSHELL_DIR="$INSTALL_GLOBAL/quickshell"

APPLY_EXISTING_USERS="${APPLY_EXISTING_USERS:-1}"

# ========== Arrays ==========
BOOTSTRAP_CMDS=(
  bash pacman mktemp find grep sed awk id
)

REQUIRED_PKGS=(
  git quickshell hyprland qt6-base qt6-declarative qt6-wayland cmatrix
)

REQUIRED_LAYOUTS=(
  Alternative.qml Elegant.qml Futuristic.qml
  Minimalist.qml Modern.qml Pop.qml
)

# ========== Utils ==========
log()  { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die()  { printf '[ERRO] %s\n' "$*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1; }

require_cmds() {
  local -a missing=()
  local c
  for c in "${BOOTSTRAP_CMDS[@]}"; do
    if ! need_cmd "$c"; then
      missing+=("$c")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    die "$(msg bootstrap_missing): ${missing[*]}"
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
  local v="${1:-}"
  v="${v#*:}"
  v="${v%%-*}"
  v="$(printf '%s' "$v" | grep -Eo '^[0-9]+(\.[0-9]+){0,3}' | head -n1 || true)"
  [[ -n "$v" ]] || return 1

  local a1 a2 a3 a4
  IFS=. read -r a1 a2 a3 a4 <<<"$v"
  [[ -n "${a1:-}" && -n "${a2:-}" ]] || return 1

  a3="${a3:-0}"
  printf '%s.%s.%s' "$a1" "$a2" "$a3"
}

semver_ge() {
  local a b a1 a2 a3 b1 b2 b3

  a="$(ver_norm "$1")" || return 2
  b="$(ver_norm "$2")" || return 2

  IFS=. read -r a1 a2 a3 <<<"$a"
  IFS=. read -r b1 b2 b3 <<<"$b"

  if (( a1 != b1 )); then (( a1 > b1 )); return; fi
  if (( a2 != b2 )); then (( a2 > b2 )); return; fi
  (( a3 >= b3 ))
}

is_stdin_execution() {
  [[ ! -f "${BASH_SOURCE[0]:-}" ]] || [[ "${BASH_SOURCE[0]:-}" == "-" ]]
}

github_raw_install_url() {
  local repo_url="$1"
  local ref="$2"

  local path
  path="${repo_url#https://github.com/}"
  path="${path#http://github.com/}"
  path="${path%.git}"

  [[ "$path" == */* ]] || return 1
  printf 'https://raw.githubusercontent.com/%s/%s/install.sh' "$path" "$ref"
}

fetch_to_file() {
  local url="$1"
  local out="$2"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$out"
    return 0
  fi

  if command -v wget >/dev/null 2>&1; then
    wget -qO "$out" "$url"
    return 0
  fi

  return 1
}

sanity_check_script_file() {
  local f="$1"

  [[ -s "$f" ]] || die "$(msg bootstrap_empty) ($f)"

  if head -n1 "$f" | grep -qi '<!doctype html'; then
    die "$(msg bootstrap_html)"
  fi

  if ! head -n1 "$f" | grep -q '^#!'; then
    die "$(msg bootstrap_no_shebang)"
  fi
}

# ========== Phase: root escalation ==========
as_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    need_cmd sudo || die "$(msg sudo_missing)"

    if is_stdin_execution; then
      log "$(msg stdin_bootstrap)"

      local url tmp
      url="${INSTALL_SH_URL:-}"

      if [[ -z "$url" ]]; then
        url="$(github_raw_install_url "$REPO_URL" "$REPO_REF")" || \
          die "$(msg install_sh_url_fail)"
      fi

      tmp="$(mktemp -p /tmp toucan-install.XXXXXX.sh)"
      fetch_to_file "$url" "$tmp" || die "$(msg download_fail)"

      sanity_check_script_file "$tmp"
      chmod +x "$tmp"

      exec sudo -E bash "$tmp" "$@"
    fi

    exec sudo -E bash "${BASH_SOURCE[0]}" "$@"
  fi
}

# ========== Phase: distro gate ==========
detect_distro() {
  [[ -r /etc/os-release ]] || die "$(msg os_release_missing)"
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

  die "$(msg distro_unsupported). ID=$id ID_LIKE=$like"
}

# ========== Phase: pacman deps ==========
check_pkg_exists() {
  pacman -Si "$1" >/dev/null 2>&1
}

require_repo_pkgs() {
  local -a missing=()
  local p
  for p in "${REQUIRED_PKGS[@]}"; do
    if ! check_pkg_exists "$p"; then
      missing+=("$p")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    die "$(msg pkg_not_found): ${missing[*]}"
  fi
}

pacman_install() {
  log "$(msg installing_deps): ${REQUIRED_PKGS[*]}"
  pacman -Syu --needed --noconfirm "${REQUIRED_PKGS[@]}"
}

pkg_version() {
  local pkg="$1"
  pacman -Q "$pkg" 2>/dev/null | awk '{print $2}' | head -n1
}

check_pins() {
  local vq vh

  vq="$(pkg_version quickshell || true)"
  [[ -n "$vq" ]] || die "$(msg quickshell_version)"
  semver_ge "$vq" "$MIN_QUICKSHELL" || \
    die "$(msg quickshell_too_old) $vq $(msg min_version_below) $MIN_QUICKSHELL"

  vh="$(pkg_version hyprland || true)"
  [[ -n "$vh" ]] || die "$(msg hyprland_version)"
  semver_ge "$vh" "$MIN_HYPRLAND" || \
    die "$(msg hyprland_too_old) $vh $(msg min_version_below) $MIN_HYPRLAND"

  log "$(msg pins_ok): quickshell $vq >= $MIN_QUICKSHELL; hyprland $vh >= $MIN_HYPRLAND"
}

# ========== Phase: guardrail (inline) ==========
guardrail_layouts() {
  local layouts_dir="$1"

  for layout in "${REQUIRED_LAYOUTS[@]}"; do
    [[ -f "$layouts_dir/$layout" ]] || \
      die "$(msg guardrail_fail): $layout"
  done

  # Validação sintática básica (opcional)
  for qml in "$layouts_dir"/*.qml; do
    if ! grep -q '^import' "$qml"; then
      warn "$qml may be invalid (no import statements)"
    fi
  done

  log "Layout validation passed"
}

# ========== Phase: install global + users ==========
install_global() {
  local src_repo="$1"

  [[ -d "$src_repo/quickshell" ]] || \
    die "$(msg repo_missing_quickshell): $src_repo/quickshell"

  log "$(msg installing_global): $GLOBAL_QUICKSHELL_DIR"
  rm -rf "$GLOBAL_QUICKSHELL_DIR"
  mkdir -p "$INSTALL_GLOBAL"
  cp -a "$src_repo/quickshell" "$GLOBAL_QUICKSHELL_DIR"

  [[ -d "$GLOBAL_QUICKSHELL_DIR" ]] || \
    die "$(msg postcheck_fail_dir): $GLOBAL_QUICKSHELL_DIR"
  [[ -d "$GLOBAL_QUICKSHELL_DIR/customize/layouts" ]] || \
    die "$(msg postcheck_fail_layouts) $GLOBAL_QUICKSHELL_DIR/customize/layouts"
}

apply_existing_users() {
  [[ "$APPLY_EXISTING_USERS" == "1" ]] || return 0

  log "$(msg applying_users)"
  local home user cfg

  for home in /home/*; do
    [[ -d "$home" ]] || continue
    user="$(basename "$home")"
    id "$user" >/dev/null 2>&1 || continue

    cfg="$home/.config/quickshell"
    mkdir -p "$home/.config"

    if [[ -e "$cfg" ]]; then
      log "$(msg skip_user_exists) $user: $cfg"
      continue
    fi

    # Copia (não link) e ajusta ownership
    cp -a "$GLOBAL_QUICKSHELL_DIR" "$cfg"
    chown -R "$user:$user" "$cfg"
  done
}

# ========== Main ==========
main() {
  as_root "$@"
  detect_distro
  require_cmds

  require_repo_pkgs
  pacman_install

  need_cmd git || die "$(msg git_not_available)"

  check_pins

  cleanup_tmp="$(mktemp -d -p /tmp toucan-shell.XXXXXX)"
  log "$(msg cloning_repo): $cleanup_tmp"
  git clone --depth 1 --branch "$REPO_REF" "$REPO_URL" "$cleanup_tmp/repo"

  # Guardrail inline
  guardrail_layouts "$cleanup_tmp/repo/quickshell/customize/layouts"

  install_global "$cleanup_tmp/repo"
  apply_existing_users

  log "$(msg success)"
  log "$(msg success_global): $GLOBAL_QUICKSHELL_DIR"
  log "$(msg success_users)"
}

main "$@"
