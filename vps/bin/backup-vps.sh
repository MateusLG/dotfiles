#!/usr/bin/env bash
# Backup da VPS: coleta o insubstituivel para o cenario "a VPS pegou fogo,
# so tenho este tarball e o GitHub" - bancos, o estado do Komodo (stacks,
# builds, procedures, variables), secrets, volumes docker com dado real,
# configs de sistema, mundo do Minecraft, chave do rustdesk. Codigo dos apps
# nao entra: esta todo no GitHub e o Komodo rebuilda a imagem a partir dele.
#
# Pos-migracao systemd+nginx -> Komodo+Traefik (2026-08): as 5 apps viram
# container, /srv/<app>, /var/www e os users de sistema por app foram
# removidos. So o Minecraft segue em systemd/`/srv`. Ver vps/apps.md e
# vps/README.md para o desenho atual.
#
# Cada secao vira um tarball proprio para preservar owner/modo dos arquivos de
# root sem exigir sudo no rsync que puxa isso pra maquina do usuario.
#
# Seguro rodar com o sistema no ar: nenhum container e parado. A unica pausa
# e o systemd do Minecraft, so durante o tar do mundo (por consistencia dos
# region files), e ele religa mesmo se o resto do script falhar.
set -euo pipefail

STAMP=$(date +%F)
DEST=/home/mateus/vps-backup-$STAMP
WORK=$DEST/.staging
LOG=$DEST/backup.log

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

mkdir -p "$DEST" "$WORK"
: > "$LOG"

# guarda de espaco: aborta antes de mexer em qualquer coisa se o disco ja
# estiver critico. Nada foi parado ainda nesse ponto, entao um exit aqui e
# barato.
MIN_KB=$((5 * 1024 * 1024)) # 5G de folga minima
AVAIL_KB=$(df --output=avail -k / | tail -1)
if [ "$AVAIL_KB" -lt "$MIN_KB" ]; then
  log "erro: menos de 5G livres em / (${AVAIL_KB}KB disponiveis) - abortando antes de comecar"
  exit 1
fi
log "espaco livre em /: $(df -h --output=avail / | tail -1 | tr -d ' ')"

# ---------------------------------------------------------------- minecraft trap ---
# so o minecraft e parado, e so por perto do proprio tar dele (ver secao mais
# abaixo) - a flag evita ficar com o servico fora do ar o resto do backup
# inteiro, mas o trap cobre qualquer falha no meio do caminho.
minecraft_stopped=0
restart_minecraft() {
  [ "$minecraft_stopped" = 1 ] || return 0
  log "religando minecraft"
  sudo systemctl start minecraft.service 2>&1 | tee -a "$LOG" || true
  minecraft_stopped=0
}
trap 'rc=$?; restart_minecraft; exit $rc' EXIT

# ---------------------------------------------------------------- postgres ---
log "=== dump postgres ==="
mkdir -p "$WORK/postgres"
sudo -u postgres pg_dumpall --globals-only > "$WORK/postgres/globals.sql"
sudo -u postgres psql -Atc \
  "select datname||'|'||pg_get_userbyid(datdba)||'|'||pg_size_pretty(pg_database_size(datname))
   from pg_database where datistemplate=false order by datname" \
  > "$WORK/postgres/databases.txt"
log "bancos encontrados:"
sed 's/^/  /' "$WORK/postgres/databases.txt" | tee -a "$LOG"

# clones de trabalho que NAO entram no dump: reproduziveis por procedimento
# documentado, nao contam como "insubstituivel". creadf_migracao_validacao e
# um clone de ~37G usado para validar a migracao do CREA-DF, recriavel via
# kodium/crea/migracao/database/validation/recreate-validation-db.sh a partir
# do dump imutavel dump-creadf-202607132009.sql (fora do escopo desta VPS/
# backup - ver kodium/crea/migracao/docs/dump-creadf-20260713.md). Incluir
# esse banco encheria o disco: ele sozinho e maior que o espaco livre.
EXCLUDE_DBS=(creadf_migracao_validacao)

DBS=$(sudo -u postgres psql -Atc \
  "select datname from pg_database where datistemplate=false and datname<>'postgres' order by datname")
