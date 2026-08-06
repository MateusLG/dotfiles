#!/usr/bin/env bash
# Deploy dos apps self-hosted na VPS: git pull + build (+ restart do systemd quando houver serviço).
# Uso: deploy.sh {lgmateus|turmasunb|albumcopa|os48|ericsongomes|all}
#
# Apps com processo persistente rodam como user de sistema dedicado em /srv/<app>, com mise
# proprio; o deploy faz git pull + build como esse user (sudo -u) e reinicia o servico.
# ericsongomes.com.br e static export (sem processo, sem user dedicado): git pull + build
# como o proprio mateus em /srv/ericsongomes/site-src, depois rsync --delete pro
# subdiretorio certo de /var/www/ericsongomes/ (nunca no pai — site e calculadora sao
# irmaos ali). Site e calculadora vivem no mesmo repo desde o subtree merge da calculadora
# em calculadora/, entao um comando so cobre os dois.
# os48 (OS 0048 CREA, servico `gestao`) e o unico que faz pull/build como mateus: o repo e privado e a org
# KodiumAI bloqueia deploy key, entao quem autentica no GitHub e o gh do mateus (ver funcao).
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

case "${1:-}" in
  lgmateus)               deploy_lgmateus ;;
  turmasunb)              deploy_turmasunb ;;
  albumcopa)              deploy_albumcopa ;;
  os48)                   deploy_os48 ;;
  ericsongomes)           deploy_ericsongomes ;;
  all)       deploy_lgmateus; deploy_turmasunb; deploy_albumcopa; deploy_os48; deploy_ericsongomes ;;
  *) echo "uso: $(basename "$0") {lgmateus|turmasunb|albumcopa|os48|ericsongomes|all}" >&2; exit 1 ;;
esac

log "deploy concluído."
