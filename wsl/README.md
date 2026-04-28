# wsl

Configuração do **Zsh + Powerlevel10k** adaptada pra **WSL2 + Arch Linux** (sem Omarchy/Hyprland).

Variante do `zsh/zshrc`: remove o que depende de ambiente gráfico Linux (FortiClient, Remmina, Hyprland, Kitty, funções do Omarchy) e adapta o `open()` pra usar o host Windows.

## Arquivos

- `zshrc` — vai em `~/.zshrc`. Igual ao `zsh/zshrc` em estrutura (history, completion, aliases `eza`/`fzf`/`zoxide`, git, plugins, p10k), com as diferenças:
  - **Removido:** `OMARCHY_PATH`, loop de `fns/*`, `/opt/forticlient` no PATH, alias `fortinet`, alias `rdp-embratur`, branch `xterm-kitty` do `ff`.
  - **Adaptado:** `open()` usa `wslview` (do AUR `wslu`) com fallback `explorer.exe`.

O `p10k.zsh` é reaproveitado do `zsh/`: instala via symlink `ln -sf ~/DEV/dotfiles/zsh/p10k.zsh ~/.p10k.zsh`.

## Dependências (pacman)

- `zsh`, `zsh-completions`, `zsh-autosuggestions`, `zsh-syntax-highlighting`
- `eza`, `fzf`, `zoxide`, `bat`, `fastfetch`, `mise`
- Powerlevel10k clonado em `~/.config/zsh/powerlevel10k` (atualizar com `git -C ~/.config/zsh/powerlevel10k pull`)

Opcional (AUR): `wslu` pro `wslview`. Sem ele, `open()` cai em `explorer.exe`.

## Instalação

1. Instalar pacotes:
   ```bash
   sudo pacman -S --needed zsh zsh-completions zsh-autosuggestions zsh-syntax-highlighting \
     eza fzf zoxide bat fastfetch mise
   ```
2. Clonar Powerlevel10k:
   ```bash
   mkdir -p ~/.config/zsh
   git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ~/.config/zsh/powerlevel10k
   ```
3. Copiar zshrc e linkar p10k:
   ```bash
   cp ~/DEV/dotfiles/wsl/zshrc ~/.zshrc
   ln -sf ~/DEV/dotfiles/zsh/p10k.zsh ~/.p10k.zsh
   ```
4. Trocar shell padrão:
   ```bash
   chsh -s /usr/bin/zsh
   ```
5. Fechar e reabrir o WSL (`wsl --terminate <distro>` no PowerShell).
