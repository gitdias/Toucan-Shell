#!/usr/bin/env bash
set -Eeuo pipefail

LAYOUTS_DIR="${1:-quickshell/customize/layouts}"

die() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }

[[ -d "$LAYOUTS_DIR" ]] || die "Layouts dir não existe: $LAYOUTS_DIR"

# Guardrail 2: nenhuma subpasta dentro de layouts/
if find "$LAYOUTS_DIR" -mindepth 1 -type d -print -quit | grep -q .; then
  die "Guardrail violado: não pode existir subpastas em: $LAYOUTS_DIR"
fi

# Guardrail 2: somente arquivos *.qml no diretório raiz
if find "$LAYOUTS_DIR" -maxdepth 1 -type f ! -name '*.qml' -print -quit | grep -q .; then
  die "Guardrail violado: apenas arquivos *.qml são permitidos em: $LAYOUTS_DIR"
fi

# (Opcional, mas barato) deve existir ao menos 1 layout
if ! find "$LAYOUTS_DIR" -maxdepth 1 -type f -name '*.qml' -print -quit | grep -q .; then
  die "Nenhum layout encontrado em: $LAYOUTS_DIR"
fi

printf "OK: guardrail layouts (flat) passou (%s)\n" "$LAYOUTS_DIR"
