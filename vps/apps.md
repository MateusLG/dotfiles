# apps self-hosted

Apps self-hosted nesta VPS, atrás da Cloudflare (migradas do Railway em junho/2026,
e do systemd+nginx pro Komodo+Traefik em containers em agosto/2026).

| App          | Stack (Komodo) | Porta (container) | Domínio(s)                                    |
|--------------|-----------------|--------------------|------------------------------------------------|
| lgmateus     | `lgmateus`      | 3000               | lgmateus.com, www.lgmateus.com                  |
| turmasunb    | `turmasunb`     | 8000               | turmasunb.com, www.turmasunb.com                |
| album-copa   | `albumcopa`     | 8001               | album.lgmateus.com                              |
| os48 / CREA  | `gestao`        | 8002               | crea.lglabs.tech                                |
| ericsongomes | `ericsongomes`  | 8080               | ericsongomes.com.br, www.ericsongomes.com.br    |

A stack do `gestao` tem **dois** containers: a app e o sidecar `jobs`, que roda as tarefas
agendadas (ver seção própria). As demais têm um só.

Cada app é uma **Stack** do Komodo: compose versionado em `stacks/<app>/compose.yaml`,
imagem construída por uma **Build** do Komodo a partir do repo da própria app (não deste
repo de dotfiles) e publicada como `<app>:latest` (mais uma tag com o hash do commit).

## Isolamento (container)

Cada app roda como container **não-root** (`node` no lgmateus; UID `10001` em
turmasunb/albumcopa/gestao; `101` no ericsongomes), com `cap_drop: ALL`,
`no-new-privileges` e `read_only: true` na raiz (exceto turmasunb, que escreve backup
em volume) — os diretórios que a app precisa escrever viram `tmpfs`. Cada container só
entra nas redes Docker que precisa:

- **`edge`**: todos os 5, é a rede que o Traefik enxerga (`exposedByDefault: false` — só
  publica quem tem `traefik.enable=true`).
- **`apps`**: só turmasunb, album-copa e gestao, que falam com o Postgres do host via
  `host.docker.internal` (extra_hosts com `host-gateway`).

Nada do mundo pré-container sobrou no disco. Os diretórios `/srv/<app>`, os users de
sistema (`lgmateus`, `turmasunb`, `albumcopa`, `gestao`) e o `/var/www` foram removidos em
2026-08-24, depois que os jobs do gestao deixaram de depender do virtualenv em `/srv`
(ver seção própria abaixo). **`/srv` hoje contém apenas `minecraft`**, que segue em systemd
e não faz parte deste conjunto. Rollback, a partir daqui, é reconstruir a partir do git —
não existe mais interruptor.

Nenhuma app publica porta no host. Os containers são alcançados só pelo Traefik, pela rede
`edge`. As portas em `127.0.0.1` que existiram durante a transição — para o nginx continuar
apontando para o mesmo endereço enquanto as apps viravam container — foram removidas em
2026-08-24.

## Fluxo de uma requisição

```
navegador → Cloudflare (proxy laranja, TLS na borda)
          → ufw: 80/443 só das faixas de IP da Cloudflare
          → VPS:443 Traefik (Origin Certificate; mTLS via Authenticated Origin Pulls
            obrigatório — tls.options=cf-aop@file — nos 5 domínios)
          → container na rede `edge` (roteado por Host() + labels do compose)
          → Postgres nativo do host, pela rede `apps` (turmasunb, album-copa, gestao)
```

Sem nginx no caminho: quem termina TLS, roteia por domínio e fala com o Docker é o
Traefik (`stacks/traefik/`), via um `docker-socket-proxy` somente-leitura — o Traefik
nunca tem o socket do Docker montado direto.

## Deploy

`git push` no repo da própria app dispara um **webhook do GitHub** apontando para
`https://komodo.lgmateus.com/listener/github/procedure/deploy-<app>/main`. Isso executa
a Procedure `deploy-<app>` no Komodo, em dois estágios sequenciais:

```
RunBuild (rebuilda a imagem <app>:latest do commit novo)
  → DeployStack (docker compose up -d com a imagem nova)
```

