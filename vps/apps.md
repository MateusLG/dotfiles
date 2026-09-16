# apps self-hosted

Apps self-hosted nesta VPS, atrás da Cloudflare (migradas do Railway em junho/2026,
e do systemd+nginx pro Komodo+Traefik em containers em agosto/2026).

| App          | Stack (Komodo) | Porta (container) | Domínio(s)                                    |
|--------------|-----------------|--------------------|------------------------------------------------|
| lgmateus     | `lgmateus`      | 3000               | lgmateus.com, www.lgmateus.com                  |
| turmasunb    | `turmasunb`     | 8000               | turmasunb.com, www.turmasunb.com                |
| os48 / CREA  | `gestao`        | 8002               | crea.lglabs.tech                                |
| ericsongomes | `ericsongomes`  | 8080               | ericsongomes.com.br, www.ericsongomes.com.br    |
| faturamento  | `faturamento`   | 8000               | faturamento.kodium.ai                         |
| SiPE (homolog) | `sipe-hom`    | 3000               | sipe-hom.lglabs.tech                            |
| ITSM (homolog) | `itsm-hom`    | 5000               | itsm-hom.lglabs.tech                            |
| Patrocínio (homolog) | `patrocinio-hom` **(parada)** | 8080 (api+web) | patrocinio-hom.lglabs.tech    |

Removidos em **2026-09-10**: `album-copa` (album.lgmateus.com; último dump em
`~/backups/albumcopa/`), a stack `rustdesk`, o ambiente de teste `patrocinio.lglabs.tech`
(processos no host + rota solta no `dynamic/` do Traefik, nunca versionada) e, a pedido,
**tudo da GTD**: stacks `embratur`, `sipe` e `itsm` com builds, procedures, variables, bancos
(`embratur_novo`, `sipe`, `itsm`), volumes (`embratur_media`, `itsm_anexos`), secrets em
`/etc/komodo/secrets` e webhooks — sem backup, por decisão. `lgmateus` está **parada** (não
apagada). Pendente só o DNS `album.lgmateus.com` (lglabs.tech é A wildcard).

Em **2026-09-16** SiPE, ITSM e Patrocínio subiram — **só como homologação** (`sipe-hom`,
`itsm-hom` e `patrocinio-hom`, ver seções próprias), a pedido, em bancos novos e sem nenhum
dado da GTD restaurado. Só o `embratur` (site Payload) segue fora.

A stack do `gestao` tem **dois** containers: a app e o sidecar `jobs`, que roda as tarefas
agendadas (ver seção própria). As demais têm um só.

Cada app é uma **Stack** do Komodo: compose versionado em `stacks/<app>/compose.yaml`,
imagem construída por uma **Build** do Komodo a partir do repo da própria app (não deste
repo de dotfiles) e publicada como `<app>:latest` (mais uma tag com o hash do commit).

## faturamento (sistema de faturamento da Kodium)

Sistema interno de OS/pagamentos/repasses (`KodiumAI/faturamento`): FastAPI +
Jinja2/HTMX, dark. Login por usuário (tabela `usuario`, senha scrypt, cookie de sessão
assinado com o Variable `FATURAMENTO_SESSAO_SECRET`); a migração seeda a equipe (Michel,
Nathan, Juan, Mateus, Marcus, Allyson) com a senha padrão do time. Cascata de repasses é
congelada em snapshot na confirmação do pagamento — editar template depois não recalcula
confirmados.

- Banco: `faturamento` no Postgres do host; migrações via alembic no start do container.
- Uploads (termos de aceite) no volume `uploads` da stack.
- `TZ=America/Sao_Paulo` no compose: `date.today()` define as datas de negócio.

## sipe-hom (homologação do SiPE)

Homologação do **SiPE** (`gtd-embratur/novo-sipe`), o Sistema Integrado de Planejamento
Estratégico da Embratur: Next 16 + Prisma + Auth.js v5, para o usuário testar fora do
cluster da Embratur.

**Não confundir com o homolog institucional** (`sipehom.embratur.com.br`), que roda no
Docker Swarm deles via Portainer, a partir do `stack.homol.yml` do repo da app. Aquele usa
login Google normal; este aqui é o cenário "VPS externa" que o próprio código prevê.

