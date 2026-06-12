# vps

Configuração de uma **VPS Ubuntu 24.04 LTS (Hostinger)**, headless, acessada via SSH.
Usuário comum `mateus` no grupo `sudo`. Os arquivos espelham os caminhos reais de `/etc`.

## Conteúdo

- [`setup.sh`](setup.sh) — script idempotente que reproduz todo o setup abaixo.
- [`apps.md`](apps.md) — sites self-hosted (lgmateus.com, turmasunb) atrás da Cloudflare.
- [`bin/deploy.sh`](bin/deploy.sh) — deploy dos apps (git pull + build + restart + health).
- [`bin/ufw-cloudflare.sh`](bin/ufw-cloudflare.sh) — restringe `80/443` às faixas de IP da Cloudflare.
- [`bin/nginx-cloudflare-realip.sh`](bin/nginx-cloudflare-realip.sh) — gera o snippet de `real_ip` (IP real do visitante).
- [`bin/pg-backup.sh`](bin/pg-backup.sh) — dump diário dos bancos Postgres (`pg-backup.timer`).
- [`mobile-claude.md`](mobile-claude.md) — acesso ao Claude Code pelo celular (mosh + tmux + Termius).
- `etc/systemd/system/{lgmateus,turmasunb}.service` → unidades systemd dos apps.
- `etc/nginx/sites-available/{lgmateus.com,turmasunb.com}` → server blocks do nginx.
- `etc/ssh/sshd_config.d/00-hardening.conf` → `/etc/ssh/sshd_config.d/00-hardening.conf`
- `etc/ssh/sshd_config.d/10-keepalive.conf` → `/etc/ssh/sshd_config.d/10-keepalive.conf`
- `etc/fail2ban/jail.local` → `/etc/fail2ban/jail.local`
- `etc/sysctl.d/99-swappiness.conf` → `/etc/sysctl.d/99-swappiness.conf`
- `mise/config.toml` → `~/.config/mise/config.toml`

## O que cada parte faz

### Segurança (SSH)

`00-hardening.conf` desabilita login por senha e deixa root só por chave. É nomeado
`00-` de propósito: o sshd usa **a primeira ocorrência** de cada opção, e o
`50-cloud-init.conf` (que vem na imagem) força `PasswordAuthentication yes` — só
ganhamos dele lendo antes.

> **Ordem importa, risco de lockout:** suba sua chave pública pro
> `~/.ssh/authorized_keys`, teste o login por chave numa sessão nova, e **só então**
> aplique o hardening. O console web da Hostinger é o fallback se travar.

### Firewall (ufw)

`default deny incoming`, `allow outgoing`, a `22/tcp` liberada com `LIMIT`
(rate-limit: bloqueia IP com 6+ conexões em 30s) e `60000:60010/udp` aberta pro mosh.
As regras base são aplicadas pelo `setup.sh`.

As portas web (`80/443`) **não** ficam abertas pra todos: o
[`bin/ufw-cloudflare.sh`](bin/ufw-cloudflare.sh) libera-as apenas das faixas de IP
oficiais da Cloudflare, pra ninguém furar o proxy batendo direto no IP da VPS (WAF,
rate-limit e anti-DDoS ficam na borda; o IP de origem fica escondido). É idempotente —
re-rodar atualiza as faixas quando a Cloudflare muda a lista.

### Origem protegida (Authenticated Origin Pulls + IP real)

Segunda camada além do lock de IP: **AOP** (mTLS Cloudflare→origem). O nginx exige o
**cert de cliente da Cloudflare** (`ssl_verify_client on` nos vhosts, validando contra a
CA global `authenticated_origin_pull_ca.pem`); requests que não vêm da CF levam `400`.
Liga-se em **SSL/TLS → Origin Server → Authenticated Origin Pulls** (opção **Global**) em
cada zona. A CA pública é baixada de
`https://developers.cloudflare.com/ssl/static/authenticated_origin_pull_ca.pem` pra
`/etc/ssl/cloudflare/`.

