# zsh

Configuração do **Zsh + Powerlevel10k** substituindo o bash+starship padrão do Omarchy.

## Arquivos

- `p10k.zsh` — vai em `~/.p10k.zsh`. Gerado pelo assistente `p10k configure` na primeira execução.

## Dependências (pacman/yay)

- `zsh`, `zsh-completions`, `zsh-autosuggestions`, `zsh-syntax-highlighting`
- Powerlevel10k clonado em `~/.config/zsh/powerlevel10k` (mantido fora do AUR; atualizar com `git -C ~/.config/zsh/powerlevel10k pull`)

## Instalação

1. Copiar configs:
   ```bash
   cp ~/DEV/dotfiles/zsh/zshrc ~/.zshrc
   ```
2. Trocar shell padrão:
   ```bash
   chsh -s /usr/bin/zsh
   ```
3. Abrir nova sessão → rodar `p10k configure` pra gerar `~/.p10k.zsh`.
4. (Opcional) salvar o `~/.p10k.zsh` gerado de volta no repo:
   ```bash
   cp ~/.p10k.zsh ~/DEV/dotfiles/zsh/p10k.zsh
   ```
