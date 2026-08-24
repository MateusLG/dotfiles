# vps

Configuração de uma **VPS Ubuntu 24.04 LTS (Hostinger)**, headless, acessada via SSH.
Usuário comum `mateus` no grupo `sudo`. Os arquivos espelham os caminhos reais de `/etc`.

## Conteúdo

- [`setup.sh`](setup.sh) — script idempotente que reproduz todo o setup abaixo (SSH,
  ufw, fail2ban, sysctl, mise — **não** cobre Komodo/Traefik/apps, que vivem no fluxo
  descrito abaixo).
- [`apps.md`](apps.md) — as 5 apps self-hosted (Stacks do Komodo) atrás da Cloudflare.
- [`komodo/compose.yaml`](komodo/compose.yaml) — bootstrap do Komodo (Core + Mongo +
  Periphery); o único compose que o próprio Komodo não gerencia.
- [`komodo/compose.env.example`](komodo/compose.env.example) — modelo do `compose.env`
  real (segredos, não versionado — ver seção própria abaixo).
- [`komodo-sync/resources.toml`](komodo-sync/resources.toml) — export do estado do
  Komodo (Stacks, Builds, Server, Procedures) via Resource Sync, versionado para
  auditoria; não é aplicado automaticamente.
- [`stacks/`](stacks/) — um diretório por Stack (`lgmateus`, `turmasunb`, `albumcopa`,
  `gestao`, `ericsongomes`, `traefik`, `rustdesk`), cada um com o `compose.yaml` que o
  Komodo faz pull e sobe.
- [`bin/ufw-cloudflare.sh`](bin/ufw-cloudflare.sh) — restringe `80/443` às faixas de IP da Cloudflare.
- [`bin/pg-backup.sh`](bin/pg-backup.sh) — dump diário dos bancos Postgres (`pg-backup.timer`).
- [`bin/backup-vps.sh`](bin/backup-vps.sh) — backup do insubstituível (bancos,
  banco do Komodo, secrets, volumes docker com dado, mundo do Minecraft, chave do
  rustdesk, configs de sistema). Código das apps não entra — está no GitHub.
- [`mobile-claude.md`](mobile-claude.md) — acesso ao Claude Code pelo celular (mosh + tmux + Termius).
- `etc/systemd/system/{pg-backup.service,pg-backup.timer}` → as únicas units de app que
  seguem em systemd (as 4 apps migradas foram removidas daqui e do host).
- `etc/ssh/sshd_config.d/00-hardening.conf` → `/etc/ssh/sshd_config.d/00-hardening.conf`
- `etc/ssh/sshd_config.d/10-keepalive.conf` → `/etc/ssh/sshd_config.d/10-keepalive.conf`
- `etc/fail2ban/jail.local` → `/etc/fail2ban/jail.local`
- `etc/sysctl.d/99-swappiness.conf` → `/etc/sysctl.d/99-swappiness.conf`
- `etc/postgresql/10-docker.conf` → `listen_addresses` para as redes Docker alcançarem o Postgres do host.
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

Segunda camada além do lock de IP: **AOP** (mTLS Cloudflare→origem). O **Traefik** exige
o cert de cliente da Cloudflare — `tls.options=cf-aop@file` nos routers de cada Stack
(definido em [`stacks/traefik/dynamic/tls.yml`](stacks/traefik/dynamic/tls.yml),
validando contra a CA global `authenticated_origin_pull_ca.pem`); requests que não vêm
da CF (sem cert de cliente válido) recebem alerta TLS de certificado exigido, na própria
negociação — nem chega a virar request HTTP. Liga-se em **SSL/TLS → Origin Server →
Authenticated Origin Pulls** (opção **Global**) em cada zona. A CA pública é baixada de
`https://developers.cloudflare.com/ssl/static/authenticated_origin_pull_ca.pem` pra
`/etc/ssl/cloudflare/`, montada `:ro` no container do Traefik. Hoje **AOP está
obrigatório nos 5 domínios** — não sobrou nenhum em modo opcional.

Atrás da CF o Traefik veria só IPs da Cloudflare. `trustedIPs` em
[`stacks/traefik/traefik.yml`](stacks/traefik/traefik.yml) (as faixas oficiais da CF,
hardcoded nos dois entrypoints) faz o Traefik confiar no `X-Forwarded-For`/
`CF-Connecting-IP` que a Cloudflare manda, restaurando o **IP real do visitante** no
access log e no header repassado aos containers.

### Komodo + Traefik (painel, deploy, segredos, rollback)