> **Rollout sem downtime:** subir `ssl_verify_client optional` primeiro, confirmar que a
> CF manda o cert (header de debug `$ssl_client_verify == SUCCESS`), só então `on`.

Atrás da CF o nginx veria só IPs da Cloudflare. O
[`bin/nginx-cloudflare-realip.sh`](bin/nginx-cloudflare-realip.sh) gera
`/etc/nginx/conf.d/cloudflare-realip.conf` (`set_real_ip_from` das faixas da CF +
`real_ip_header CF-Connecting-IP`), restaurando o **IP real do visitante** no log e no
`X-Real-IP` repassado aos apps.

### Backup do Postgres

[`bin/pg-backup.sh`](bin/pg-backup.sh) faz `pg_dump -Fc` de `turmasunb` e `albumcopa`
pra `/var/backups/postgres/`, com retenção de **14 dias**. Roda como o user `postgres`
(peer auth) via `pg-backup.service`, agendado **diário** pelo `pg-backup.timer`
(`Persistent=true` — recupera execução perdida se a VPS estava off). É o complemento
granular ao snapshot **semanal** da Hostinger (disaster recovery): protege contra erro de
migração / delete / corrupção sem rolar a VPS inteira uma semana. Restaurar:
`pg_restore -d <db> /var/backups/postgres/<db>-<data>.dump`.

### Acesso mobile (mosh + tmux)

Claude Code no celular de qualquer lugar via Termius. mosh (UDP) segura a troca de
rede/sleep/IP; tmux mantém a sessão viva; keepalive (`10-keepalive.conf`) limpa
conexões mortas do lado do servidor. Passo a passo do cliente em
[`mobile-claude.md`](mobile-claude.md).

### Brute force (fail2ban)

Jail `sshd`: 5 tentativas em 10 min → ban de 1h, ação `nftables` (padrão Debian,
tabela própria `f2b-table`, não conflita com o ufw).

> **Pegadinha do Ubuntu:** o filtro padrão casa `_SYSTEMD_UNIT=sshd.service`, mas no
> Ubuntu o serviço é `ssh.service`. Sem o `journalmatch` corrigido o fail2ban fica
> ativo porém **inútil** — nunca casa um ataque real. Testado banindo `127.0.0.1`
> com `ignoreself=false` temporário.

### Sistema

- Timezone `America/Sao_Paulo`.
- Swapfile de 2G (`/swapfile`, persistido no `/etc/fstab`).
- `vm.swappiness=10` — com RAM sobrando, evita ir pra swap cedo demais.

### Updates (unattended + cloud-init travado)

`unattended-upgrades` ativo (só security). O **`cloud-init` está `held`**
(`apt-mark hold`, vindo da imagem da Hostinger) e **decidimos manter assim** (2026-06-12):
um upgrade dele não re-roda o provisionamento — que fica registrado em `/var/lib/cloud` —
mas como alguém o travou de propósito, evitamos o risco de um major bump (24.1 → 26.x)
mexer em rede/SSH no boot. **Trade-off aceito:** o `cloud-init` não recebe updates de
segurança e fica congelado. Para reverter a decisão:

```sh
sudo apt-mark unhold cloud-init
sudo apt-get install --only-upgrade cloud-init
```

### Dev (mise)

`mise` instalado em `~/.local/bin`, ativado no `~/.zshrc`. Runtimes globais em
`mise/config.toml`: `node@lts`, `rust@stable`, `uv@latest`. Não instalar runtime por
`apt`/`nvm`/`rustup` direto — passar sempre pelo mise.

## Uso

```sh
./setup.sh        # aplica tudo (pede sudo)
```

Passos interativos (git config, `gh auth login`, gerar/registrar chave SSH da VPS no
GitHub) ficam documentados no final do `setup.sh` — não dá pra automatizar sem token.
