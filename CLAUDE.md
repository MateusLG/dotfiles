# CLAUDE.md

> Instruções para o Claude Code ao trabalhar neste repositório.
> Mantenha respostas em **português (Brasil)**, salvo quando o conteúdo técnico exigir inglês (nomes de variáveis, commits, etc).

---

## 1. Visão geral do projeto

- Dotfiles pessoais do meu setup em **macOS (Apple Silicon)**.
- Cada subpasta agrupa configs por ferramenta e tem seu próprio `README.md`.
- A instalação é feita por `macos/install.sh`: cria symlinks do repo pro
  sistema (`~/.zshrc`, `~/.claude/`, etc), com backup do que já existia.

## 2. Estrutura / stack

- `macos/` — Zsh + Powerlevel10k, Nerd Fonts, Brewfile, instalador
- `claude/` — Claude Code (`settings.json`, `CLAUDE.md` global, `skills/`)
- `codex/` — Codex CLI (`config.toml`)
- `agents/` — skills compartilhadas Codex + Claude Code (`skills/<nome>/SKILL.md`)
- `nvim/` — customizações sobre o LazyVim (`lua/config/keymaps.lua`)
- `vps/` — VPS Ubuntu: hardening, ufw, fail2ban, Komodo/Traefik, stacks

## 3. Convenções

### 3.1 Código
- Configs em formato nativo da ferramenta (TOML, JSON, shell, Lua).
- Indentação de 2 espaços em JSON; siga o estilo já presente no arquivo ao editar.
- Shell: `bash` com `set -euo pipefail` nos scripts, e idempotência —
  rodar duas vezes tem que dar o mesmo resultado que rodar uma.

### 3.2 Commits
- Idioma: **português**, mensagem em minúsculas, no infinitivo/imperativo curto.
- Prefixos observados no histórico: `add:`, `fix:` — use o que melhor descrever a mudança.
- Exemplo: `add: config de idle do hypr (screensaver, dpms, lock)`.
- `includeCoAuthoredBy` está desligado em `claude/settings.json` — **não** adicione `Co-Authored-By: Claude` nos commits.

### 3.3 Branches / PRs
- Trabalho direto na `main`, sem PRs. Commits pequenos e atômicos.

## 4. Preferências de colaboração

- Antes de editar uma config nova, dê uma olhada no `README.md` da subpasta para entender o propósito.
- Ao criar arquivos novos numa subpasta, atualize o `README.md` correspondente.

## 5. O que evitar

- Não adicionar `Co-Authored-By` em commits.
- Não commitar segredos nem info corporativa (usuários de VPN, hosts/IPs
  internos, nomes de perfis, tokens, certificados de rede). Se precisar
  referenciar, use placeholder ou variável de ambiente.
- Não versionar arquivo que a própria ferramenta reescreve com estado da
  máquina — `~/.claude/settings.local.json` e os blocos `[projects.*]` /
  `[marketplaces.*]` / `[mcp_servers.*]` do Codex são os casos conhecidos.
  Para o Codex existe `macos/merge-codex-config.py`, que junta as
  preferências do repo com o estado local em vez de sobrescrever.

## 6. Comandos úteis

- `bash macos/install.sh` — instala tudo (idempotente). `--skip-brew` pula os pacotes.
- `brew bundle --file=macos/Brewfile` — só os pacotes.
- `bash macos/install-nerdfonts.sh` — só as fontes.
- `exec zsh` — recarrega o shell após editar `macos/zshrc`.

## 7. Contexto adicional

- O setup anterior era Arch Linux com Omarchy / Hyprland (e uma variante
  WSL2). Foi removido na migração pro Mac, mas está no histórico do git.
- A rede de trabalho faz inspeção TLS (FortiGate), o que quebra Homebrew,
  npm e pip. Ver a seção correspondente em `macos/README.md`.
