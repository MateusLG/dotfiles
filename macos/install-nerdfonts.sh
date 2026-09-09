#!/usr/bin/env bash
# Instala as Nerd Fonts em ~/Library/Fonts (não precisa de sudo). Idempotente.
# Equivalente macOS do wsl/install-nerdfonts.ps1.
#
#  - MesloLGS NF: a fonte que o p10k recomenda, direto do repo do romkatv
#    (mesmas 4 variantes que o script do Windows instala).
#  - JetBrainsMono Nerd Font: a que o macos/ghostty/config pede.
set -euo pipefail

DEST="$HOME/Library/Fonts"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$DEST"

info() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }

# ─────────────────────────── MesloLGS NF ─────────────────────────
MESLO_BASE="https://github.com/romkatv/powerlevel10k-media/raw/master"
for v in "Regular" "Bold" "Italic" "Bold Italic"; do
  f="MesloLGS NF ${v}.ttf"
  if [[ -f "$DEST/$f" ]]; then
    info "já instalada: $f"
    continue
  fi
  info "baixando: $f"
  curl -fsSL -o "$DEST/$f" "$MESLO_BASE/${f// /%20}"
done

# ──────────────────── JetBrainsMono Nerd Font ────────────────────
if compgen -G "$DEST/JetBrainsMonoNerdFont-*.ttf" >/dev/null; then
  info "já instalada: JetBrainsMono Nerd Font"
else
  ver="$(curl -fsSL https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest \
         | grep '"tag_name"' | head -1 | cut -d'"' -f4)"
  info "baixando JetBrainsMono Nerd Font ($ver)"
  curl -fsSL -o "$TMP/jbm.zip" \
    "https://github.com/ryanoasis/nerd-fonts/releases/download/${ver}/JetBrainsMono.zip"
  unzip -oq "$TMP/jbm.zip" -d "$TMP/jbm"
  # Só as 4 variantes principais — o zip traz dezenas (Mono/Propo/NL etc).
  for v in Regular Bold Italic BoldItalic; do
    src="$TMP/jbm/JetBrainsMonoNerdFont-$v.ttf"
    [[ -f "$src" ]] && cp "$src" "$DEST/" && info "instalada: $(basename "$src")"
  done
fi

info "pronto. Fontes em $DEST"
info "Ghostty: já aponta pra JetBrainsMono Nerd Font (macos/ghostty/config)."
info "Outros terminais: configurar 'MesloLGS NF' ou 'JetBrainsMono Nerd Font'."
