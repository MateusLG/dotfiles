# macos

Configuração adaptada pro **macOS (Apple Silicon)**. Terceira variante do zsh,
ao lado de [`zsh/`](../zsh/) (Omarchy/Arch) e [`wsl/`](../wsl/) (WSL2/Arch).

Partiu do `wsl/zshrc` — que já é a versão sem Omarchy/Hyprland — e trocou o que
era específico de Linux/Windows.

## Arquivos

- `zshrc` — vai em `~/.zshrc`.
- `ghostty/config` + `ghostty/themes/lg-abissal` — vão em `~/.config/ghostty/`.
- `Brewfile` — dependências. `brew bundle --file=macos/Brewfile`.
- `install.sh` — instalador idempotente (symlinks + backup do que existia).
- `merge-codex-config.py` — merge do config do Codex (ver abaixo).

## Diferenças em relação ao `wsl/zshrc`

| | WSL/Arch | macOS |
|---|---|---|
| Gerenciador | pacman, paths em `/usr/share/...` | Homebrew, `$HOMEBREW_PREFIX/share/...` |
| `open()` | wrapper de `wslview`/`explorer.exe` | **removido** — o macOS já tem `open` nativo, e a função atropelava ele |
| `chrome()` | `cmd.exe /c start chrome` + `wslpath` | `open -a "Google Chrome"` |
| `sff()` | `find -printf` (GNU) | glob do zsh `**/*(.omN)` — o find BSD não tem `-printf` |
| `fzf` | `/usr/share/fzf/*.zsh` | `fzf --zsh`, com fallback pros arquivos do brew |
| Godot | aliases `mowgul`/`icebite`/`pingado` em `/mnt/c/...` | **removidos** (paths do host Windows) |
| PATH | — | `brew shellenv` antes do `compinit`, senão as completions não entram no FPATH |
| `chsh` | necessário | desnecessário, zsh já é o shell padrão do macOS |

Mantidos iguais: history, completion, aliases `eza`/git/`..`, `zd` do zoxide,
`n()`, `claude-sessions`, mise, p10k.

## Ghostty

O `ghostty/config` do Omarchy fazia `config-file = ?"~/.config/omarchy/current/theme/ghostty.conf"`,
que não existe fora do Omarchy. O tema [`lg-abissal`](../omarchy/themes/lg-abissal/)
foi portado do `colors.toml` pro formato de tema do Ghostty.

Outras mudanças: `font-size` 9 → 14 (Retina), `background-opacity` 0.5 → 0.92 +
`background-blur` (o 0.5 contava com o blur do Hyprland), removidos
`gtk-toolbar-style` e `async-backend = epoll` (Linux-only), e os keybinds de
`Insert` (tecla que não existe em teclado Mac — `cmd+c`/`cmd+v` já são padrão).

## Codex

O `~/.codex/config.toml` é escrito pelo próprio Codex e guarda estado da
máquina (`[marketplaces.*]`, `[mcp_servers.*]`, `[projects.*]`, `notify`) com
paths absolutos — copiar o do repo por cima destrói isso. O
`merge-codex-config.py` junta os dois: preferências do repo mandam, blocos da
máquina são preservados. Roda dentro do `install.sh`, com backup antes.

## O que NÃO se aplica ao macOS

`hypr/`, `waybar/`, `omarchy/` (Wayland/Arch), `system/` (systemd), `wsl/`,
e `scripts/` (`work.sh` depende de FortiClient+Remmina; `lgfetch.sh` lê o tema
atual do Omarchy).

## Instalação

```bash
# 1. Homebrew (pede senha de sudo — precisa ser você)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 2. Resto
bash ~/DEV/dotfiles/macos/install.sh
```

Depois, `p10k configure` se quiser regerar o `~/.p10k.zsh` (o instalador linka o
do `zsh/`, gerado no Linux — funciona, mas foi feito pra outra fonte/terminal).

O instalador move qualquer arquivo existente pra `<arquivo>.bak-<timestamp>`
antes de criar o symlink.