- `HOMOL=true` desliga o login Google (fail-closed) e liga o **picker de personas sem
  senha** da tela de login — 8 personas `@homolog.embratur.local`, uma por papel, criadas
  por `scripts/seed-homolog.ts`. O picker é persona-only: mesmo que um usuário real fosse
  parar no banco, ele não apareceria na lista.
- **O domínio não pode ser `embratur.com.br` nem subdomínio.** Com `HOMOL=true`, a guarda
  de boot (`instrumentation-node.ts`) resolve `AUTH_URL ?? NEXTAUTH_URL` e faz
  `process.exit(1)` se o host for institucional — senão seria login sem senha no ambiente
  real. Daí `sipe-hom.lglabs.tech`.
- **Aberto na internet, por decisão de 2026-09-16.** Como o picker não pede senha, quem
  chegar na URL entra como Admin. Não há Cloudflare Access na frente, ao contrário do
  painel do Komodo. O que limita o estrago: as personas são sintéticas
  (`@homolog.embratur.local`), o banco é só do ambiente e o sync com o Workspace nunca
  roda aqui, então não há dado pessoal real pra vazar. Se um dia precisar de barreira sem
  mexer na Cloudflare, um middleware `basicAuth` no router do Traefik resolve com um
  label.
- Banco `sipe_hom` no Postgres do host. O entrypoint da imagem roda `prisma migrate deploy`
  com retry antes de servir; o seed é **opt-in** (`SEED_AUTOMATICO` não setado), então
  rodar seed é manual — `prisma/seed.ts` (base) e depois `scripts/seed-homolog.ts`
  (personas, exige `HOMOL=true`).
- **Sem o service `sync-workspace`** do stack original: ele importaria os ~300 usuários
  reais do Google Workspace pra esta VPS, e o runbook da app marca isso como risco LGPD.
  Por isso também não há nenhuma `GOOGLE_*` na stack.
- Integração **Hermes desligada** (`HERMES_INTEGRACAO_DESABILITADA=1`); o
  `SKIP_HERMES_SECRETS_BOOT_CHECK=1` é obrigatório junto, senão o boot aborta cobrando os
  secrets HMAC mesmo com a integração off.
- Os módulos Relato de Ação e Indicadores, que o homolog institucional desliga na janela
  GPE 2027, ficam **ligados** aqui — o ambiente existe pra testar o sistema inteiro.

Sem webhook de deploy: a Build aponta pra `main` do repo da app, mas quem decide quando
subir versão nova é o usuário (`RunBuild sipe-hom` → `DeployStack sipe-hom`). Um push na
`main` do SiPE não redeploya este ambiente sozinho.

## itsm-hom (homologação do ITSM)

Homologação do **ITSM Embratur** (`gtd-embratur/itsm-embratur`): service desk com chamados,
SLA, RDM e base de conhecimento. Next 15 + Prisma + Auth.js v5.

