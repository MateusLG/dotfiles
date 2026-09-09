# agents

Skills compartilhadas entre Codex e Claude Code. Formato [Agent Skills](https://agentskills.io/specification): uma pasta por skill com `SKILL.md` (frontmatter `name` igual ao nome da pasta, `description` de quando usar).

## Skills

- `skills/produzir-sprites/` — fluxo padrão de sprites animados para jogos: image gen do Codex desenha, PixelOver anima via agente de computer use, desenvolvedor integra e valida.

## Instalação

Cópia, não symlink (o instalador de skills do Codex recusa links simbólicos):

```bash
for s in ~/infra/dotfiles/agents/skills/*/; do
  n=$(basename "$s")
  mkdir -p ~/.codex/skills/"$n" ~/.claude/skills/"$n"
  cp "$s"SKILL.md ~/.codex/skills/"$n"/SKILL.md
  cp "$s"SKILL.md ~/.claude/skills/"$n"/SKILL.md
done
```

Ajuste o caminho do repo conforme a máquina (`~/DEV/dotfiles`, `~/dotfiles`, `~/infra/dotfiles`).
