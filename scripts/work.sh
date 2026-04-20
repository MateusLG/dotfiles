#!/bin/bash

FORTINET="/opt/forticlient/forticlient-cli"

echo "Conectando na VPN..."
$FORTINET vpn connect $VPN_PROFILE -u $VPN_USER

echo "Aguardando VPN..."
sleep 3

STATUS=$($FORTINET vpn status)
if echo "$STATUS" | grep -q "Connected"; then
    echo "VPN conectada! Abrindo Remmina..."
    remmina -c ~/.local/share/remmina/group_rdp_pc-$VPN_PROFILE_xxx-xxx-xxx-xxx.remmina &
else
    echo "Falha na VPN: $STATUS"
fi