Repos com webhook configurado: `lgmateus`, `turmasunb`, `album-copa`, `site-ericson` (do
`MateusLG`) e `OS48-CREA` (da org `KodiumAI`, para o gestao).

Este repo (**`dotfiles`**) **não tem webhook** — um push aqui pode afetar várias Stacks
ao mesmo tempo (compose, config do Traefik, etc.) e não há mapeamento automático de
arquivo pra Stack. Redeploy depois de mexer em `dotfiles` é manual, pela UI ou API do
Komodo (ver [`README.md`](README.md) para o passo a passo de rollback/redeploy).

### Painel do Komodo

`komodo.lgmateus.com`, atrás do **Cloudflare Access** (login por one-time PIN no e-mail
autorizado, sem IdP externo, sessão de 24h). O path `/listener` (onde o GitHub bate com
os webhooks) está em **Bypass** na política do Access — ele valida a entrega pela
assinatura HMAC (`X-Hub-Signature-256` contra `KOMODO_WEBHOOK_SECRET`), não por login.

## Segredos (Variables do Komodo)

As apps não leem mais `.env` do disco — a configuração vem do Komodo no momento do deploy.
Os arquivos antigos ainda existem em `/srv/turmasunb/.env` e `/srv/albumcopa/backend/.env`,
junto do resto do material de rollback, mas nenhum container os enxerga.

Os **33 Variables** cadastrados no Komodo
(turmasunb: 6, album-copa: 1, gestao: 26) são referenciados no `environment:` de cada
Stack com a sintaxe `NOME=[[NOME_DA_VARIABLE]]` e injetados na hora do deploy. Inclui,
no caso do gestao, as variáveis `VITE_*` do frontend — que são assadas no bundle em
**build time**, então entram como `build_args` da Build, não só como `environment` da
Stack.

## Jobs do gestao (rastreamento e conformidade)

Duas tarefas agendadas rodam como **sidecar da própria stack**: o serviço `jobs`, no
`vps/stacks/gestao/compose.yaml`, usa a **mesma imagem da app** e executa
`gestao/backend/scripts/agendador.py`. O agendador dispara `rastreamento` a cada minuto e
`conformidade` no minuto 0 de cada hora, chamando `http://gestao:8002` pela rede interna do
compose. Uma falha isolada é logada e não derruba o laço; todo log vai para stdout, então
aparece em `docker logs` e no Komodo.

Até 2026-08-24 isso eram dois timers do systemd (`gestao-rastreamento`,
`gestao-conformidade`) rodando um script solto em `/srv/gestao/bin` com o virtualenv do
host. Foram removidos, e com eles a última dependência de `/srv/gestao`.

O script e o agendador são **versionados no repo da app**, não aqui — então a contratante,
que vai rodar o sistema em outro servidor, recebe o agendamento junto com o
`compose.example.yaml`, sem precisar instalar cron nenhum.

## TLS / Cloudflare

- Proxy **laranja** nos domínios; SSL/TLS mode **Full (strict)**.
- O Traefik usa os mesmos **Cloudflare Origin Certificates** de antes, agora montados
  read-only em `/etc/ssl/cloudflare/` do host → `/certs` no container
  (`stacks/traefik/compose.yaml`) — **não versionados** (a key é segredo). Regenerar em:
  painel Cloudflare → SSL/TLS → Origin Server → Create Certificate.
- `lgmateus.{crt,key}` é wildcard `*.lgmateus.com` (cobre `album.lgmateus.com`);
  `turmasunb.{crt,key}` cobre `turmasunb.com`; `lglabs.tech.{crt,key}` cobre
  `crea.lglabs.tech`; `ericsongomes.{crt,key}` cobre `ericsongomes.com.br`.
- DNS: registros A → IP da VPS (`179.198.127.45`), **proxied**. `album` e `komodo` são A
  próprios (subdomínios de `lgmateus.com`).
