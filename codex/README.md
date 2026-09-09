# codex

Configurações do **Codex CLI** (OpenAI).

## Arquivos

- `config.toml` — vai em `~/.codex/config.toml`. Modelo padrão `gpt-6-astra` (esforço `medium`, tier Fast), personalidade `pragmatic`, aprovação `never` + sandbox `danger-full-access` (equivalente ao bypass do Claude), `file_opener = "none"` (sem link `vscode://`), busca web `live`, memórias entre sessões, multi-agent com backstop de subagente em `gpt-5.6-sol`, notificações do TUI e `resume` voltando pro cwd da sessão.

## Instalação

1. Config global (a partir da raiz do repo):
   ```bash
   cp codex/config.toml ~/.codex/config.toml
   ```
   Se o `~/.codex/config.toml` já existir, preservar os blocos `[projects.*]` e `[marketplaces.*]` dele (ver Notas).
2. Superpowers (mesmo plugin usado no Claude Code, via marketplace oficial da OpenAI):
   ```bash
   codex plugin add superpowers@openai-curated-remote
   ```
   O estado do plugin não fica no `config.toml`, então não há bloco pra versionar. `codex plugin list | grep superpowers` confirma.

## Notas

- `[projects."<path>"] trust_level` e `[marketplaces.*]` são escritos pelo próprio Codex com caminho absoluto da máquina. **Não** versionar — mesmo papel do `settings.local.json` do Claude.
- Depois de atualizar o Codex (`npm i -g @openai/codex@latest`), o daemon `app-server` compartilhado continua rodando a versão antiga e a lista de modelos fica presa nela. Conferir com `codex app-server daemon version` (`cliVersion` × `appServerVersion`). Se divergir, matar os processos do daemon (`pgrep -af 'app-server|code-mode-host'`); a próxima sessão sobe um novo. Isso derruba as sessões abertas (recuperáveis com `codex resume`). `codex app-server daemon restart` não funciona quando o daemon foi iniciado pela TUI.
- Referência oficial de config: https://learn.chatgpt.com/docs/config-file/config-reference
