#!/usr/bin/env bash
# Restringe as portas web (80/443) da origem nginx as faixas de IP da Cloudflare,
# pra ninguem furar o proxy batendo direto no IP da VPS (WAF/DDoS/rate-limit ficam
# na borda). SSH (22) e mosh NAO sao afetados. Idempotente: re-rodar atualiza as faixas.
# Requer sudo.
set -euo pipefail

PORTS="80,443"
TAG="cf-origin"

echo "==> baixando faixas oficiais da Cloudflare"
ranges=$(
  { curl -fsSL https://www.cloudflare.com/ips-v4; echo;
    curl -fsSL https://www.cloudflare.com/ips-v6; } \
  | grep -E '^[0-9a-fA-F:.]+/[0-9]+$'
)
[ -n "$ranges" ] || { echo "ERRO: lista de IPs vazia" >&2; exit 1; }

echo "==> removendo regras antigas (tag '$TAG') e o 'Nginx Full' aberto a todos"
while :; do
  num=$(sudo ufw status numbered | awk -v t="$TAG" 'index($0,t){gsub(/[][]/,"",$1);print $1;exit}')
  [ -z "$num" ] && break
  sudo ufw --force delete "$num" >/dev/null
done
sudo ufw delete allow 'Nginx Full' >/dev/null 2>&1 || true

echo "==> liberando $PORTS apenas das faixas da Cloudflare"
while IFS= read -r cidr; do
  [ -z "$cidr" ] && continue
  sudo ufw allow from "$cidr" to any port "$PORTS" proto tcp comment "$TAG" >/dev/null
done <<< "$ranges"

sudo ufw reload >/dev/null
echo "==> pronto. $(printf '%s\n' "$ranges" | grep -c .) faixas liberadas em $PORTS."