`HOMOL=true` desliga o login Google (a checagem de domínio é fail-closed) e liga o picker de
usuários sem senha — **é daqui que o mecanismo do [sipe-hom](#sipe-hom-homologação-do-sipe)
veio**. Duas diferenças importantes em relação ao do SiPE, que é a versão endurecida depois:
o picker do ITSM entra como **qualquer usuário do banco** (não só personas sintéticas) e não
há guarda de boot por domínio. Por isso este banco só pode conter o mundo fake do
`scripts/seed-homolog.ts` — 54 usuários e 208 chamados espalhados pelos últimos 90 dias, com
âncoras fixas por perfil (`admin@`, `gerente@`, `coordenador@`, `analista@`,
`colaborador@embratur.gov.br`) pra logar direto em cada visão.

Aberto na internet, sem Cloudflare Access, pela mesma decisão de 2026-09-16 do sipe-hom.

A app nasceu no **Replit**, o que explica três coisas:

- **`ANEXOS_DIR=/dados/anexos`** na stack: sem essa env o storage de anexos tenta falar com o
  sidecar de Object Storage do Replit (`127.0.0.1:1106`), que não existe aqui. O volume cobre
  `/dados` porque a imagem pré-cria `/dados/anexos` já com posse do UID `10001` — um volume
  nomeado novo herda essa posse na primeira montagem.
- **Porta 5000**, não 3000.
- **`prisma db push` no start** (CMD da imagem), não `migrate deploy`: a cadeia de migrations
  do repo não tem a migration inicial (o schema nasceu por db push no Replit) e
  `migrate deploy` quebra em banco vazio.

O build depende do **GitHub Packages**: as libs `@gtd-embratur/{components,icons,tokens}` são
privadas da org. O Dockerfile recebe o token por **secret mount do BuildKit**
(`--mount=type=secret`), então a Build é a única da VPS com `use_buildx = true` e
`secret_args`. Hoje a Variable `GITHUB_PACKAGES_TOKEN` guarda o token do **`gh` CLI do
usuário** — funciona, mas quebra se ele rodar `gh auth refresh`/`logout`; o certo é um PAT
classic dedicado com `read:packages`.

O seed não roda na imagem de produção (o runner só tem o standalone — sem `tsx`, sem
`scripts/`). Pra reseedar, buildar o **stage `build`** do Dockerfile e rodar o `tsx` de lá,
lembrando de `chown -R 10001:10001` no volume depois, senão os anexos nascem `root` e a app
não consegue escrever.

Sem webhook de deploy, igual ao sipe-hom.

## patrocinio-hom (homologação do Patrocínio)

> **Parada desde 2026-09-16, a pedido — não apagada.** `StopStack patrocinio-hom` no Komodo:
> os dois containers ficam `Exited`, o Traefik perde a rota (o domínio responde 404) e todo
> o resto continua de pé — stack, as duas Builds, as imagens, as Variables, o banco
> `patrocinio_hom` com o seed e este compose. Religar é `StartStack` (ou `DeployStack`, que
> recria os containers). Mesma situação da `lgmateus`.

Homologação do **Sistema de Patrocínio** (`gtd-embratur/patrocinio-novo`): ciclo da proposta
enviada pela organização até a prestação de contas, nota fiscal e encaminhamento pra
pagamento. Monorepo pnpm — Express (`artifacts/api-server`) + SPA React/Vite
(`artifacts/web`) + Postgres via drizzle.

### Anexos não funcionam aqui — limitação aceita ao subir

O `objectStorage.ts` da API conversa **direto com o sidecar do Replit** (`127.0.0.1:1106`)
pra obter credencial GCS e gerar *presigned URL*; o browser faz `PUT` direto no bucket. Não
existe backend alternativo — o ITSM tem o fallback `ANEXOS_DIR`, este não tem. Fora do
Replit, portanto, **upload e download de arquivo falham**: anexo de proposta, nota fiscal e
comprobatórios da prestação de contas.

Funciona o resto: login, criação e tramitação de proposta, admin, gabinete e o RBAC
multi-perfil da SPEC-025. Consertar é **PR no repo da app**, não infra: o contrato de upload
nasce no `lib/api-spec` (OpenAPI é a fonte da verdade) e desce pro `api-zod` e o
`api-client-react` gerados a partir dele.

### Como está montado

O repo **não tem Dockerfile** — é canônico no Replit (Autoscale). Os dois Dockerfiles vivem
na **config das Builds do Komodo**, não no repo da app. Duas pegadinhas que custaram tempo:

- O campo `dockerfile` da Build é **ignorado quando a fonte é um repo git**: o Komodo passa
  `-f Dockerfile` e falha com *no such file or directory*. Quem escreve o Dockerfile no
  clone é o **`pre_build`** (com `shell_mode`, via heredoc).
- O `vite.config.ts` lança se `PORT` **ou** `BASE_PATH` faltarem — e isso vale pro
  `vite build`, que só carrega o config. Por isso o build da SPA passa as duas
  (`BASE_PATH=/`, já que a SPA é servida na raiz).

Front e API precisam da **mesma origem**, porque o cliente React chama caminhos relativos
(`/api/...`). Quem une os dois é o Traefik: o router da API casa
``Host(...) && PathPrefix(`/api`)`` com `priority=100`, o da SPA casa só o Host com
`priority=10`.

Efeitos colaterais externos (Monday, Gmail) ficam desligados por `MONDAY_DISABLED` e
`EMAIL_DISABLED`. O código já se protegeria sozinho — o portão de produção é
`REPLIT_DEPLOYMENT`, que não existe fora do Replit — mas as envs evitam até a tentativa de
conexão.

O schema **não precisa de migração manual**: a API roda `ensureSchema()` no boot e cria
enums/tabelas/colunas que faltarem. O seed (`lib/db/src/seed.ts`) traz 7 usuários
`@embratur.test` com senha, propostas em vários estados e prestações de contas em todas as
fases. Roda com o `tsx` que está em `lib/db/node_modules/.bin/` dentro da imagem da API.

Sem webhook de deploy, igual às outras homologações.

## Isolamento (container)

Cada app roda como container **não-root** (`node` no lgmateus; UID `10001` em
turmasunb/gestao/itsm-hom e na api do patrocinio-hom; `101` no ericsongomes e na web do
patrocinio-hom; `1001` no sipe-hom), com `cap_drop: ALL`,
`no-new-privileges` e `read_only: true` na raiz (exceto turmasunb, que escreve backup
em volume) — os diretórios que a app precisa escrever viram `tmpfs`. Cada container só
entra nas redes Docker que precisa:

- **`edge`**: todas as apps, é a rede que o Traefik enxerga (`exposedByDefault: false` — só
  publica quem tem `traefik.enable=true`).
- **`apps`**: só turmasunb e gestao, que falam com o Postgres do host via
  `host.docker.internal` (extra_hosts com `host-gateway`). É legado da migração: o
  `extra_hosts` sozinho já resolve o host-gateway de qualquer bridge, então faturamento e
  sipe-hom alcançam o Postgres estando só na `edge`.

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
          → Postgres nativo do host, pela rede `apps` (turmasunb, gestao)
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

Repos com webhook configurado: `lgmateus`, `turmasunb`, `site-ericson`,
`faturamento` e `OS48-CREA` (estes dois na org `KodiumAI`; o segundo alimenta `gestao`).
**`novo-sipe` não tem** — o `sipe-hom` é homologação e sobe versão quando o usuário manda
(ver seção própria).

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

Os Variables cadastrados no Komodo são referenciados no `environment:` de cada
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
- `lgmateus.{crt,key}` é wildcard `*.lgmateus.com`;
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
- **gestao**: db `crea_demo`, schema via alembic; contém dado de cliente em validação —
  ver `vps-os48-db-reset.md` na memória sobre reset/reseed.
- **faturamento**: db/role `faturamento`, schema via alembic (roda no start do
  container). Dado financeiro interno da Kodium.
- **sipe-hom**: db/role `sipe_hom`, schema via `prisma migrate deploy` (roda no entrypoint
  do container). Só dado sintético — as personas do picker e o que for criado no teste;
  o sync com o Workspace da Embratur não roda aqui de propósito.
- **itsm-hom**: db/role `itsm_hom`, schema via `prisma db push` (roda no start do container).
  Só dado sintético, do `seed-homolog.ts`. Como o picker entra como qualquer usuário do
  banco, **não restaurar dump de produção aqui**.
- **patrocinio-hom**: db/role `patrocinio_hom`, schema via `ensureSchema()` no boot da API
  (aditivo — cria o que faltar, não remove). Só dado sintético, do seed do `lib/db`.
- Postgres escuta em `listen_addresses='*'` (`etc/postgresql/10-docker.conf`); o controle
  de acesso real é `pg_hba.conf` (scram, faixa `172.16.0.0/12` — todas as bridges do
  Docker) e `ufw` (5432 fechado pra internet, liberado só para essa faixa).
- **Backup**: dump diário do banco `turmasunb` via `bin/pg-backup.sh` +
  `pg-backup.timer`, que **continuam em systemd** (retenção 14 dias em
  `/var/backups/postgres/`). Ver [`README.md`](README.md).
- **Backup completo sob demanda**: `bin/backup-vps.sh` cobre todos os bancos do host, o
  banco do Komodo (Stacks/Builds/Variables), secrets, volumes docker com dado e o mundo
  do Minecraft — ver seção própria no [`README.md`](README.md).

## Logs / status

```sh
docker ps --format 'table {{.Names}}\t{{.Status}}'
docker logs -f turmasunb-turmasunb-1
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
   `environment:` da Stack ou o `secret_args` da Build referencia. Reservar
   `build_args` somente para valores públicos que podem aparecer em logs e camadas da
   imagem.
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
