# nvim

Configurações customizadas do Neovim (base: LazyVim). Só as partes editadas à mão são versionadas — os defaults do LazyVim ficam fora.

- `lua/config/keymaps.lua` — keymaps extras:
  - `Ctrl+V` em insert/command mode → cola do clipboard do sistema.
  - `Ctrl+C` em visual mode → copia a seleção pro clipboard do sistema.
  - Normal mode preservado (`Ctrl+V` segue como Visual Block, `Ctrl+C` segue como interrompe/cancela).
