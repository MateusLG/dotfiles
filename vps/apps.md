# apps self-hosted

Dois sites migrados do Railway pra esta VPS (junho/2026), atrás da Cloudflare.

| App            | Stack            | Porta local | Serviço systemd     | Domínio          |
|----------------|------------------|-------------|---------------------|------------------|
| lgmateus.com   | Next.js 16 (Node)| 3000        | `lgmateus.service`  | lgmateus.com     |
| turmasunb      | FastAPI (Python) | 8000        | `turmasunb.service` | turmasunb.com    |

Código clonado em `~/apps/<app>`. Os dois rodam como serviço systemd (sobem no boot,
reiniciam em falha), expostos só em `127.0.0.1` e publicados pelo nginx.

## Fluxo de uma requisição

```
navegador → Cloudflare (proxy laranja, TLS na borda)
          → VPS:443 nginx (Origin Certificate, Full strict)
          → 127.0.0.1:{3000,8000} app (systemd)
          → Postgres local (só turmasunb)
```

## Deploy

```sh
deploy.sh lgmateus     # git pull + npm ci + build + restart + health
deploy.sh turmasunb    # git pull + uv pip install + restart + health
deploy.sh all
```

(`bin/deploy.sh`; na VPS há um symlink `~/.local/bin/deploy`.) Precisa do shell com
mise ativo (node/npm/uv no PATH).

## Logs / status

```sh
systemctl status lgmateus turmasunb
journalctl -u lgmateus -f
journalctl -u turmasunb -f
```

## TLS / Cloudflare

- Proxy **laranja** ligado nos dois domínios; SSL/TLS mode **Full (strict)**.
- nginx usa **Cloudflare Origin Certificates** (válidos ~15 anos) em
  `/etc/ssl/cloudflare/{lgmateus,turmasunb}.{crt,key}` — **não versionados** (a key é segredo).
  Regenerar em: painel Cloudflare → domínio → SSL/TLS → Origin Server → Create Certificate.
- DNS: registros A `@` e `www` → IP da VPS, proxied.

## turmasunb — Postgres

- Banco `turmasunb` / role `turmasunb` no Postgres local (apt). Guarda só a tabela
  `links` (PK `materia+turma`); a estrutura das turmas vem do `data.json` versionado no repo do app.
- Config do app em `~/apps/turmasunb/.env` (`DATABASE_URL`, `SEMESTER`, `BACKUP_TOKEN`,
  `BACKUP_PATH=~/apps/turmasunb/backups`) — **não versionado** (segredos).
- O app carrega os links em memória na inicialização → **reiniciar o serviço** após mexer
  direto no banco.
- Migração de dados (PG18 no Railway, cliente PG16 local não faz pg_dump entre versões):
  ```sh
  psql "$RAILWAY_PUBLIC_URL" -c "\copy links TO STDOUT" | psql "$LOCAL_URL" -c "\copy links FROM STDIN"
  ```

## Reproduzir do zero (resumo)

Não está no `setup.sh` (envolve segredos e passos manuais). Ordem:

1. `sudo apt-get install -y nginx postgresql certbot python3-certbot-nginx`
2. Clonar os repos em `~/apps`.
3. **turmasunb**: `uv venv --python 3.12 && uv pip install -r requirements.txt`; criar
   `.env`; criar role/db no Postgres; importar os dados.
4. **lgmateus**: `npm ci && npm run build`.
5. Instalar os units de `etc/systemd/system/` e habilitar (`systemctl enable --now`).
   No `lgmateus.service` o `ExecStart` aponta pro `node` absoluto do mise — **conferir o
   path da versão** se o mise atualizar o Node.
6. Instalar as confs de `etc/nginx/sites-available/`, linkar em `sites-enabled`,
   remover o `default`, instalar os Origin Certs, `nginx -t && systemctl reload nginx`.
7. `ufw allow 'Nginx Full'`.
8. Cloudflare: A records → VPS (proxied) + SSL mode Full (strict).
