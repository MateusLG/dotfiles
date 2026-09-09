#!/usr/bin/env bash
# Instala os dotfiles no macOS (Apple Silicon). Idempotente.
# Uso: bash macos/install.sh
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"

# --skip-brew: instala configs sem os pacotes (útil quando o Homebrew ainda
# não foi instalado — ele pede senha de sudo e não dá pra automatizar).
SKIP_BREW=0
[[ "${1:-}" == "--skip-brew" ]] && SKIP_BREW=1

info() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }

# Move o arquivo/link existente pra .bak-<timestamp> antes de sobrescrever.
backup() {
  local target="$1"
  if [[ -e "$target" || -L "$target" ]]; then
    mv "$target" "$target.bak-$STAMP"
    warn "backup: $target -> $target.bak-$STAMP"
  fi
}

link() {
  local src="$1" dst="$2"
  # Já aponta pro lugar certo: não faz nada.
  [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]] && return 0
  mkdir -p "$(dirname "$dst")"
  backup "$dst"
  ln -s "$src" "$dst"
  info "link: $dst -> $src"
}

# ─────────────────────────── Homebrew ────────────────────────────
if ! command -v brew &>/dev/null && [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

if command -v brew &>/dev/null; then
  info "instalando pacotes (brew bundle)"
  brew bundle --file="$REPO/macos/Brewfile"
elif (( SKIP_BREW )); then
  warn "Homebrew ausente — pulando os pacotes (--skip-brew)."
  warn "Depois: instale o brew e rode 'brew bundle --file=$REPO/macos/Brewfile'"
else
  warn "Homebrew não encontrado. Instale antes:"
  warn '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  warn "Ou rode com --skip-brew pra instalar só as configs."
  exit 1
fi

# ───────────────────────── Powerlevel10k ─────────────────────────
P10K_DIR="$HOME/.config/zsh/powerlevel10k"
if [[ -d "$P10K_DIR/.git" ]]; then
  info "powerlevel10k já clonado, atualizando"
  git -C "$P10K_DIR" pull --ff-only
else
  info "clonando powerlevel10k"
  mkdir -p "$HOME/.config/zsh"
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
fi

# ──────────────────────────── Shell ──────────────────────────────
link "$REPO/macos/zshrc"   "$HOME/.zshrc"
link "$REPO/zsh/p10k.zsh"  "$HOME/.p10k.zsh"

# ─────────────────────────── Ghostty ─────────────────────────────
link "$REPO/macos/ghostty/config" "$HOME/.config/ghostty/config"
link "$REPO/macos/ghostty/themes" "$HOME/.config/ghostty/themes"

# ──────────────────────────── Claude ─────────────────────────────
link "$REPO/claude/CLAUDE.md"     "$HOME/.claude/CLAUDE.md"
link "$REPO/claude/settings.json" "$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude/skills"
for f in "$REPO"/claude/skills/*.md; do
  link "$f" "$HOME/.claude/skills/$(basename "$f")"
done

# ───────────────────────────── Codex ─────────────────────────────
# Symlink aqui seria destrutivo: o ~/.codex/config.toml é escrito pelo próprio
# Codex e guarda estado da máquina ([marketplaces.*], [mcp_servers.*],
# [projects.*]) com paths absolutos. Merge em vez de sobrescrever.
CODEX_CFG="$HOME/.codex/config.toml"
if [[ -f "$CODEX_CFG" ]]; then
  cp "$CODEX_CFG" "$CODEX_CFG.bak-$STAMP"
  info "merge do config do Codex (backup em $CODEX_CFG.bak-$STAMP)"
  python3 "$REPO/macos/merge-codex-config.py" \
    "$REPO/codex/config.toml" "$CODEX_CFG.bak-$STAMP" "$CODEX_CFG"
else
  mkdir -p "$HOME/.codex"
  cp "$REPO/codex/config.toml" "$CODEX_CFG"
  info "config do Codex copiado"
fi

# ──────────── Skills compartilhadas (cópia, não symlink) ─────────
# O instalador de skills do Codex recusa symlink — ver agents/README.md.
for s in "$REPO"/agents/skills/*/; do
  n="$(basename "$s")"
  mkdir -p "$HOME/.codex/skills/$n" "$HOME/.claude/skills/$n"
  cp "$s/SKILL.md" "$HOME/.codex/skills/$n/SKILL.md"
  cp "$s/SKILL.md" "$HOME/.claude/skills/$n/SKILL.md"
  info "skill copiada: $n"
done

# ───────────────────────────── Neovim ────────────────────────────
# O keymaps.lua é uma customização SOBRE o LazyVim; sem ele, não faz nada.
if [[ ! -d "$HOME/.config/nvim" ]]; then
  info "instalando o starter do LazyVim"
  git clone https://github.com/LazyVim/starter "$HOME/.config/nvim"
  rm -rf "$HOME/.config/nvim/.git"
fi
link "$REPO/nvim/lua/config/keymaps.lua" "$HOME/.config/nvim/lua/config/keymaps.lua"

info "pronto. Abra um terminal novo (ou 'exec zsh')."
