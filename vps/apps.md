# apps self-hosted

Apps self-hosted nesta VPS, atrás da Cloudflare (migrados do Railway em junho/2026).

| App          | Stack                       | Porta | Serviço             | User (sistema) | Domínio              |
|--------------|-----------------------------|-------|---------------------|----------------|----------------------|
| lgmateus     | Next.js 16 (Node)           | 3000  | `lgmateus.service`  | `lgmateus`     | lgmateus.com         |
| turmasunb    | FastAPI (Python)            | 8000  | `turmasunb.service` | `turmasunb`    | turmasunb.com        |
| album-copa   | FastAPI + Vite (serve dist) | 8001  | `albumcopa.service` | `albumcopa`    | album.lgmateus.com   |

## Isolamento (importante)

Cada app roda como **user de sistema dedicado, sem sudo**, com código em
**`/srv/<app>`** (não em `~/apps` — antes rodavam como `mateus`, que tem `NOPASSWD`,
o que tornava qualquer RCE num app uma escalada direta pra root). Cada user tem **mise
próprio** em `/srv/<app>/.local/bin/mise`.

As units têm um drop-in `*.service.d/10-hardening.conf` com sandbox systemd:
`NoNewPrivileges=yes` (mata escalada via `sudo`/setuid mesmo que o user tivesse),
`ProtectSystem=strict`, `ProtectHome=yes` (o processo não enxerga `/home/mateus` → a
chave SSH fica protegida), `ReadWritePaths=/srv/<app>`, etc. Um app comprometido não
vira root, não lê a chave SSH e não toca nos outros apps.

Os apps escutam só em `127.0.0.1`; quem publica é o nginx.

## Fluxo de uma requisição

```
navegador → Cloudflare (proxy laranja, TLS na borda)
          → VPS:443 nginx (Origin Certificate, Full strict)   [ufw: 80/443 só de IPs da CF]
          → 127.0.0.1:{3000,8000,8001} app (systemd, user dedicado)
          → Postgres local (turmasunb e album-copa)
```

## Deploy

```sh
deploy.sh lgmateus     # git pull + npm ci + build
deploy.sh turmasunb    # git pull + uv pip install
deploy.sh albumcopa    # git pull + uv sync (backend) + npm build (frontend)
deploy.sh all
```

(`bin/deploy.sh`; symlink `~/.local/bin/deploy`.) O script roda o build **como o user
dedicado** (`sudo -u <app>` com o mise daquele user) e reinicia o serviço + health check.

## Logs / status

```sh
systemctl status lgmateus turmasunb albumcopa
journalctl -u albumcopa -f
```

## TLS / Cloudflare

- Proxy **laranja** nos domínios; SSL/TLS mode **Full (strict)**.
- nginx usa **Cloudflare Origin Certificates** em `/etc/ssl/cloudflare/` — **não
  versionados** (a key é segredo). Regenerar em: painel Cloudflare → SSL/TLS → Origin
  Server → Create Certificate.
- `lgmateus.{crt,key}` é **wildcard `*.lgmateus.com`** → cobre `album.lgmateus.com` sem
  cert novo. `turmasunb.{crt,key}` cobre `turmasunb.com`.
- DNS: registros A → IP da VPS (`2.25.202.113`), **proxied**. `album` é A próprio
  (subdomínio).
- **Origem fechada em duas camadas:** `ufw` libera `80/443` só das faixas da Cloudflare
  (`bin/ufw-cloudflare.sh`) **e** os vhosts exigem o cert de cliente da CF via
  Authenticated Origin Pulls (`ssl_verify_client on`). Acesso direto na origem → `400`.
  Detalhes e rollout no [`README.md`](README.md).
- IP real do visitante restaurado no log (`bin/nginx-cloudflare-realip.sh`).

## Postgres (local, apt — só loopback, scram)

- **turmasunb**: db/role `turmasunb`, tabela `links` (PK `materia+turma`); estrutura das
  turmas vem do `data.json` versionado. Carrega em memória no boot → **reiniciar o
  serviço** após mexer no banco. `.env` em `/srv/turmasunb/.env`.
- **album-copa**: db/role `albumcopa` (tabelas `usuario`/`figurinha`/`colecao_usuario`/
  `audit_log`), schema via **alembic** (`alembic upgrade head`). Auth é só header
  `X-Username` (sem senha). `.env` em `/srv/albumcopa/backend/.env` (só `DATABASE_URL`).
- Migração Railway→local sempre por `\copy` (Railway PG18 vs cliente PG16 local não faz
  `pg_dump` cross-version). Lembrar de resetar as sequences após carregar dados:
  ```sh
  psql "$RAILWAY" -c "\copy <tabela> TO STDOUT" | psql "$LOCAL" -c "\copy <tabela> FROM STDIN"
  ```
- **Backup**: dump diário dos bancos (`turmasunb`, `albumcopa`) via
  `bin/pg-backup.sh` + `pg-backup.timer` (retenção 14 dias em `/var/backups/postgres/`).
  Ver [`README.md`](README.md).

## Reproduzir do zero (resumo)

Fora do `setup.sh` (envolve segredos e passos manuais). Por app:

1. `sudo apt-get install -y nginx postgresql`
2. User: `sudo useradd --system --create-home --home-dir /srv/<app> --shell /usr/sbin/nologin <app>`
3. Código em `/srv/<app>` (`chown -R <app>:<app>`); mise próprio do user
   (`curl https://mise.run | sh` com `HOME=/srv/<app>`) + runtime (`mise use -g ...`).
4. Build como o user: **turmasunb** `uv venv && uv pip install -r requirements.txt`;
   **lgmateus** `npm ci && npm run build`; **album-copa** `uv sync` no backend +
   `npm ci && npm run build` no frontend, criar role/db + `alembic upgrade head`.
5. Postgres: role/db dedicados, `.env` do app com `DATABASE_URL` local; importar dados.
6. Unit de `etc/systemd/system/<app>.service` + drop-in `…/10-hardening.conf`;
   `systemctl enable --now <app>`.
7. nginx: conf de `etc/nginx/sites-available/`, linkar em `sites-enabled`, remover o
   `default`, instalar os Origin Certs, `nginx -t && systemctl reload nginx`.
8. Firewall: `bin/ufw-cloudflare.sh` (libera 80/443 só da Cloudflare).
9. Cloudflare: A record → VPS (proxied) + SSL mode Full (strict).
