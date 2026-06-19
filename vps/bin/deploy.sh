#!/usr/bin/env bash
# Deploy dos apps self-hosted na VPS: git pull + build + restart do serviço systemd.
# Uso: deploy.sh {lgmateus|turmasunb|all}
#
# Cada app roda como user de sistema dedicado em /srv/<app>, com mise proprio.
# O deploy faz git pull + build como esse user (sudo -u) e reinicia o servico.
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

case "${1:-}" in
  lgmateus)  deploy_lgmateus ;;
  turmasunb) deploy_turmasunb ;;
  albumcopa) deploy_albumcopa ;;
  all)       deploy_lgmateus; deploy_turmasunb; deploy_albumcopa ;;
  *) echo "uso: $(basename "$0") {lgmateus|turmasunb|albumcopa|all}" >&2; exit 1 ;;
esac

log "deploy concluído."
