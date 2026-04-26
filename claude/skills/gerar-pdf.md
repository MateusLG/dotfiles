---
name: gerar-pdf
description: Converte HTML em PDF via Chromium headless, organizando os arquivos em html/, pdf/ e assets/ na raiz do repositório. Use a flag --virtual-time-budget=10000 quando o HTML depende de fontes/CSS externos (ex. Google Fonts). Use quando o usuário pedir para gerar/converter PDF a partir de HTML. NÃO use para gerar PDF a partir de Markdown, docs Office, LaTeX ou imagens — esta skill é exclusiva para entrada HTML.
---

# Contexto

Conversão de HTML para PDF via **Chromium headless**. Sem build, sem dependências externas — só o binário do Chromium disponível no sistema.

# Estrutura do repositório

A skill assume e impõe a seguinte estrutura na raiz do repositório:

```
<repo>/
├── html/     # fontes HTML
├── pdf/      # PDFs gerados (saída)
└── assets/   # logos, imagens e outros recursos referenciados pelos HTMLs
```

- Antes de gerar, garanta que `html/`, `pdf/` e `assets/` existam: `mkdir -p html pdf assets`.
- Os HTMLs de entrada vivem em `html/`. Se o usuário entregar um `.html` solto na raiz, **mova-o** para `html/` antes de gerar.
- Os PDFs de saída vão **sempre** para `pdf/`. Não gere PDF na raiz nem em outra pasta.
- Logos, imagens e qualquer asset referenciado pelos HTMLs vivem **sempre** em `assets/`. Se o usuário entregar um asset solto (na raiz ou dentro de `html/`), **mova-o** para `assets/` e ajuste o `src`/`href` no HTML para `../assets/<arquivo>`.
- Os comandos devem rodar **a partir da raiz do repo**, para que caminhos relativos (`../assets/...`) dentro dos HTMLs resolvam corretamente.

# Detecção do binário

Não assuma `/usr/bin/chromium`. Detecte o binário disponível antes de gerar:

```bash
CHROMIUM=$(command -v chromium || command -v chromium-browser || command -v google-chrome-stable || command -v google-chrome || command -v chrome)
[ -z "$CHROMIUM" ] && { echo "Chromium não encontrado no PATH"; exit 1; }
```

Use `$CHROMIUM` em vez de hardcodar o caminho.

# Quando usar `--virtual-time-budget`

A flag `--virtual-time-budget=10000` força o Chromium a esperar recursos remotos (ex: Google Fonts) antes de imprimir. **Aplique condicionalmente:**

- **Use** quando o HTML referencia recursos externos: `<link href="https://fonts.googleapis.com/...">`, CDNs de CSS/JS, imagens remotas.
- **Não use** quando o HTML é 100% local (sem `http://` ou `https://` no `<head>`/`<body>`) — só adiciona latência sem benefício.

Antes de decidir, faça um `grep -E "https?://" html/<arquivo>.html` para checar.

# Flags fixas

- `--headless`, `--disable-gpu`, `--no-pdf-header-footer`.
- `--user-data-dir="$(mktemp -d)"` — evita conflito de profile entre execuções concorrentes ou com instâncias do Chromium já abertas.

# Política de overwrite

Antes de gerar, **cheque se o PDF de saída já existe**. Se existir, avise o usuário e peça confirmação antes de sobrescrever — gerações de PDF costumam ser intencionais e sobrescrever silenciosamente pode apagar uma versão revisada.

```bash
[ -f "pdf/<nome>.pdf" ] && echo "AVISO: pdf/<nome>.pdf já existe e será sobrescrito"
```

# Comando padrão (arquivo único)

```bash
mkdir -p html pdf assets
CHROMIUM=$(command -v chromium || command -v chromium-browser || command -v google-chrome-stable || command -v google-chrome)
HTML="html/<nome>.html"
OUT="pdf/<nome>.pdf"

# Adicione --virtual-time-budget=10000 se o HTML referencia recursos externos
EXTRA=""
grep -qE "https?://" "$HTML" && EXTRA="--virtual-time-budget=10000"

"$CHROMIUM" --headless --disable-gpu --no-pdf-header-footer \
  --user-data-dir="$(mktemp -d)" \
  $EXTRA \
  --print-to-pdf="$OUT" "$HTML"

# Validação: arquivo existe e tem conteúdo
[ -s "$OUT" ] || { echo "FALHA: $OUT não foi gerado ou está vazio"; exit 1; }
```

# Comando padrão (lote)

Confirme com o usuário antes de rodar em lote. Execução serial (não paralela) — evita race conditions e mantém logs legíveis.

```bash
mkdir -p html pdf assets
CHROMIUM=$(command -v chromium || command -v chromium-browser || command -v google-chrome-stable || command -v google-chrome)

for f in html/*.html; do
  name=$(basename "$f" .html)
  out="pdf/${name}.pdf"

  EXTRA=""
  grep -qE "https?://" "$f" && EXTRA="--virtual-time-budget=10000"

  "$CHROMIUM" --headless --disable-gpu --no-pdf-header-footer \
    --user-data-dir="$(mktemp -d)" \
    $EXTRA \
    --print-to-pdf="$out" "$f"

  [ -s "$out" ] || echo "FALHA: $out não foi gerado"
done
```

# Validação pós-geração

Após gerar, liste os tamanhos com `ls -la pdf/*.pdf` (ou `du -b pdf/*.pdf`). Em vez de comparar com um valor absoluto:

- Para **arquivo único**: confirme apenas que o arquivo existe e não está vazio (`[ -s "$OUT" ]`).
- Para **lote**: calcule a mediana dos tamanhos e sinalize qualquer PDF que tenha menos de **50% da mediana** — provável falha silenciosa de carregamento de fonte/asset.

```bash
# Detecta outliers em lote
sizes=$(stat -c%s pdf/*.pdf | sort -n)
median=$(echo "$sizes" | awk '{a[NR]=$1} END{print a[int(NR/2)+1]}')
threshold=$((median / 2))
for p in pdf/*.pdf; do
  s=$(stat -c%s "$p")
  [ "$s" -lt "$threshold" ] && echo "AVISO: $p ($s bytes) abaixo de 50% da mediana ($median)"
done
```

# O que evitar

- Hardcodar `/usr/bin/chromium` — sempre detectar via `command -v`.
- Aplicar `--virtual-time-budget=10000` em HTMLs sem recursos externos.
- Gerar PDF fora de `pdf/`, ler HTML fora de `html/` ou deixar assets fora de `assets/`.
- Rodar o comando de dentro de `html/` (quebra caminhos relativos como `../assets/...`).
- Sobrescrever PDF existente sem avisar.
- Confiar apenas no exit code do Chromium — sempre validar com `[ -s "$OUT" ]`.
- Sugerir ferramentas alternativas (wkhtmltopdf, weasyprint, puppeteer) sem o usuário pedir.
