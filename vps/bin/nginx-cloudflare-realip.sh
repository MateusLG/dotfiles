#!/usr/bin/env bash
# Gera /etc/nginx/conf.d/cloudflare-realip.conf com as faixas da Cloudflare, pro nginx
# logar o IP REAL do visitante (header CF-Connecting-IP) em vez do IP da Cloudflare.
# Sem isso, log e fail2ban so veem IPs da CF. Idempotente. Requer sudo.
set -euo pipefail

OUT=/etc/nginx/conf.d/cloudflare-realip.conf

echo "==> baixando faixas oficiais da Cloudflare"
ranges=$(
  { curl -fsSL https://www.cloudflare.com/ips-v4; echo;
    curl -fsSL https://www.cloudflare.com/ips-v6; } \
  | grep -E '^[0-9a-fA-F:.]+/[0-9]+$'
)
[ -n "$ranges" ] || { echo "ERRO: lista de IPs vazia" >&2; exit 1; }

{
  echo "# Restaura o IP real do visitante atras da Cloudflare (CF-Connecting-IP)."
  echo "# Gerado por bin/nginx-cloudflare-realip.sh — nao editar a mao."
  while IFS= read -r cidr; do
    [ -n "$cidr" ] && echo "set_real_ip_from $cidr;"
  done <<< "$ranges"
  echo "real_ip_header CF-Connecting-IP;"
} | sudo tee "$OUT" >/dev/null

sudo nginx -t && sudo systemctl reload nginx
echo "==> $OUT atualizado ($(printf '%s\n' "$ranges" | grep -c .) faixas), nginx recarregado."
