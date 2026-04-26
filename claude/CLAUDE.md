# CLAUDE.md — Preferências globais

> Instruções globais do usuário (Mateus Lira / LGMateus) para o Claude Code.
> Aplicam-se a **todos** os projetos. Cada repositório pode ter seu próprio `CLAUDE.md` que sobrescreve ou complementa este.

---

## 1. Sobre o usuário

- Desenvolvedor fullstack com foco em **backend**, brasileiro.
- Setup: **Arch Linux + Hyprland + Omarchy**, tema `lg-umbra`. Editor principal: **Neovim**. Escreve **C** com gosto, usa **LaTeX** para documentos.
- Stacks recorrentes: **Python (FastAPI, Typer, Pydantic v2)**, **TypeScript / Next.js**, **PostgreSQL**, deploy em **Railway**.
- Terceiriza redação de texto longo para IA — gosta de respostas que ele possa colar/usar direto.

## 2. Idioma e tom

- Respostas **sempre em PT-BR**, diretas e enxutas. Nada de enrolação, nada de "embelezar".
- Honesto sobre limitações e trade-offs. Não inventar decisões — perguntar quando houver dúvida real.
- Identificadores em código:
  - Projeto **internacional / open-source** → tudo em inglês (código, commits, docs no PR).
  - Projeto **local / interno** → PT-BR ok em comentários e docs; commits podem seguir o idioma do projeto.
  - **Nunca misturar idiomas dentro de um mesmo arquivo de código.**

## 3. Fluxo de trabalho

- Antes de implementar algo grande/não-trivial: **propor abordagem e validar** com o usuário antes de mexer no código.
- Para ações caras ou irreversíveis (gastar crédito em API paga, regerar artefatos em lote, apagar dados, force-push), **pedir confirmação explícita**.
- Comandos interativos (login, chave de API, `gcloud auth`, etc): pedir pro usuário rodar com o prefixo `!`.
- Commits pequenos, atômicos e coerentes. Não misturar refactor com feature.
- **Nunca usar `--no-verify`** nem pular lint/type-check/testes pra "passar logo".
- **Nunca adicionar `Co-Authored-By: Claude`** nos commits (`includeCoAuthoredBy` está desligado em `settings.json`).

## 4. Estilo de código

- **Type hints obrigatórios** em Python; mypy strict sempre que o projeto suportar.
- **TypeScript estrito** (`strict: true`).
- Sem comentários decorativos. Só comentar quando o **porquê** não for óbvio (constraint escondido, workaround, decisão contra-intuitiva).
- Não criar abstrações antecipadas. Três linhas parecidas é melhor que abstração prematura.
- Não criar arquivos de documentação (`*.md`, README) sem o usuário pedir.
- Não introduzir build system, dependências ou ferramentas extras "pra facilitar" — manter o escopo do que foi pedido.

## 5. Ferramentas e gerenciadores

- **Python:** sempre `uv`. Não usar `pip`, `poetry` ou `pyenv` salvo se o projeto já usa.
- **Node:** `npm` por padrão; respeitar `package-lock.json`/`pnpm-lock.yaml` existente.
- **Lint/format Python:** Ruff (lint + format) + Mypy strict.
- **Antes de usar API/framework recente** (Next 16, React 19, fal.ai, libs novas): conferir a documentação local (`node_modules/<pkg>/dist/docs/`) ou docs oficiais. **Não confiar em memória** sobre APIs — modelos saem rápido e endpoints mudam.

## 6. Convenções de commit (padrão)

- Idioma segue o projeto (inglês em projetos internacionais; PT-BR nos locais).
- Imperativo curto, minúsculas.
- Prefixos aceitos: `add:`, `fix:`, `update:`, `chore:`, `refactor:`, `docs:`, `feat:`.
- Conventional commits (`feat(escopo): ...`) ok quando o projeto já adota.
- Exemplo bom: `add: config de idle do hypr (screensaver, dpms, lock)`.

## 7. Estética e UI (quando aplicável)

Inimigo principal: **cara de "feito por IA"**. Evitar a todo custo:

- Gradientes roxo/azul tipo "SaaS genérico".
- Glassmorphism decorativo, animações gratuitas (rotação/fade sem propósito).
- Cards de projetos em grid simétrico padronizado.
- Estrutura clichê: hero → sobre → skills → projetos → contato.
- Seções "Skills/Tecnologias" como grid de ícones.

Direção preferida: dark mode, paleta restrita, tipografia forte, muito whitespace, animações sutis com propósito, tratamento **editorial** (não-templatizado) por seção.

Referências: apple.com, samsung.com, claude.com, anthropic.com.

## 8. O que NÃO fazer

- Não tomar ações destrutivas (force push, `reset --hard`, `rm -rf`, drop de tabela) sem confirmação explícita do usuário.
- Não criar PRs/commits/pushes sem ser pedido.
- Não usar tom corporativo, emojis ou exclamações em respostas.
- Não responder com listas gigantes/headers quando uma frase resolve.
- Não terminar resposta com "resumo do que fiz" se o diff já mostra — ele lê o diff.
- Não adicionar fallbacks/validações pra cenários que não acontecem ("trust internal code").

## 9. Auto-memory

- Memória persistente em `~/.claude/projects/-home-lgmateus-DEV/memory/`.
- Atualizar memórias quando aprender preferência nova, decisão de projeto importante ou correção de rumo.
- Antes de recomendar algo baseado em memória antiga, **verificar se ainda é verdade** (arquivo existe, função existe, etc).

## 10. Dúvidas frequentes

- "Roda os testes?" → sim, sempre antes de marcar tarefa como concluída.
- "Faço commit?" → **não**, salvo se o usuário pediu explicitamente.
- "Crio um README?" → **não**, salvo se o usuário pediu.
- "Posso instalar essa lib nova?" → pergunta antes.
