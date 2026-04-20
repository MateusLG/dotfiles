# CLAUDE.md

> Instruções para o Claude Code ao trabalhar neste repositório.
> Mantenha respostas em **português (Brasil)**, salvo quando o conteúdo técnico exigir inglês (nomes de variáveis, commits, etc).

---

## 1. Visão geral do projeto

- Dotfiles pessoais do meu setup em **Arch Linux** com **Omarchy / Hyprland**.
- Cada subpasta agrupa configs por ferramenta e tem seu próprio `README.md`.
- Os arquivos aqui são versionados; no sistema vivem em `~/.config/`, `~/.claude/`, `/etc/`, etc. (não há script de symlink — é cópia manual por enquanto).

## 2. Estrutura / stack

- `hypr/` — Hyprland (`bindings.conf`, `input.conf`, `monitors.conf`, `hypridle.conf`)
- `waybar/` — Waybar (`config.jsonc`, `style.css`)
- `claude/` — Claude Code (`settings.json`, `CLAUDE.md` template, `skills/`)
- `omarchy/themes/` — temas customizados do Omarchy (ex: `lg-umbra`)
- `scripts/` — utilitários shell (ex: `work.sh` — VPN $VPN_PROFILE + RDP via Remmina)
- `system/logind.conf.d/` — overrides do `systemd-logind` (ex: tampa fechada com monitor externo)

## 3. Convenções

### 3.1 Código
- Configs em formato nativo da ferramenta (Hyprland conf, JSONC, CSS, shell, systemd drop-in).
- Indentação de 2 espaços em JSON/JSONC; siga o estilo já presente no arquivo ao editar.

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
- Não commitar segredos (senhas de VPN, hosts internos da $VPN_PROFILE, tokens). Se precisar referenciar, use placeholder.
- Não criar scripts de instalação/symlink automáticos sem combinar antes.

## 6. Comandos úteis

- `hyprctl reload` — recarrega o Hyprland após editar configs em `hypr/`.
- `pkill -SIGUSR2 waybar` — recarrega a Waybar.
- `bash scripts/work.sh` — abre VPN + RDP de trabalho.

## 7. Contexto adicional

- Screenshot de referência do desktop atual: `screenshot-2026-04-20_14-30-55.png` (raiz do repo).
- Tema visual em uso: `lg-umbra` (em `omarchy/themes/`).
