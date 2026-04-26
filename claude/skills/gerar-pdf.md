---
name: gerar-pdf
description: Gera PDF a partir de um arquivo HTML usando Chromium headless, com a flag --virtual-time-budget=10000 para garantir o carregamento de fontes externas (Google Fonts) antes da renderização. Organiza os arquivos em html/, pdf/ e assets/ na raiz do repositório. Use quando o usuário pedir para converter HTML em PDF.
---

# Contexto

Conversão de HTML para PDF via **Chromium headless** (`/usr/bin/chromium`). Sem build, sem dependências externas — só o binário do Chromium.

# Estrutura do repositório

A skill assume e impõe a seguinte estrutura na raiz do repositório:

```
<repo>/
├── html/     # fontes HTML
├── pdf/      # PDFs gerados (saída)
└── assets/   # logos, imagens e outros recursos referenciados pelos HTMLs
```

- Antes de gerar, garanta que `html/`, `pdf/` e `assets/` existam: `mkdir -p html pdf assets assets`.
- Os HTMLs de entrada vivem em `html/`. Se o usuário entregar um `.html` solto na raiz, **mova-o** para `html/` antes de gerar.
- Os PDFs de saída vão **sempre** para `pdf/`. Não gere PDF na raiz nem em outra pasta.
- Logos, imagens e qualquer asset referenciado pelos HTMLs vivem **sempre** em `assets/`. Se o usuário entregar um asset solto (na raiz ou dentro de `html/`), **mova-o** para `assets/` e ajuste o `src`/`href` no HTML para `../assets/<arquivo>`.
- Os comandos devem rodar **a partir da raiz do repo**, para que caminhos relativos (`../assets/...`) dentro dos HTMLs resolvam corretamente.

# Regras Gerais

- **Flag obrigatória:** `--virtual-time-budget=10000`. Sem ela, o Chromium não espera fontes externas (Google Fonts) terminarem de carregar e elas caem para serif/sans default silenciosamente — o PDF sai visivelmente menor.
- **Flags fixas:** `--headless`, `--disable-gpu`, `--no-pdf-header-footer`.
- **Antes de gerar em massa**, confirmar com o usuário.

# Comando padrão (arquivo único)

```bash
mkdir -p html pdf assets
chromium --headless --disable-gpu --no-pdf-header-footer \
  --virtual-time-budget=10000 \
  --print-to-pdf=pdf/<nome>.pdf \
  html/<nome>.html
```

# Comando padrão (lote)

```bash
mkdir -p html pdf assets
for f in html/*.html; do
  name=$(basename "$f" .html)
  chromium --headless --disable-gpu --no-pdf-header-footer \
    --virtual-time-budget=10000 \
    --print-to-pdf="pdf/${name}.pdf" "$f"
done
```

# Validação pós-geração

Após gerar, rode `ls -la pdf/<nome>.pdf` e reporte o tamanho. Se um PDF sair anormalmente pequeno comparado aos demais (ou ao esperado), avise — provável falha de carregamento de fonte.

# O que evitar

- Omitir `--virtual-time-budget=10000`.
- Gerar PDF fora de `pdf/`, ler HTML fora de `html/` ou deixar assets fora de `assets/`.
- Rodar o comando de dentro de `html/` (quebra caminhos relativos como `../assets/...`).
- Sugerir ferramentas alternativas (wkhtmltopdf, weasyprint, puppeteer) sem o usuário pedir.
