#!/usr/bin/env bash
# Deploy dos apps self-hosted na VPS: git pull + build (+ restart do systemd quando houver serviço).
# Uso: deploy.sh {lgmateus|turmasunb|albumcopa|os48|discovery|ericsongomes|plataforma|all}
#
# Apps com processo persistente rodam como user de sistema dedicado em /srv/<app>, com mise
# proprio; o deploy faz git pull + build como esse user (sudo -u) e reinicia o servico.
# ericsongomes.com.br e static export (sem processo, sem user dedicado): git pull + build
# como o proprio mateus em /srv/ericsongomes/site-src, depois rsync --delete pro
# subdiretorio certo de /var/www/ericsongomes/ (nunca no pai — site e calculadora sao
# irmaos ali). Site e calculadora vivem no mesmo repo desde o subtree merge da calculadora
# em calculadora/, entao um comando so cobre os dois.
# plataforma (studio.kodium.ai) e docker compose no home do mateus, nao /srv: pull + rebuild
# da imagem + up -d do servico `web` (o caddy do compose fica fora, quem termina TLS e o nginx).
#
# AUTENTICACAO NO GITHUB (todo repo aqui e privado)
# O user de sistema do app nao tem credencial nenhuma, entao ate 2026-08-05 o `git pull` de
# lgmateus/turmasunb/albumcopa/discovery morria pedindo usuario e senha — que o GitHub nao
# aceita mais em HTTPS desde 2021. Como cada um resolve hoje:
#   - lgmateus, turmasunb, albumcopa, discovery: deploy key read-only propria por app em
#     /srv/<app>/.ssh/id_ed25519, registrada no repo como `vps-srv1752180-<app>`. Remote e SSH.
#     O pull segue rodando como o user do app — ninguem precisa da credencial do mateus.
#   - os48: segue no gh do mateus (pull/build como ele, servico `gestao` so le o diretorio).
#     Era a unica saida quando a org KodiumAI bloqueava deploy key; hoje ela permite
#     (`deploy_keys_enabled_for_repositories`), entao da pra migrar pro padrao acima se quiser.
# Chave nova, se um dia precisar recriar:
#   sudo -u <app> ssh-keygen -t ed25519 -N '' -f /srv/<app>/.ssh/id_ed25519 -C vps-srv1752180-<app>
#   gh repo deploy-key add /srv/<app>/.ssh/id_ed25519.pub -R <owner/repo> -t vps-srv1752180-<app>
set -euo pipefail

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }

# health <serviço> <url> — confirma que o serviço está active e respondendo
health() {
  local svc="$1" url="$2" code
  if ! systemctl is-active --quiet "$svc"; then
    echo "ERRO: $svc não está active" >&2
    journalctl -u "$svc" -n 20 --no-pager >&2
    exit 1
  fi
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$url" || true)
  echo "health $svc: HTTP $code"
  case "$code" in
    2*|3*) ;;
    *) echo "ERRO: $svc respondeu $code" >&2; exit 1 ;;
  esac
}

# health_static <url> — sem systemd pra checar (site estático): só confirma HTTP 2xx/3xx
health_static() {
  local url="$1" code
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$url" || true)
  echo "health $url: HTTP $code"
  case "$code" in
    2*|3*) ;;
    *) echo "ERRO: $url respondeu $code" >&2; exit 1 ;;
  esac
}

deploy_lgmateus() {
  log "lgmateus.com (Next.js) — user dedicado em /srv"
  sudo -u lgmateus env HOME=/srv/lgmateus bash -c '
    set -e
    cd /srv/lgmateus
    git pull --ff-only
    M="$HOME/.local/bin/mise"
    "$M" exec -- npm ci
    "$M" exec -- npm run build
  '
  sudo systemctl restart lgmateus
  sleep 2
  health lgmateus http://127.0.0.1:3000/
}

deploy_turmasunb() {
  log "turmasunb (FastAPI) — user dedicado em /srv"
  sudo -u turmasunb env HOME=/srv/turmasunb bash -c '
    set -e
    cd /srv/turmasunb
    git pull --ff-only
    "$HOME/.local/bin/mise" exec -- uv pip install -r requirements.txt
  '
  sudo systemctl restart turmasunb
  sleep 2
  health turmasunb http://127.0.0.1:8000/
}

deploy_albumcopa() {
  log "album-copa / FALTINHA (FastAPI + Vite) — user dedicado em /srv"
  sudo -u albumcopa env HOME=/srv/albumcopa bash -c '
    set -e
    cd /srv/albumcopa
    git pull --ff-only
    M="$HOME/.local/bin/mise"
    ( cd backend && "$M" exec -- uv sync )
    ( cd frontend && "$M" exec -- npm ci && "$M" exec -- npm run build )
  '
  sudo systemctl restart albumcopa
  sleep 2
  health albumcopa http://127.0.0.1:8001/api/health
}

