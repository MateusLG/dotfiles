# Meus Dotfiles

Configurações pessoais do meu setup em **macOS (Apple Silicon)**.

## Estrutura

- [`macos/`](macos/) — o setup da máquina: Zsh + Powerlevel10k, Nerd Fonts, Brewfile e instalador
- [`claude/`](claude/) — configurações do Claude Code (`settings.json`, skills, `CLAUDE.md`)
- [`codex/`](codex/) — configurações do Codex CLI (`config.toml`)
- [`agents/`](agents/) — skills compartilhadas entre Codex e Claude Code
- [`nvim/`](nvim/) — customizações do Neovim sobre o LazyVim (keymaps)
- [`vps/`](vps/) — setup de VPS Ubuntu (Hostinger): hardening SSH, ufw, fail2ban, swap, mise

Cada subpasta tem seu próprio `README.md` descrevendo os arquivos.

## Instalação

```bash
git clone https://github.com/MateusLG/dotfiles.git ~/DEV/dotfiles
bash ~/DEV/dotfiles/macos/install.sh
```

Ver [`macos/README.md`](macos/README.md) para os detalhes — inclusive o que
fazer em rede com inspeção TLS, que quebra o Homebrew.

## Histórico

O setup anterior era **Arch Linux com Omarchy / Hyprland**, com uma variante
para WSL2. As configs de `hypr/`, `waybar/`, `omarchy/` (temas), `alacritty/`,
`kitty/`, `ghostty/`, `system/`, `scripts/`, `zsh/` e `wsl/` foram removidas na
migração pro Mac. Estão no histórico do git, é só recuperar se precisar:

```bash
git log --oneline --diff-filter=D -- omarchy/
git checkout <commit>^ -- omarchy/
```
