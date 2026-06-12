#!/usr/bin/env bash
# Deploy dos apps self-hosted na VPS: git pull + build + restart do serviço systemd.
# Uso: deploy.sh {lgmateus|turmasunb|all}
#
# Requer o shell com mise ativo (uv/npm/node no PATH) e sudo NOPASSWD pro systemctl.
set -euo pipefail

APPS="$HOME/apps"

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
  log "lgmateus.com (Next.js)"
  cd "$APPS/lgmateus.com"
  git pull --ff-only
  npm ci
  npm run build
  sudo systemctl restart lgmateus
  sleep 2
  health lgmateus http://127.0.0.1:3000/
}

deploy_turmasunb() {
  log "turmasunb (FastAPI)"
  cd "$APPS/turmasunb"
  git pull --ff-only
  uv pip install -r requirements.txt
  sudo systemctl restart turmasunb
  sleep 2
  health turmasunb http://127.0.0.1:8000/
}

case "${1:-}" in
  lgmateus)  deploy_lgmateus ;;
  turmasunb) deploy_turmasunb ;;
  all)       deploy_lgmateus; deploy_turmasunb ;;
  *) echo "uso: $(basename "$0") {lgmateus|turmasunb|all}" >&2; exit 1 ;;
esac

log "deploy concluído."
