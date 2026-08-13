#!/usr/bin/env bash
# Backup de migracao da VPS (troca de regiao + upgrade -> disco zerado).
# Coleta apenas o insubstituivel: bancos, secrets, configs de sistema, mundo do
# Minecraft, dados de app. Codigo dos apps nao entra (esta todo no GitHub).
#
# Cada secao vira um tarball proprio para preservar owner/modo dos arquivos de
# root sem exigir sudo no rsync que puxa isso pra maquina do usuario.
set -euo pipefail

STAMP=$(date +%F)
DEST=/home/mateus/vps-backup-$STAMP
WORK=$DEST/.staging
LOG=$DEST/backup.log

APPS=(albumcopa turmasunb lgmateus gestao discovery-api discovery-web)
DOCKER_CT=(hbbs hbbr)

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

mkdir -p "$DEST" "$WORK"
: > "$LOG"

# ---------------------------------------------------------------- servicos ---
services_started=0

start_services() {
  [ "$services_started" = 1 ] && return 0
  services_started=1
  log "religando servicos"
  sudo systemctl start minecraft.service 2>&1 | tee -a "$LOG" || true
  for s in "${APPS[@]}"; do
    sudo systemctl start "$s.service" 2>&1 | tee -a "$LOG" || true
  done
  for c in "${DOCKER_CT[@]}"; do
    sudo docker start "$c" >/dev/null 2>&1 || true
  done
}
trap 'rc=$?; start_services; exit $rc' EXIT

log "=== parando servicos ==="
# minecraft: save + stop limpo via RCON antes do systemctl, senao region files
# podem ficar meio escritos
if systemctl is-active --quiet minecraft.service; then
  sudo mcc save-all 2>&1 | tee -a "$LOG" || true
  sleep 3
  sudo mcc stop 2>&1 | tee -a "$LOG" || true
  sleep 8
fi
sudo systemctl stop minecraft.service 2>&1 | tee -a "$LOG" || true
for s in "${APPS[@]}"; do
  sudo systemctl stop "$s.service" 2>&1 | tee -a "$LOG" || true
done
for c in "${DOCKER_CT[@]}"; do
  sudo docker stop "$c" >/dev/null 2>&1 || true
done
log "servicos parados"

# ---------------------------------------------------------------- postgres ---
log "=== dump postgres ==="
mkdir -p "$WORK/postgres"
sudo -u postgres pg_dumpall --globals-only > "$WORK/postgres/globals.sql"
sudo -u postgres psql -Atc \
  "select datname||'|'||pg_get_userbyid(datdba)||'|'||pg_size_pretty(pg_database_size(datname))
   from pg_database where datistemplate=false order by datname" \
  > "$WORK/postgres/databases.txt"

DBS=$(sudo -u postgres psql -Atc \
  "select datname from pg_database where datistemplate=false and datname<>'postgres' order by datname")
for db in $DBS; do
  log "  pg_dump $db"
  sudo -u postgres pg_dump -Fc "$db" -f "/tmp/$db.dump"
  sudo mv "/tmp/$db.dump" "$WORK/postgres/$db.dump"
done
sudo chown -R mateus:mateus "$WORK/postgres"

# --------------------------------------------------------------- inventario ---
log "=== inventario do sistema ==="
INV=$WORK/inventory
mkdir -p "$INV"
{ echo "# hostname"; hostname; echo; echo "# os"; cat /etc/os-release; echo;
  echo "# kernel"; uname -a; echo; echo "# uptime"; uptime; } > "$INV/system.txt"
dpkg --get-selections > "$INV/packages-apt.txt"
apt-mark showmanual > "$INV/packages-apt-manual.txt" 2>/dev/null || true
sudo cp -a /etc/apt/sources.list.d "$INV/apt-sources.d" 2>/dev/null || true
systemctl list-unit-files --state=enabled --no-pager --no-legend > "$INV/services-enabled.txt"
sudo ufw status verbose > "$INV/ufw.txt" 2>&1 || true
sudo fail2ban-client status sshd > "$INV/fail2ban.txt" 2>&1 || true
df -h > "$INV/disk.txt"
getent passwd | awk -F: '$3>=1000 || $1 ~ /^(albumcopa|turmasunb|lgmateus|discovery|gestao|minecraft|simmer)$/' > "$INV/users.txt"
getent group | grep -E "albumcopa|turmasunb|lgmateus|discovery|gestao|minecraft|mateus|docker|sudo" > "$INV/groups.txt"
~/.local/bin/mise ls > "$INV/mise.txt" 2>&1 || true
{ sudo docker ps -a --format '{{.Names}}\t{{.Image}}\t{{.Ports}}'; echo;
  sudo docker images --format '{{.Repository}}:{{.Tag}}'; echo;
  sudo docker volume ls; } > "$INV/docker.txt" 2>&1 || true