- **Origem fechada em duas camadas:** `ufw` libera `80/443` só das faixas da Cloudflare
  (`bin/ufw-cloudflare.sh`) **e** o Traefik exige o cert de cliente da CF via
  Authenticated Origin Pulls (`tls.options=cf-aop@file`, validando contra
  `authenticated_origin_pull_ca.pem`) em **todos os 5 domínios** — acesso direto na
  origem devolve alerta TLS de certificado exigido, não HTTP. Detalhes no
  [`README.md`](README.md).
- O IP real do visitante chega ao Traefik via `forwardedHeaders.trustedIPs` (as faixas
  da Cloudflare, hardcoded em `stacks/traefik/traefik.yml`) — sem isso o log e os
  middlewares só veriam o IP da borda da CF.

## Postgres (local, apt — só loopback do host + rede Docker `apps`, scram)

- **turmasunb**: db/role `turmasunb`, tabela `links` (PK `materia+turma`); estrutura das
  turmas vem do `data.json` versionado. Carrega em memória no boot → **redeploy da
  Stack** após mexer no banco.
- **album-copa**: db/role `albumcopa` (tabelas `usuario`/`figurinha`/`colecao_usuario`/
  `audit_log`), schema via **alembic** (`alembic upgrade head`, roda no container).
  Auth é só header `X-Username` (sem senha).
- **gestao**: db `crea_demo`, schema via alembic; contém dado de cliente em validação —
  ver `vps-os48-db-reset.md` na memória sobre reset/reseed.
- Postgres escuta em `listen_addresses='*'` (`etc/postgresql/10-docker.conf`); o controle
  de acesso real é `pg_hba.conf` (scram, faixa `172.16.0.0/12` — todas as bridges do
  Docker) e `ufw` (5432 fechado pra internet, liberado só para essa faixa).
- **Backup**: dump diário dos bancos (`turmasunb`, `albumcopa`) via `bin/pg-backup.sh` +
  `pg-backup.timer`, que **continuam em systemd** (retenção 14 dias em
  `/var/backups/postgres/`). Ver [`README.md`](README.md).

## Logs / status

```sh
docker ps --format 'table {{.Names}}\t{{.Status}}'
docker logs -f albumcopa-albumcopa-1
```

Ou pela UI do Komodo (`komodo.lgmateus.com`): página da Stack → aba Log/Containers.

## Reproduzir do zero (resumo)

Fora do `setup.sh` (envolve segredos e passos manuais) e do bootstrap do Komodo
(`komodo/compose.yaml`, aplicado uma vez direto no host — é o único compose que o
próprio Komodo não gerencia). Por app nova:

1. Repo da app no GitHub, com um `Dockerfile` que builda uma imagem que escuta na porta
   escolhida.
2. Registrar o **Repo** no Komodo (provider `github.com`, conta com PAT fine-grained
   `Contents: Read-only`) e criar a **Build** apontando pra ele.
3. Criar as **Variables** que a app precisa (Komodo → Variables), com o nome que o
   `environment:`/`build_args:` do compose referencia.
4. Criar o diretório `stacks/<app>/compose.yaml` neste repo: rede `edge` (+ `apps` se
   precisar de Postgres), labels do Traefik (`traefik.enable`, `Host()`,
   `tls.options=cf-aop@file`, porta do `loadbalancer.server.port`), `cap_drop: ALL`,
   `no-new-privileges`, `read_only` quando der.
5. Criar a **Stack** no Komodo (repo=dotfiles, branch=main, `run_directory=stacks/<app>`,
   `auto_pull: false` — o Build local não tem registry pra puxar de volta), apontar pro
   `server_id` do `srv1`.
6. Postgres (se precisar): role/db dedicados, Variable com a `DATABASE_URL` apontando
   pra `host.docker.internal`; `extra_hosts: host-gateway` no compose.
7. Criar a **Procedure** `deploy-<app>` (`RunBuild` → `DeployStack`,
   `webhook_enabled: true`) e o webhook no GitHub apontando pra
   `https://komodo.lgmateus.com/listener/github/procedure/deploy-<app>/main`.
8. Cloudflare: A record → VPS (proxied), SSL mode Full (strict), Origin Certificate
   novo se o domínio não estiver coberto por um wildcard já existente.
