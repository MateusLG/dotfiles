#!/usr/bin/env bash
# Setup de uma VPS Ubuntu 24.04 (Hostinger). Idempotente — pode rodar de novo.
# Espelha os arquivos de config desta pasta pra dentro de /etc.
# Rodar como usuário comum com sudo (NOPASSWD ou senha). NÃO rodar como root.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Sistema: timezone + swap"
sudo timedatectl set-timezone America/Sao_Paulo
if ! swapon --show | grep -q '/swapfile'; then
  sudo fallocate -l 2G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
fi
sudo install -m 644 "$DIR/etc/sysctl.d/99-swappiness.conf" /etc/sysctl.d/99-swappiness.conf
sudo sysctl --system >/dev/null

echo "==> Pacotes"
sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ufw fail2ban unattended-upgrades mosh

echo "==> Hardening SSH (login só por chave)"
# Pré-requisito: a chave pública do seu PC já em ~/.ssh/authorized_keys. NÃO desabilite
# senha antes de testar login por chave numa sessão nova, sob risco de lockout.
sudo install -m 644 "$DIR/etc/ssh/sshd_config.d/00-hardening.conf" /etc/ssh/sshd_config.d/00-hardening.conf
sudo install -m 644 "$DIR/etc/ssh/sshd_config.d/10-keepalive.conf" /etc/ssh/sshd_config.d/10-keepalive.conf
sudo sshd -t && sudo systemctl reload ssh

echo "==> Firewall (ufw): só a 22, com rate-limit"
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit 22/tcp comment 'SSH rate-limited'
sudo ufw allow 60000:60010/udp comment 'mosh'   # acesso mobile — ver mobile-claude.md
sudo ufw --force enable

echo "==> fail2ban (jail sshd)"
sudo install -m 644 "$DIR/etc/fail2ban/jail.local" /etc/fail2ban/jail.local
sudo systemctl enable --now fail2ban
sudo systemctl restart fail2ban

echo "==> Dev: mise + runtimes"
if ! command -v mise >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/mise" ]; then
  curl -fsSL https://mise.run | sh
fi
mkdir -p "$HOME/.config/mise"
install -m 644 "$DIR/mise/config.toml" "$HOME/.config/mise/config.toml"
"$HOME/.local/bin/mise" install

cat <<'EOF'

==> Passos manuais restantes:
  - git:  git config --global user.name "mateus.lira"
          git config --global user.email "mateuslira3105@gmail.com"
  - gh:   gh auth login  (token em https://github.com/settings/tokens com scopes
          repo,read:org,gist,workflow,admin:public_key — device-flow costuma falhar
          em headless; usar --with-token)
  - chave SSH da VPS pro GitHub:
          ssh-keygen -t ed25519 -C "mateus@$(hostname)-vps"
          gh ssh-key add ~/.ssh/id_ed25519.pub --title "vps-$(hostname)"
EOF
echo "==> Pronto."