for db in $DBS; do
  skip=0
  for x in "${EXCLUDE_DBS[@]}"; do
    [ "$db" = "$x" ] && skip=1 && break
  done
  if [ "$skip" = 1 ]; then
    log "  pulando $db (clone descartavel, fora do escopo do backup)"
    continue
  fi
  log "  pg_dump $db"
  sudo -u postgres pg_dump -Fc "$db" -f "/tmp/$db.dump"
  sudo mv "/tmp/$db.dump" "$WORK/postgres/$db.dump"
  sz=$(sudo stat -c%s "$WORK/postgres/$db.dump" 2>/dev/null || echo 0)
  [ "$sz" -gt 0 ] || log "  aviso: dump de $db ficou com 0 bytes"
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
# so sobrou o user do minecraft como sistema relevante; os das apps foram
# removidos na migracao para container (ver vps/apps.md)
getent passwd | awk -F: '$3>=1000 || $1 ~ /^(minecraft)$/' > "$INV/users.txt"
getent group | grep -E "minecraft|mateus|docker|sudo" > "$INV/groups.txt"
~/.local/bin/mise ls > "$INV/mise.txt" 2>&1 || true
{ sudo docker ps -a --format '{{.Names}}\t{{.Image}}\t{{.Ports}}'; echo;
  sudo docker images --format '{{.Repository}}:{{.Tag}}'; echo;
  sudo docker volume ls; } > "$INV/docker.txt" 2>&1 || true
for u in root mateus minecraft; do
  echo "## $u"; sudo crontab -u "$u" -l 2>/dev/null || echo "(vazio)"
done > "$INV/crontabs.txt"
{ echo "# porta -> processo"; sudo ss -tlnp; } > "$INV/listening-ports.txt" 2>&1 || true

