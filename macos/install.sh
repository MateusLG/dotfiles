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
  # O brew cria $HOMEBREW_PREFIX/share gravável pelo grupo. Como ele é
  # ancestral dos diretórios de completion, o compinit condena a árvore
  # inteira, aborta o autocomplete e ainda faz uma pergunta a cada shell
  # novo. Volta a cada brew update, por isso fica aqui e não só no README.
  if [[ -d "$HOMEBREW_PREFIX/share" ]]; then
    chmod -R go-w "$HOMEBREW_PREFIX/share" 2>/dev/null || true
    info "permissões de $HOMEBREW_PREFIX/share ajustadas (compinit)"
  fi
elif (( SKIP_BREW )); then
  warn "Homebrew ausente — pulando os pacotes (--skip-brew)."
  warn "Depois: instale o brew e rode 'brew bundle --file=$REPO/macos/Brewfile'"
else
  warn "Homebrew não encontrado. Instale antes:"
  warn '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  warn "Ou rode com --skip-brew pra instalar só as configs."
  exit 1
fi

# ──────────────────────────── Fontes ─────────────────────────────
info "instalando Nerd Fonts"
bash "$REPO/macos/install-nerdfonts.sh"

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
link "$REPO/macos/p10k.zsh" "$HOME/.p10k.zsh"

# ──────────────────────────── Git ────────────────────────────────
link "$REPO/macos/gitconfig"        "$HOME/.gitconfig"
link "$REPO/macos/gitignore_global" "$HOME/.gitignore_global"


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
  CODEX_TMP="$(mktemp)"
  python3 "$REPO/macos/merge-codex-config.py" \
    "$REPO/codex/config.toml" "$CODEX_CFG" "$CODEX_TMP"
  # Só toca no arquivo (e só faz backup) se o merge mudou alguma coisa —
  # senão cada execução deixaria um .bak idêntico pra trás.
  if cmp -s "$CODEX_TMP" "$CODEX_CFG"; then
    info "config do Codex já em dia"
    rm -f "$CODEX_TMP"
  else
    cp "$CODEX_CFG" "$CODEX_CFG.bak-$STAMP"
    mv "$CODEX_TMP" "$CODEX_CFG"
    info "merge do config do Codex (backup em $CODEX_CFG.bak-$STAMP)"
  fi
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

# ─────────────────────────── power-watch ─────────────────────────
# Mantém o Mac acordado na tomada e dormindo na bateria (ver README).
link "$REPO/macos/power-watch.sh" "$HOME/.local/bin/power-watch"
PW_PLIST="$HOME/Library/LaunchAgents/com.mateus.power-watch.plist"
# launchd não gosta de symlink em LaunchAgents: copia e só recarrega se mudou.
if ! cmp -s "$REPO/macos/com.mateus.power-watch.plist" "$PW_PLIST"; then
  mkdir -p "$(dirname "$PW_PLIST")"
  cp "$REPO/macos/com.mateus.power-watch.plist" "$PW_PLIST"
  launchctl bootout "gui/$(id -u)/com.mateus.power-watch" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$PW_PLIST"
  info "power-watch carregado no launchd"
fi
if [[ ! -f /etc/sudoers.d/pmset ]]; then
  warn "power-watch precisa da regra de sudo (pede senha — precisa ser você):"
  warn "  sudo install -m 0440 -o root -g wheel $REPO/macos/sudoers-pmset /etc/sudoers.d/pmset"
fi

# ───────────────────────────── Neovim ────────────────────────────
# O keymaps.lua é uma customização SOBRE o LazyVim; sem ele, não faz nada.
if [[ ! -d "$HOME/.config/nvim" ]]; then
  info "instalando o starter do LazyVim"
  git clone https://github.com/LazyVim/starter "$HOME/.config/nvim"
  rm -rf "$HOME/.config/nvim/.git"
fi
link "$REPO/nvim/lua/config/keymaps.lua" "$HOME/.config/nvim/lua/config/keymaps.lua"

info "pronto. Abra um terminal novo (ou 'exec zsh')."
warn "Terminal.app: configure a fonte 'MesloLGS NF' em"
warn "  Terminal > Configurações > Perfis > Texto > Fonte."
warn "  Sem Nerd Font, o prompt do p10k vira caixinhas."
