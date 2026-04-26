# claude

Configurações do **Claude Code** (CLI da Anthropic).

## Arquivos

- `settings.json` — vai em `~/.claude/settings.json`. Permissões em modo bypass, sem `Co-Authored-By` em commits, `effortLevel: high`, plugins habilitados (`frontend-design`).
- `CLAUDE.md` — vai em `~/.claude/CLAUDE.md`. Instruções **globais** (preferências do usuário, idioma, fluxo, estilo de código, anti-IA).
- `skills/` — vai em `~/.claude/skills/`. Skills customizadas:
  - `gerar-pdf.md` — converte HTML em PDF via Chromium headless.
  - `security-scanner.md` — análise de segurança em mudanças pendentes.
- `templates/CLAUDE.md` — **não** vai pro `~/.claude/`. É o template por-projeto, pra copiar dentro de repos novos como ponto de partida do `CLAUDE.md` daquele projeto.

## Instalação

1. Configs globais:
   ```bash
   cp ~/DEV/dotfiles/claude/settings.json ~/.claude/settings.json
   cp ~/DEV/dotfiles/claude/CLAUDE.md     ~/.claude/CLAUDE.md
   ```
2. Skills:
   ```bash
   mkdir -p ~/.claude/skills
   cp ~/DEV/dotfiles/claude/skills/*.md ~/.claude/skills/
   ```
3. Em um projeto novo, pra criar o `CLAUDE.md` local:
   ```bash
   cp ~/DEV/dotfiles/claude/templates/CLAUDE.md ./CLAUDE.md
   # depois preencher as seções
   ```

## Notas

- `~/.claude/settings.local.json` **não** é versionado — guarda allows específicos da máquina (rotas absolutas, permissões pontuais).
- O `~/.claude/CLAUDE.md` global é sobrescrito por qualquer `CLAUDE.md` de projeto, então as instruções aqui valem como base.