# repos: onde o codigo vive, para reclonar no destino. As 5 apps nao tem mais
# clone de trabalho na VPS (o Komodo builda direto do GitHub); o que sobra
# clonado aqui e o dotfiles e os repos de trabalho em ~/dev e ~/codex.
{
  for d in /home/mateus/infra/dotfiles \
           /home/mateus/dev/*/*/ \
           /home/mateus/dev/*/*/sistemas/*/*/ \
           /home/mateus/codex/*/; do
    d=${d%/}
    [ -d "$d/.git" ] || continue
    printf '%s\n  remote: %s\n  branch: %s\n  head:   %s\n' "$d" \
      "$(git -C "$d" remote get-url origin 2>/dev/null)" \
      "$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null)" \
      "$(git -C "$d" rev-parse HEAD 2>/dev/null)"
  done
} > "$INV/repos.txt"

# --------------------------------------------------------------------- /etc ---
log "=== configs do /etc ==="
sudo tar czf "$DEST/etc.tar.gz" \
  --exclude='*.sock' \
  -C / \
  etc/ssl/cloudflare \
  etc/ssh/sshd_config etc/ssh/sshd_config.d \
  etc/fail2ban \
  etc/ufw etc/default/ufw \
  etc/sudoers.d \
  etc/sysctl.d \
  etc/hosts etc/hostname \
  etc/postgresql \
  usr/local/bin/pg-backup.sh usr/local/bin/mcc \
  2>&1 | grep -v 'Removing leading' | tee -a "$LOG" || true

# units que sobraram em systemd: as 5 apps viraram container, so minecraft e
# o pg-backup (dump diario) seguem aqui.
log "=== units systemd (minecraft + pg-backup) ==="
SYSTEMD_UNITS=(minecraft.service pg-backup.service pg-backup.timer)
UNIT_ARGS=()
for u in "${SYSTEMD_UNITS[@]}"; do
  if [ -f "/etc/systemd/system/$u" ]; then
    UNIT_ARGS+=("etc/systemd/system/$u")
  else
    log "  aviso: unit $u nao encontrada, pulando"
  fi
done
if [ "${#UNIT_ARGS[@]}" -gt 0 ]; then
  sudo tar czf "$DEST/systemd-units.tar.gz" -C / "${UNIT_ARGS[@]}" \
    2>&1 | grep -v 'Removing leading' | tee -a "$LOG" || true
else
  log "  nenhuma unit encontrada, systemd-units.tar.gz nao foi gerado"
fi

# ------------------------------------------------------------------ secrets ---
log "=== secrets (envs, chaves ssh/gpg, segredos do komodo) ==="
SEC=$WORK/secrets
mkdir -p "$SEC"
# .env residual em /home ou /srv, com o caminho original preservado na
# estrutura (as apps hoje pegam config das Variables do Komodo, nao de disco,
# entao isso normalmente nao acha nada - fica como rede de seguranca)
while IFS= read -r f; do
  rel=${f#/}
  sudo mkdir -p "$SEC/$(dirname "$rel")"
  sudo cp -a "$f" "$SEC/$rel"
done < <(sudo find /srv /home/mateus -maxdepth 5 -name '.env' \
           -not -path '*/node_modules/*' -not -path '*/.venv/*' 2>/dev/null)

# chave do mateus (github + authorized_keys do PC)
sudo mkdir -p "$SEC/ssh"
sudo cp -a /home/mateus/.ssh "$SEC/ssh/mateus"
sudo cp -a /home/mateus/.gnupg "$SEC/gnupg-mateus" 2>/dev/null || true

# segredos do proprio komodo: senha do mongo, jwt secret, senha do admin
# inicial (compose.env) e credencial da api (api.env). Sem isso o komodo nao
# sobe de novo com o mesmo estado.
sudo mkdir -p "$SEC/etc/komodo/komodo"
for f in compose.env api.env; do
  if [ -f "/etc/komodo/komodo/$f" ]; then
    sudo cp -a "/etc/komodo/komodo/$f" "$SEC/etc/komodo/komodo/$f"
    sudo chmod 600 "$SEC/etc/komodo/komodo/$f"
  else
    log "  aviso: /etc/komodo/komodo/$f nao encontrado"
  fi
done

sudo tar czf "$DEST/secrets.tar.gz" -C "$WORK" secrets
sudo rm -rf "$SEC"

# ------------------------------------------------------------------ komodo ---
# banco do komodo (mongo, em container) - guarda todas as Stacks, Builds,
# Procedures, Servers e as Variables (senhas de banco, tokens, PAT do
# github). Usa o backup nativo do komodo (exporta as collections do mongo em
# /etc/komodo/backups, que ja e volume do host) em vez de inventar um dump.
log "=== komodo: backup nativo do banco (stacks, builds, variables) ==="
if sudo docker ps --format '{{.Names}}' | grep -qx 'komodo-core-1'; then
  sudo docker exec komodo-core-1 km database backup -y 2>&1 | tee -a "$LOG" || \
    log "  aviso: 'km database backup' falhou"
  if [ -d /etc/komodo/backups ]; then
    sudo tar czf "$DEST/komodo-backup.tar.gz" -C /etc/komodo backups \
      2>&1 | grep -v 'Removing leading' | tee -a "$LOG" || true
  else
    log "  aviso: /etc/komodo/backups nao existe apos o backup nativo"
  fi
else
  log "  aviso: container komodo-core-1 nao esta rodando, pulando backup do komodo"
fi

# ----------------------------------------------------------- docker volumes ---
# so os volumes com dado real que nao vem de outro lugar deste backup.
# Volumes de imagem/cache (mongo-config, mongo-data - coberto pelo backup
# logico acima -, socket-config do traefik) ficam de fora de proposito.
log "=== volumes docker com dado real ==="
VOLW=$WORK/docker-volumes
mkdir -p "$VOLW"

backup_volume() {
  local pattern=$1 label=$2 vol mp
  vol=$(sudo docker volume ls --format '{{.Name}}' | grep -E "$pattern" | head -1 || true)
  if [ -z "$vol" ]; then
    log "  aviso: volume '$label' ($pattern) nao encontrado, pulando"
    return 0
  fi
  mp=$(sudo docker volume inspect "$vol" --format '{{.Mountpoint}}')
  log "  $vol ($label)"
  sudo cp -a "$mp" "$VOLW/$vol"
}

# nome tem prefixo do projeto do compose (turmasunb_<volume>)
backup_volume '^turmasunb.*backup' "backups do turmasunb"
# par de chaves ed25519 core<->periphery do komodo
backup_volume '^komodo_keys$' "chaves do komodo"

if [ -n "$(ls -A "$VOLW" 2>/dev/null)" ]; then
  sudo tar czf "$DEST/docker-volumes.tar.gz" -C "$WORK" docker-volumes \
    2>&1 | grep -v 'Removing leading' | tee -a "$LOG" || true
else
  log "  nenhum volume com dado encontrado, docker-volumes.tar.gz nao foi gerado"
fi
sudo rm -rf "$VOLW"

# ---------------------------------------------------------------- minecraft ---
log "=== minecraft: parando para consistencia do mundo ==="
if systemctl is-active --quiet minecraft.service; then
  # save + stop limpo via RCON antes do systemctl, senao region files podem
  # ficar meio escritos
  sudo mcc save-all 2>&1 | tee -a "$LOG" || true
  sleep 3
  sudo mcc stop 2>&1 | tee -a "$LOG" || true
  sleep 8
fi
sudo systemctl stop minecraft.service 2>&1 | tee -a "$LOG" || true
minecraft_stopped=1
log "minecraft parado"

log "=== minecraft (mundo + mods + config) ==="
sudo tar -I 'zstd -3 -T0' -cf "$DEST/minecraft.tar.zst" \
  --exclude='libraries' --exclude='.cache' --exclude='.fabric' \
  --exclude='crash-reports' --exclude='logs' --exclude='old-26.1.2' \
  -C /srv minecraft \
  2>&1 | grep -v 'Removing leading' | tee -a "$LOG" || true

restart_minecraft
log "minecraft religado"

# ----------------------------------------------------------------- rustdesk ---
log "=== rustdesk (chave do servidor + db) ==="
sudo tar czf "$DEST/rustdesk.tar.gz" -C /home/mateus rustdesk \
  2>&1 | grep -v 'Removing leading' | tee -a "$LOG" || true

# --------------------------------------------------------------- pg history ---
log "=== historico de dumps diarios ==="
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
git -C /home/mateus/infra/dotfiles status --porcelain > "$HOMEW/dotfiles-uncommitted/status.txt"
git -C /home/mateus/infra/dotfiles diff > "$HOMEW/dotfiles-uncommitted/uncommitted.diff"
while IFS= read -r line; do
  f=${line:3}
  [ -f "/home/mateus/infra/dotfiles/$f" ] || continue
  mkdir -p "$HOMEW/dotfiles-uncommitted/files/$(dirname "$f")"
  cp -a "/home/mateus/infra/dotfiles/$f" "$HOMEW/dotfiles-uncommitted/files/$f"
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
restart_minecraft
trap - EXIT

log "=== copiando inventario e dumps para o destino ==="
sudo cp -a "$WORK/inventory" "$DEST/"
sudo cp -a "$WORK/postgres" "$DEST/"
sudo rm -rf "$WORK"
sudo chown -R mateus:mateus "$DEST"

log "=== checksums ==="
(cd "$DEST" && find . -type f ! -name SHA256SUMS ! -name backup.log -print0 \
  | sort -z | xargs -0 sha256sum > SHA256SUMS)

log "=== resumo ==="
(
  cd "$DEST"
  printf '%-32s %s\n' "arquivo/dir" "tamanho" | tee -a "$LOG"
  for f in *.tar.gz *.tar.zst; do
    [ -e "$f" ] && printf '%-32s %s\n' "$f" "$(du -h "$f" | cut -f1)" | tee -a "$LOG"
  done
  for d in inventory postgres; do
    [ -d "$d" ] && printf '%-32s %s\n' "$d/" "$(du -sh "$d" | cut -f1)" | tee -a "$LOG"
  done
)
log "fora de proposito (de fora, nao por esquecimento): codigo das apps (github),"
log "  imagens docker (komodo rebuilda a partir do build), volumes de"
log "  imagem/cache do docker (mongo-data/mongo-config, socket-config do"
log "  traefik), banco creadf_migracao_validacao (clone descartavel e"
log "  reproduzivel, ver nota na secao postgres deste log)"

log "=== pronto ==="
du -sh "$DEST" | tee -a "$LOG"