O **Komodo** (Core + Mongo + Periphery, bootstrap em
[`komodo/compose.yaml`](komodo/compose.yaml)) é o painel/orquestrador; o **Traefik**
(`stacks/traefik/`) é quem termina TLS e roteia por domínio nas portas 80/443. Detalhes
de cada app em [`apps.md`](apps.md).

- **UI**: `https://komodo.lgmateus.com`, atrás do **Cloudflare Access** (one-time PIN
  por e-mail, sem IdP externo, sessão de 24h). O `bind 127.0.0.1:9120` do Core continua
  aberto de propósito como via de emergência por túnel SSH (`ssh -L 9120:localhost:9120
  mateus@srv1`), caso Traefik ou Access fiquem fora do ar.
- **Segredos do próprio Komodo** (senha do Mongo, `KOMODO_WEBHOOK_SECRET`,
  `KOMODO_JWT_SECRET`, credencial de admin): vivem em `/etc/komodo/komodo/compose.env`
  no host, **fora do git** — [`komodo/compose.env.example`](komodo/compose.env.example)
  é o modelo versionado, sem valores reais.
- **Segredos das apps** (`DATABASE_URL`, tokens, etc.): não ficam em arquivo nenhum —
  são **Variables** do Komodo (Settings → Variables na UI, ou `CreateVariable`/
  `UpdateVariableValue` na API), referenciadas no `environment:`/`build_args:` de cada
  `stacks/<app>/compose.yaml` com `[[NOME_DA_VARIABLE]]`. Ver contagem por app em
  [`apps.md`](apps.md).
- **API do Komodo**: chave em `/etc/komodo/komodo/api.env` no host (`chmod 600`, fora do
  git), headers `X-Api-Key`/`X-Api-Secret` contra `http://127.0.0.1:9120/read` (leitura)
  e `/execute` (ações, ex. `DeployStack`).

#### Rollback de uma Stack

Duas rotas, dependendo de onde está o problema:

1. **Bug no código da app** (o caminho normal): reverter/corrigir o commit **no repo da
   própria app** (não no `dotfiles`) e dar `git push`. O webhook dispara a Procedure
   `deploy-<app>` (`RunBuild` → `DeployStack`) sozinha.
2. **Precisa voltar rápido, sem esperar rebuild**: o Build do Komodo marca cada imagem
   com **duas tags** — `<app>:latest` e `<app>:<hash-do-commit>` (`docker images` mostra
   o histórico local). Para voltar pra uma build anterior sem rebuildar:
   ```sh
   docker tag <app>:<hash-anterior-conhecido-bom> <app>:latest
   ```
   e disparar `DeployStack` (pela UI ou `POST /execute {"type":"DeployStack","params":
   {"stack":"<app>"}}`) — como as Stacks usam `auto_pull: false`, o `docker compose up
   -d` sobe com a imagem local que acabou de virar `:latest`, sem tentar puxar nada de
   fora.
3. **Mudança em `stacks/<app>/compose.yaml` ou no Traefik** (este repo, sem webhook):
   `git revert` aqui, `git push`, e redeploy manual da Stack certa pela UI/API — um push
   no `dotfiles` não redeploya nada sozinho.

### Backup do Postgres

[`bin/pg-backup.sh`](bin/pg-backup.sh) faz `pg_dump -Fc` de `turmasunb` e `albumcopa`
pra `/var/backups/postgres/`, com retenção de **14 dias**. Roda como o user `postgres`
(peer auth) via `pg-backup.service`, agendado **diário** pelo `pg-backup.timer`
(`Persistent=true` — recupera execução perdida se a VPS estava off). É o complemento
granular ao snapshot **semanal** da Hostinger (disaster recovery): protege contra erro de
migração / delete / corrupção sem rolar a VPS inteira uma semana. Restaurar:
`pg_restore -d <db> /var/backups/postgres/<db>-<data>.dump`.

### Backup de tudo (disaster recovery manual)

[`bin/backup-vps.sh`](bin/backup-vps.sh) é o que sobra pra reconstruir a VPS do zero se
o disco morrer: todos os bancos Postgres do host, o banco do Komodo (backup nativo via
`km database backup`, cobre Stacks/Builds/Procedures/Variables — inclusive as 33
Variables com senha de banco, tokens e o PAT do GitHub), `compose.env`/`api.env` do
Komodo, os volumes docker com dado real (backups do turmasunb, chaves Ed25519
Core↔Periphery do Komodo), `/etc/ssl/cloudflare`, o mundo do Minecraft e os dados do
RustDesk (chave do servidor). Não é agendado — roda sob demanda antes de mexer grande na
VPS. Seguro rodar com tudo no ar: nenhum container é parado, só o `minecraft.service`
pausa por alguns segundos pra consistência do mundo.

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