for u in root mateus albumcopa turmasunb lgmateus discovery gestao minecraft; do
  echo "## $u"; sudo crontab -u "$u" -l 2>/dev/null || echo "(vazio)"
done > "$INV/crontabs.txt"
{ echo "# porta -> processo"; sudo ss -tlnp; } > "$INV/listening-ports.txt" 2>&1 || true

# repos: onde cada codigo vive, para reclonar no destino
{
  for d in /home/mateus/dotfiles /home/mateus/album-copa /home/mateus/OS0048-Modulo-Gestao-CREA \
           /home/mateus/site-ericson /home/mateus/v2discovery /home/mateus/kodeone-recovery; do
    [ -d "$d/.git" ] || continue
    printf '%s\n  remote: %s\n  branch: %s\n  head:   %s\n' "$d" \
      "$(git -C "$d" remote get-url origin 2>/dev/null)" \
      "$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null)" \
      "$(git -C "$d" rev-parse HEAD 2>/dev/null)"
  done
  for p in albumcopa:/srv/albumcopa lgmateus:/srv/lgmateus turmasunb:/srv/turmasunb \
           gestao:/srv/gestao/repo discovery:/srv/discovery/app mateus:/srv/ericsongomes/site-src; do
    u=${p%%:*}; d=${p##*:}
    [ -d "$d/.git" ] || continue
    printf '%s\n  remote: %s\n  branch: %s\n  head:   %s\n' "$d" \
      "$(sudo -u "$u" git -C "$d" remote get-url origin 2>/dev/null)" \
      "$(sudo -u "$u" git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null)" \
      "$(sudo -u "$u" git -C "$d" rev-parse HEAD 2>/dev/null)"
  done
} > "$INV/repos.txt"

# --------------------------------------------------------------------- /etc ---
log "=== configs do /etc ==="
sudo tar czf "$DEST/etc.tar.gz" \
  --exclude='*.sock' \
  -C / \
  etc/nginx/sites-available etc/nginx/sites-enabled etc/nginx/nginx.conf etc/nginx/conf.d \
  etc/ssl/cloudflare \
  etc/ssh/sshd_config etc/ssh/sshd_config.d \
  etc/fail2ban \
  etc/ufw etc/default/ufw \
  etc/sudoers.d \
  etc/hosts etc/hostname \
  etc/postgresql \
  usr/local/bin/pg-backup.sh usr/local/bin/mcc \
  2>&1 | grep -v 'Removing leading' | tee -a "$LOG" || true

# Units custom E os drop-ins de <app>.service.d/ (o sandbox systemd dos apps).
# maxdepth 2 alcanca os drop-ins; -type f continua excluindo os symlinks de
# *.wants/ que apontam pro /usr/lib. Com maxdepth 1 os drop-ins ficavam de fora
# em silencio — foi assim que o hardening dos 6 apps se perdeu na migracao de
# 2026-08-13 e teve de ser reconstruido a mao no destino.
sudo tar czf "$DEST/systemd-units.tar.gz" -C / \
  $(cd / && find etc/systemd/system -maxdepth 2 -type f \( -name '*.service' -o -name '*.timer' -o -name '*.conf' \) -printf '%p ') \
  2>&1 | grep -v 'Removing leading' | tee -a "$LOG" || true

# ------------------------------------------------------------------ secrets ---
log "=== secrets (envs, chaves ssh/gpg) ==="
SEC=$WORK/secrets
mkdir -p "$SEC"
# .env dos apps, com o caminho original preservado na estrutura
while IFS= read -r f; do
  rel=${f#/}
  sudo mkdir -p "$SEC/$(dirname "$rel")"
  sudo cp -a "$f" "$SEC/$rel"
done < <(sudo find /srv /home/mateus -maxdepth 5 -name '.env' \
           -not -path '*/node_modules/*' -not -path '*/.venv/*' 2>/dev/null)
sudo cp -a /etc/discovery.env "$SEC/etc-discovery.env"

# chaves: a do mateus (github + authorized_keys do PC) e as deploy keys por app
sudo mkdir -p "$SEC/ssh"
sudo cp -a /home/mateus/.ssh "$SEC/ssh/mateus"
for u in albumcopa turmasunb lgmateus discovery gestao; do
  [ -d "/srv/$u/.ssh" ] && sudo cp -a "/srv/$u/.ssh" "$SEC/ssh/$u"
done
[ -d /srv/gestao/.ssh ] || true
sudo cp -a /home/mateus/.gnupg "$SEC/gnupg-mateus" 2>/dev/null || true
sudo tar czf "$DEST/secrets.tar.gz" -C "$WORK" secrets
sudo rm -rf "$SEC"

# ---------------------------------------------------------------- minecraft ---
log "=== minecraft (mundo + mods + config) ==="
sudo tar -I 'zstd -3 -T0' -cf "$DEST/minecraft.tar.zst" \
  --exclude='libraries' --exclude='.cache' --exclude='.fabric' \
  --exclude='crash-reports' --exclude='logs' --exclude='old-26.1.2' \
  -C /srv minecraft \
  2>&1 | grep -v 'Removing leading' | tee -a "$LOG" || true

# ----------------------------------------------------------------- srv data ---
log "=== dados de app em /srv ==="
sudo tar czf "$DEST/srv-data.tar.gz" \
  --exclude='node_modules' --exclude='.venv' --exclude='.next' \
  --exclude='__pycache__' --exclude='.mypy_cache' --exclude='.ruff_cache' \
  --exclude='.cache' --exclude='.npm' \
  -C /srv gestao/_pre-repo-20260804 plataforma/projects \
  2>&1 | grep -v 'Removing leading' | tee -a "$LOG" || true

# ----------------------------------------------------------------- rustdesk ---
log "=== rustdesk (chave do servidor + db) ==="
sudo tar czf "$DEST/rustdesk.tar.gz" -C /home/mateus rustdesk backup-rustdesk \
  2>&1 | grep -v 'Removing leading' | tee -a "$LOG" || true

# --------------------------------------------------------------- pg history ---
log "=== historico de dumps ==="
sudo tar czf "$DEST/pg-history.tar.gz" -C /var/backups postgres \
  2>&1 | grep -v 'Removing leading' | tee -a "$LOG" || true

# --------------------------------------------------------------------- home ---
log "=== home (docs, backups, shell, config) ==="
HOMEW=$WORK/home
mkdir -p "$HOMEW"
cp -a /home/mateus/docs "$HOMEW/"
cp -a /home/mateus/backups "$HOMEW/"
mkdir -p "$HOMEW/shell"
for f in .zshrc .p10k.zsh .tmux.conf .gitconfig .zsh_history .profile .bashrc .bash_logout; do
  [ -f "/home/mateus/$f" ] && cp -a "/home/mateus/$f" "$HOMEW/shell/"
done
cp -a /home/mateus/.config "$HOMEW/config"
# dotfiles: repo esta no GitHub, so o que nao foi commitado importa
mkdir -p "$HOMEW/dotfiles-uncommitted"
git -C /home/mateus/dotfiles status --porcelain > "$HOMEW/dotfiles-uncommitted/status.txt"
git -C /home/mateus/dotfiles diff > "$HOMEW/dotfiles-uncommitted/uncommitted.diff"
while IFS= read -r line; do
  f=${line:3}
  [ -f "/home/mateus/dotfiles/$f" ] || continue
  mkdir -p "$HOMEW/dotfiles-uncommitted/files/$(dirname "$f")"
  cp -a "/home/mateus/dotfiles/$f" "$HOMEW/dotfiles-uncommitted/files/$f"
done < "$HOMEW/dotfiles-uncommitted/status.txt"
tar czf "$DEST/home.tar.gz" -C "$WORK" home
rm -rf "$HOMEW"

# ------------------------------------------------------------------- claude ---
log "=== claude (config, memoria, transcripts) ==="
tar -I 'zstd -3 -T0' -cf "$DEST/claude.tar.zst" \
  --exclude='shell-snapshots' --exclude='paste-cache' --exclude='cache' \
  --exclude='telemetry' --exclude='session-env' \
  -C /home/mateus .claude .claude.json \
  2>&1 | grep -v 'Removing leading' | tee -a "$LOG" || true

# ------------------------------------------------------------------ fechamento ---
start_services
trap - EXIT

log "=== copiando inventario e dumps para o destino ==="
sudo cp -a "$WORK/inventory" "$DEST/"
sudo cp -a "$WORK/postgres" "$DEST/"
sudo rm -rf "$WORK"
sudo chown -R mateus:mateus "$DEST"

log "=== checksums ==="
(cd "$DEST" && find . -type f ! -name SHA256SUMS ! -name backup.log -print0 \
  | sort -z | xargs -0 sha256sum > SHA256SUMS)

log "=== pronto ==="
du -sh "$DEST" | tee -a "$LOG"
