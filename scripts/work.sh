#!/bin/bash
# Conecta na VPN (FortiClient) e abre uma sessão RDP no Remmina.
# Configure as variáveis abaixo no seu ambiente (ex: ~/.bashrc) ou num .env local:
#   VPN_PROFILE   — nome do perfil FortiClient
#   VPN_USER      — usuário da VPN
#   RDP_PROFILE   — caminho do .remmina (ex: ~/.local/share/remmina/work.remmina)

set -u

FORTINET="/opt/forticlient/forticlient-cli"

: "${VPN_PROFILE:?defina VPN_PROFILE}"
: "${VPN_USER:?defina VPN_USER}"
: "${RDP_PROFILE:?defina RDP_PROFILE}"

echo "Conectando na VPN..."
"$FORTINET" vpn connect "$VPN_PROFILE" -u "$VPN_USER"

echo "Aguardando VPN..."
sleep 3

STATUS=$("$FORTINET" vpn status)
if echo "$STATUS" | grep -qi "connected"; then
    echo "VPN conectada! Abrindo Remmina..."
    remmina -c "$RDP_PROFILE" &
else
    echo "Falha na VPN: $STATUS"
fi