deploy_os48() {
  log "OS 0048 CREA / servico gestao (FastAPI + Vite) — demo em crea.lglabs.tech"
  # O clone e o build sao do mateus (o repo e privado e a org bloqueia deploy key, entao
  # a credencial e o gh do proprio mateus); o servico segue rodando como o user gestao,
  # que so le o diretorio — o processo nao consegue alterar o proprio codigo.
  # O .env fica fora do git, dono mateus:gestao 640 (o app precisa ler, o resto nao).
  cd /srv/gestao/repo
  git pull --ff-only
  M="$HOME/.local/bin/mise"
  ( cd gestao/backend && "$M" exec -- uv sync --no-dev )
  ( cd gestao/frontend && "$M" exec -- npm ci && "$M" exec -- npm run build )
  # dump antes das migrations: o banco da demo tem dado que o cliente esta validando,
  # e o pg-backup.timer nao cobre crea_demo (retencao de 14 dias apaga estes tambem).
  sudo -u postgres pg_dump -Fc crea_demo \
    -f "/var/backups/postgres/crea_demo-pre-deploy-$(date +%Y%m%d-%H%M%S).dump"
  ( cd gestao/backend && .venv/bin/alembic upgrade head )
  sudo systemctl restart gestao
  sleep 2
  health gestao http://127.0.0.1:8002/api/health
}

deploy_ericsongomes() {
  log "ericsongomes.com.br (Next.js static export) — sem processo, sem user dedicado"
  cd /srv/ericsongomes/site-src
  git pull --ff-only
  # A calculadora e um projeto Next proprio dentro de calculadora/, que veio pro repo do site
  # por subtree merge. Confere antes de publicar qualquer coisa: sem isso o site ia pro ar e o
  # deploy morria na metade, deixando /calculadora/ na versao velha sem dizer por que.
  [[ -d calculadora ]] || { echo "ERRO: calculadora/ nao existe em site-src — o subtree merge ja foi pro origin/main?" >&2; exit 1; }
  M="$HOME/.local/bin/mise"
  "$M" exec -- npm ci
  "$M" exec -- npm run build
  rsync -a --delete out/ /var/www/ericsongomes/site/
  health_static "https://ericsongomes.com.br/"
  # package.json e build sao separados; o out/ da calculadora vai pro subdiretorio irmao em /var/www.
  ( cd calculadora && "$M" exec -- npm ci && "$M" exec -- npm run build )
  rsync -a --delete calculadora/out/ /var/www/ericsongomes/calculadora/
  health_static "https://ericsongomes.com.br/calculadora/"
}

deploy_discovery() {
  log "V2Discovery / kodeone (Rails 8 API + Next.js) — discovery.lgmateus.com"
  # /srv/discovery/app nao e so deploy: e onde o desenvolvimento acontece (tem .specs/, skills
  # e commits feitos direto ali). Por isso o deploy se recusa a mexer em trabalho nao publicado
  # — aborta e deixa a decisao pro humano, em vez de tentar merge/stash/rebase sozinho.
  sudo -u discovery env HOME=/srv/discovery bash -c '
    set -e
    cd /srv/discovery/app
    if [ -n "$(git status --porcelain)" ]; then
      echo "ERRO: working tree sujo em /srv/discovery/app — commite ou descarte antes." >&2
      git status --short >&2
      exit 1
    fi
    git fetch --quiet origin
    if [ -n "$(git log --oneline origin/main..HEAD)" ]; then
      echo "ERRO: ha commit local que nao esta no origin/main — publique antes de deployar:" >&2
      git log --oneline origin/main..HEAD >&2
      exit 1
    fi
    git pull --ff-only
    # Env do servico (RAILS_ENV, POSTGRES_*, SECRET_KEY_BASE) — 640 root:discovery, o user le
    # pelo grupo. O build do Next tambem precisa dela, nao so as migrations.
    set -a; . /etc/discovery.env; set +a
    export PATH="$HOME/.local/share/mise/shims:$PATH"
    ( cd apps/api && bundle install --quiet )
    ( cd apps/web && pnpm install --frozen-lockfile && pnpm build )
  '
  # Dump antes das migrations, mesmo motivo do os48: o pg-backup.timer nao cobre kodeone_production.
  sudo -u postgres pg_dump -Fc kodeone_production \
    -f "/var/backups/postgres/kodeone_production-pre-deploy-$(date +%Y%m%d-%H%M%S).dump"
  # Migration NAO roda com o user da api: `kodeone_app` tem so DML, e o dono das 25 tabelas (e do
  # banco) e o role `discovery` — DDL como kodeone_app morre em "must be owner of table". Trocar o
  # POSTGRES_USER nao basta, porque nao ha senha do dono guardada em lugar nenhum: zerando tambem o
  # POSTGRES_HOST, o database.yml cai no socket unix e o Postgres autentica por peer (user de
  # sistema discovery -> role discovery). O privilegio minimo da api em runtime fica preservado.
  sudo -u discovery env HOME=/srv/discovery bash -c '
    set -e
    cd /srv/discovery/app/apps/api
    set -a; . /etc/discovery.env; set +a
    export POSTGRES_USER=discovery POSTGRES_PASSWORD="" POSTGRES_HOST=""
    export PATH="$HOME/.local/share/mise/shims:$PATH"
    bin/rails db:migrate
  '
  sudo systemctl restart discovery-api discovery-web
  sleep 3
  health discovery-api http://127.0.0.1:8003/up
  health discovery-web http://127.0.0.1:3001/
}

