# vps

Configuração de uma **VPS Ubuntu 24.04 LTS (Hostinger)**, headless, acessada via SSH.
Usuário comum `mateus` no grupo `sudo`. Os arquivos espelham os caminhos reais de `/etc`.

## Conteúdo

- [`setup.sh`](setup.sh) — script idempotente que reproduz todo o setup abaixo.
- [`apps.md`](apps.md) — sites self-hosted (lgmateus.com, turmasunb) atrás da Cloudflare.
- [`bin/deploy.sh`](bin/deploy.sh) — deploy dos apps (git pull + build + restart + health).
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
Não há arquivo versionado — as regras são aplicadas pelo `setup.sh`.

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