deploy_plataforma() {
  log "plataforma-ia / Kodium Studio (Next + Agent SDK em docker) — studio.kodium.ai"
  # Unico app fora de /srv: compose no home do mateus, que tambem e quem tem a credencial
  # do repo (org KodiumAI, sem deploy key). Sobe so o `web` — o caddy do compose esta no
  # profile donotstart porque 80/443 sao do nginx do host, e o preview-router vem de outro
  # compose file (docker-compose.preview.yml), que este deploy nao toca.
  cd /home/mateus/plataforma-ia
  git pull --ff-only
  # A stack virou multi-servico em 2026-08-05: entraram `db` (Postgres) e `api` (Rails 8), o
  # `web` ganhou depends_on: [api] e o diretorio do front virou web/ (era plataforma-web/).
  # O que roda no ar hoje ainda e a imagem antiga, ligada ao Supabase self-host de ~/supabase.
  #
  # A api de producao le estes segredos com ENV.fetch sem default — faltando um, ela nao sobe
  # e o `up -d` derruba o studio sem por nada no lugar. Por isso a checagem vem antes do build.
  # RAILS_MASTER_KEY nao da pra gerar aqui: e o que decifra api/config/credentials.yml.enc, e
  # vive so em api/config/master.key (gitignored) na maquina de dev. As demais saem de
  # `openssl rand -hex 32` — mas so na PRIMEIRA vez: as ACTIVE_RECORD_ENCRYPTION_* cifram
  # mcp_servers.config e github_connections.access_token, e trocar depois torna o que ja
  # foi gravado indecifravel.
  local faltando=()
  for v in RAILS_MASTER_KEY DATABASE_USERNAME DATABASE_PASSWORD DATABASE_NAME \
           ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY \
           ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT INTERNAL_SERVICE_TOKEN; do
    grep -qE "^${v}=." .env || faltando+=("$v")
  done
  if (( ${#faltando[@]} )); then
    echo "ERRO: .env nao tem: ${faltando[*]}" >&2
    echo "      A api Rails nao sobe sem isso e o studio atual sairia do ar. Ver .env.example." >&2
    exit 1
  fi
  docker compose build api web
  docker compose up -d db api web   # o docker-entrypoint da api roda db:prepare no boot
  sleep 5
  # Sem systemd: quem supervisiona e o proprio docker (restart: unless-stopped).
  health_static "http://127.0.0.1:8020/"
}

case "${1:-}" in
  lgmateus)               deploy_lgmateus ;;
  turmasunb)              deploy_turmasunb ;;
  albumcopa)              deploy_albumcopa ;;
  os48)                   deploy_os48 ;;
  discovery)              deploy_discovery ;;
  ericsongomes)           deploy_ericsongomes ;;
  plataforma)             deploy_plataforma ;;
  # plataforma fica fora do `all` de proposito enquanto o .env nao migrar pra stack db+api:
  # o comando aborta por design, e nao vale derrubar um `deploy all` inteiro por causa disso.
  # discovery vai por ultimo: ele aborta de proposito quando ha trabalho nao publicado em
  # /srv/discovery/app (que tambem e dir de dev), e com set -e isso mataria o resto da fila.
  all)       deploy_lgmateus; deploy_turmasunb; deploy_albumcopa; deploy_os48; deploy_ericsongomes; deploy_discovery ;;
  *) echo "uso: $(basename "$0") {lgmateus|turmasunb|albumcopa|os48|discovery|ericsongomes|plataforma|all}" >&2; exit 1 ;;
esac

log "deploy concluído."
