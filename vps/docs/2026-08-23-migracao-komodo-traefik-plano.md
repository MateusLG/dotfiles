# Plano de implementação — Migração para Komodo + Traefik

> **Para executores agênticos:** SUB-SKILL OBRIGATÓRIA: use `superpowers:subagent-driven-development`
> (recomendado) ou `superpowers:executing-plans` para executar tarefa a tarefa.
> Os passos usam checkbox (`- [ ]`) para acompanhamento.

**Objetivo:** colocar as 5 aplicações web da VPS em containers Docker gerenciados pelo
Komodo, com Traefik substituindo o nginx como proxy reverso, sem downtime planejado e
com rollback possível em cada etapa.

**Arquitetura:** Komodo (Core + Mongo + Periphery) sobe primeiro sem tocar em produção.
O Traefik entra em portas alternativas para ser validado enquanto o nginx ainda atende,
e só então assume 80/443. Cada app vira container uma por vez, com o roteamento saindo
de um arquivo estático (`legacy.yml`) e passando para labels do compose.

**Stack:** Docker Compose, Komodo v2, Traefik v3.7, MongoDB 8, nginx-unprivileged
(estático), Python 3.12/3.14 + uv, Node 24.

**Spec:** `vps/docs/2026-08-23-migracao-komodo-traefik.md` — leia antes de começar.

## Constraints globais

- Versões: Komodo tag `2` (atual 2.3.2), Traefik `v3.7`, Mongo `8`. A CPU é AMD EPYC
  9354P, tem AVX2 — requisito do Mongo 5+.
- **Nenhum segredo no git.** Segredos vivem em `/etc/komodo/komodo/compose.env`
  (`chmod 600`, fora do repo) e nas Variables/Secrets do Komodo.
- Toda stack, **exceto o compose do próprio Komodo**, é servida do repo `dotfiles` em
  modo *Git Repo*. Consequência: mudança em compose só vale depois de `git push` — commit
  local não basta.
- Nenhuma porta de aplicação é publicada no host. As apps escutam `0.0.0.0` **dentro** do
  container; quem publica é o Traefik.
- Endurecimento obrigatório em toda stack de app: `security_opt: [no-new-privileges:true]`,
  `cap_drop: [ALL]`, usuário não-root.
- `nginx`, `bin/deploy.sh` e as units systemd permanecem no disco até a Task 15. Nada é
  apagado antes de todas as apps estarem verdes em container.
- Idioma dos arquivos: PT-BR nos comentários e docs (projeto local).
- Rede `edge`: Traefik ↔ apps. Rede `apps`: apps ↔ Postgres do host. Nenhuma app fala
  com outra.

## Estrutura de arquivos

```
vps/
├── komodo/compose.yaml              # bootstrap: único compose fora do Komodo
├── komodo/compose.env.example       # nomes das variáveis, sem valores
├── stacks/traefik/compose.yaml      # traefik + socket-proxy
├── stacks/traefik/traefik.yml       # config estática
├── stacks/traefik/dynamic/tls.yml         # certs + tls options (AOP/mTLS)
├── stacks/traefik/dynamic/middlewares.yml # redirect www → apex
├── stacks/traefik/dynamic/legacy.yml      # TEMPORÁRIO: rotas p/ apps em systemd
├── stacks/ericsongomes/{compose.yaml,nginx.conf}
├── stacks/turmasunb/compose.yaml
├── stacks/albumcopa/compose.yaml
├── stacks/lgmateus/compose.yaml
├── stacks/gestao/compose.yaml
├── stacks/rustdesk/compose.yaml
├── etc/postgresql/10-docker.conf    # listen_addresses
└── docs/2026-08-23-migracao-komodo-traefik{,-plano}.md
```

Cada compose fica no seu diretório porque o Komodo aponta uma Stack para um
`run_directory` do repo — os arquivos que sobem juntos precisam morar juntos.

---

## Task 1: Base — redes Docker, `/etc/komodo` e esqueleto no dotfiles

**Arquivos:**
- Criar: `vps/komodo/`, `vps/stacks/`, `vps/etc/postgresql/`
- Modificar: `.gitignore` (raiz do repo dotfiles)

**Interfaces:**
- Produz: redes `edge` e `apps`; diretório `/etc/komodo` (o `PERIPHERY_ROOT_DIRECTORY`,
  usado por todas as tasks seguintes).

- [ ] **Passo 1: Verificar que as redes ainda não existem**

```bash
docker network ls --format '{{.Name}}' | grep -E '^(edge|apps)$'
```
Esperado: nenhuma saída.

- [ ] **Passo 2: Criar as redes**

```bash
docker network create edge
docker network create apps
```

- [ ] **Passo 3: Verificar**

```bash
docker network ls --format '{{.Name}}' | grep -E '^(edge|apps)$'
```
Esperado: `edge` e `apps`.

- [ ] **Passo 4: Criar a árvore do Periphery**

```bash
sudo mkdir -p /etc/komodo/{komodo,backups,syncs,stacks,repos}
sudo chown -R mateus:mateus /etc/komodo
```

- [ ] **Passo 5: Criar o esqueleto no dotfiles**

```bash
mkdir -p ~/dotfiles/vps/{komodo,stacks,etc/postgresql}
```

- [ ] **Passo 6: Blindar o repo contra segredo**

Acrescentar ao `~/dotfiles/.gitignore`:

```
vps/komodo/compose.env
```

- [ ] **Passo 7: Commit**

```bash
cd ~/dotfiles
git add .gitignore
git commit -m "chore: ignora o compose.env do komodo"
```

---

## Task 2: Komodo no ar (fase 0)

Produção não é tocada. O Core publica em `127.0.0.1:9120` e o acesso é por túnel SSH;
o domínio só entra na Task 6, junto com o Traefik.

**Arquivos:**
- Criar: `vps/komodo/compose.yaml`, `vps/komodo/compose.env.example`
- Criar (fora do git): `/etc/komodo/komodo/compose.yaml`, `/etc/komodo/komodo/compose.env`

**Interfaces:**
- Consome: redes `edge` e `apps` (Task 1).
- Produz: Core em `ws://core:9120` para o Periphery; servidor `srv1` conectado na UI;
  volume `keys` com o par Ed25519 Core↔Periphery.

- [ ] **Passo 1: Escrever `vps/komodo/compose.yaml`**

```yaml
## Komodo Core + Mongo + Periphery.
## Bootstrap: e o unico compose que nao e gerenciado pelo proprio Komodo.
## Fonte da verdade aqui; a copia viva fica em /etc/komodo/komodo/compose.yaml.
services:
  mongo:
    image: mongo:8
    labels:
      komodo.skip:
    command: --quiet --wiredTigerCacheSizeGB 0.25
    restart: unless-stopped
    volumes:
      - mongo-data:/data/db
      - mongo-config:/data/configdb
    environment:
      MONGO_INITDB_ROOT_USERNAME: ${KOMODO_DATABASE_USERNAME}
      MONGO_INITDB_ROOT_PASSWORD: ${KOMODO_DATABASE_PASSWORD}

  core:
    image: ghcr.io/moghtech/komodo-core:${COMPOSE_KOMODO_IMAGE_TAG:-2}
    init: true
    restart: unless-stopped
    depends_on:
      - mongo
    ports:
      ## Temporario: acesso por tunel SSH ate o Traefik assumir (Task 6).
      - "127.0.0.1:9120:9120"
    env_file: ./compose.env
    environment:
      KOMODO_DATABASE_ADDRESS: mongo:27017
    volumes:
      - keys:/config/keys
      - ${COMPOSE_KOMODO_BACKUPS_PATH}:/backups
      - /etc/komodo/syncs:/syncs
    networks:
      - default
      - edge

  periphery:
    image: ghcr.io/moghtech/komodo-periphery:${COMPOSE_KOMODO_IMAGE_TAG:-2}
    init: true
    restart: unless-stopped
    depends_on:
      - core
    env_file: ./compose.env
    volumes:
      - keys:/config/keys
      - /var/run/docker.sock:/var/run/docker.sock
      - /proc:/proc
      - /etc/komodo:/etc/komodo

volumes:
  mongo-data:
  mongo-config:
  keys:

networks:
  edge:
    external: true
```

- [ ] **Passo 2: Escrever `vps/komodo/compose.env.example`**

Só os nomes, com os valores sensíveis marcados. É o arquivo versionado.

```sh
COMPOSE_KOMODO_IMAGE_TAG=2
COMPOSE_KOMODO_BACKUPS_PATH=/etc/komodo/backups
TZ=America/Sao_Paulo

## Banco
KOMODO_DATABASE_USERNAME=komodo
KOMODO_DATABASE_PASSWORD=<openssl rand -hex 24>

## Core
KOMODO_HOST=https://komodo.lgmateus.com
KOMODO_TITLE=srv1
KOMODO_PERIPHERY_PUBLIC_KEY=file:/config/keys/periphery.pub
KOMODO_LOCAL_AUTH=true
KOMODO_INIT_ADMIN_USERNAME=mateus
KOMODO_INIT_ADMIN_PASSWORD=<openssl rand -hex 16>
KOMODO_FIRST_SERVER_NAME=srv1
KOMODO_WEBHOOK_SECRET=<openssl rand -hex 24>
KOMODO_JWT_SECRET=<openssl rand -hex 32>
KOMODO_DISABLE_USER_REGISTRATION=true
KOMODO_ENABLE_NEW_USERS=false

## Periphery
PERIPHERY_CORE_ADDRESS=ws://core:9120
PERIPHERY_CONNECT_AS=${KOMODO_FIRST_SERVER_NAME}
PERIPHERY_CORE_PUBLIC_KEYS=file:/config/keys/core.pub
PERIPHERY_ROOT_DIRECTORY=/etc/komodo
PERIPHERY_DISABLE_TERMINALS=false
PERIPHERY_INCLUDE_DISK_MOUNTS=/etc/hostname
```

- [ ] **Passo 3: Gerar o `compose.env` real**

```bash
cp ~/dotfiles/vps/komodo/compose.yaml /etc/komodo/komodo/compose.yaml
cp ~/dotfiles/vps/komodo/compose.env.example /etc/komodo/komodo/compose.env
chmod 600 /etc/komodo/komodo/compose.env
```

Substituir cada `<openssl rand ...>` rodando o comando indicado e colando o valor.
Guardar o `KOMODO_INIT_ADMIN_PASSWORD` — é a senha do primeiro login.

- [ ] **Passo 4: Verificar que a 9120 está livre**

```bash
ss -tlpn | grep 9120
```
Esperado: nenhuma saída.

- [ ] **Passo 5: Subir**

```bash
docker compose -p komodo -f /etc/komodo/komodo/compose.yaml \
  --env-file /etc/komodo/komodo/compose.env up -d
```

- [ ] **Passo 6: Verificar que o Core responde e o Periphery conectou**

```bash
curl -sf http://127.0.0.1:9120/health && echo OK
docker logs komodo-periphery-1 2>&1 | tail -20
```
Esperado: `OK`, e o log do Periphery sem erro de handshake.

Se o endpoint `/health` não existir nesta versão, use `curl -s -o /dev/null -w '%{http_code}'
http://127.0.0.1:9120` e espere `200`.

- [ ] **Passo 7: Abrir a UI pelo túnel e conferir**

Na máquina local: `ssh -L 9120:localhost:9120 srv1`, depois `http://localhost:9120`.
Login com `KOMODO_INIT_ADMIN_USERNAME` / `KOMODO_INIT_ADMIN_PASSWORD`.
Conferir: servidor `srv1` conectado com métricas de CPU/disco, e os containers `hbbs`/`hbbr`
do rustdesk visíveis na aba de containers.

- [ ] **Passo 8: Verificar o consumo de memória**

```bash
docker stats --no-stream --format 'table {{.Name}}\t{{.MemUsage}}'
free -h
```
Esperado: soma dos três containers abaixo de ~800MB, e `available` ainda acima de 1G.
Se ficar abaixo disso, pare e reavalie o heap do minecraft antes de seguir.

- [ ] **Passo 9: Commit**

```bash
cd ~/dotfiles
git add vps/komodo/
git commit -m "add: compose do komodo (core + mongo + periphery)"
git push
```

**Rollback:** `docker compose -p komodo down`. Nada em produção foi tocado.

---

## Task 3: Provider do GitHub e Builder no Komodo

Habilita clonar repo privado e buildar imagem. É configuração de UI + um passo manual
no GitHub.

**Arquivos:** nenhum (configuração no banco do Komodo).

**Interfaces:**
- Consome: Komodo no ar (Task 2).
- Produz: git provider `github.com` com a conta `MateusLG`, e um Builder chamado `srv1`
  apontando para o servidor local — ambos referenciados por toda Build das Tasks 8-12.

- [ ] **Passo 1: Criar o PAT no GitHub (manual)**

Em github.com → Settings → Developer settings → Fine-grained tokens. Escopo: só os repos
`album-copa`, `lgmateus.com`, `site-ericson` e `KodiumAI/OS0048-Modulo-Gestao-CREA`.
Permissão: `Contents: Read-only`. Validade: 1 ano.

O `gh` não cria token fine-grained por CLI — este passo é obrigatoriamente pelo navegador.

- [ ] **Passo 2: Registrar o provider no Komodo**

UI → Settings → Providers → Git Providers → adicionar:
domínio `github.com`, usuário `MateusLG`, token do passo 1, HTTPS habilitado.

**Não** duplicar isso no `core.config.toml`: entrada de UI sobrescreve a de arquivo em
silêncio e o sintoma é um 403 no clone difícil de diagnosticar
(`moghtech/komodo` issue #1216).

- [ ] **Passo 3: Criar o Builder**

UI → Builders → New → tipo `Server`, apontando para o servidor `srv1`. Nome: `srv1`.

**Como a imagem é nomeada:** sem `image_registry` configurado, a Build não empurra para
lugar nenhum — a imagem fica local no Docker da VPS. O nome é o nome da Build, e
`include_latest_tag` vem ligado por padrão, então `<nome>:latest` sempre existe. É por
isso que as stacks das Tasks 8-12 referenciam `image: <app>:latest`. O Komodo também cria
tags semver (`:1.2.3`) a cada build, com auto-incremento do patch — úteis para voltar uma
versão pelo `docker images`.

- [ ] **Passo 4: Verificar**

Criar um Repo de teste apontando para `MateusLG/album-copa`, rodar "Clone", conferir que
o clone aparece em `/etc/komodo/repos/` e apagar o recurso de teste em seguida.

```bash
ls /etc/komodo/repos/
```

---

## Task 4: Traefik em portas alternativas

O Traefik sobe completo — certs, mTLS, middlewares — mas em `8080`/`8443`, que o ufw não
libera. Produção segue no nginx. Isso permite validar TLS e roteamento antes do corte.

**Arquivos:**
- Criar: `vps/stacks/traefik/compose.yaml`, `vps/stacks/traefik/traefik.yml`,
  `vps/stacks/traefik/dynamic/{tls.yml,middlewares.yml,legacy.yml}`

**Interfaces:**
- Consome: rede `edge` (Task 1); certs em `/etc/ssl/cloudflare`.
- Produz: tls options `cf-aop` e `cf-aop-optional` (referenciadas como `cf-aop@file` nas
  labels das Tasks 5, 8-13); middleware `redirect-to-apex@file`.

- [ ] **Passo 1: Escrever `vps/stacks/traefik/traefik.yml`**

As faixas em `trustedIPs` são as mesmas de `bin/ufw-cloudflare.sh`; sem elas, o IP que
chega nos logs é o da Cloudflare, não o do visitante.

```yaml
global:
  checkNewVersion: false
  sendAnonymousUsage: false

log:
  level: INFO
accessLog: {}

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true
    forwardedHeaders:
      trustedIPs: &cf_ips
        - 173.245.48.0/20
        - 103.21.244.0/22
        - 103.22.200.0/22
        - 103.31.4.0/22
        - 141.101.64.0/18
        - 108.162.192.0/18
        - 190.93.240.0/20
        - 188.114.96.0/20
        - 197.234.240.0/22
        - 198.41.128.0/17
        - 162.158.0.0/15
        - 104.16.0.0/13
        - 104.24.0.0/14
        - 172.64.0.0/13
        - 131.0.72.0/22
        - 2400:cb00::/32
        - 2606:4700::/32
        - 2803:f800::/32
        - 2405:b500::/32
        - 2405:8100::/32
        - 2a06:98c0::/29
        - 2c0f:f248::/32
  websecure:
    address: ":443"
    forwardedHeaders:
      trustedIPs: *cf_ips

providers:
  docker:
    endpoint: "tcp://socket-proxy:2375"
    exposedByDefault: false
    network: edge
  file:
    directory: /etc/traefik/dynamic
    watch: true
```

- [ ] **Passo 2: Escrever `vps/stacks/traefik/dynamic/tls.yml`**

```yaml
tls:
  options:
    cf-aop:
      minVersion: VersionTLS12
      sniStrict: true
      clientAuth:
        caFiles:
          - /certs/authenticated_origin_pull_ca.pem
        clientAuthType: RequireAndVerifyClientCert
    ## So para crea.lglabs.tech, ate ligar AOP na zona lglabs.tech no dashboard.
    cf-aop-optional:
      minVersion: VersionTLS12
      clientAuth:
        caFiles:
          - /certs/authenticated_origin_pull_ca.pem
        clientAuthType: VerifyClientCertIfGiven
  certificates:
    - certFile: /certs/lgmateus.crt
      keyFile: /certs/lgmateus.key
    - certFile: /certs/turmasunb.crt
      keyFile: /certs/turmasunb.key
    - certFile: /certs/lglabs.tech.crt
      keyFile: /certs/lglabs.tech.key
    - certFile: /certs/ericsongomes.crt
      keyFile: /certs/ericsongomes.key
```

Todos são wildcard + apex e valem até 2041 — `komodo.lgmateus.com` já está coberto pelo
cert do `lgmateus`.

- [ ] **Passo 3: Escrever `vps/stacks/traefik/dynamic/middlewares.yml`**

Só o ericsongomes redireciona www → apex hoje; lgmateus e turmasunb servem os dois nomes
sem redirect, e isso é preservado.

```yaml
http:
  middlewares:
    redirect-to-apex:
      redirectRegex:
        regex: "^https://www\\.(.+)"
        replacement: "https://${1}"
        permanent: true
```

- [ ] **Passo 4: Escrever `vps/stacks/traefik/dynamic/legacy.yml`**

Temporário: aponta para as apps que ainda rodam em systemd. Cada app migrada some daqui.
O ericsongomes não entra — ele vira container na Task 5.

```yaml
## TEMPORARIO — rotas para as apps ainda em systemd.
## Cada entrada e removida quando a app vira container (Tasks 8-11).
## Este arquivo e apagado na Task 15.
http:
  routers:
    legacy-lgmateus:
      rule: "Host(`lgmateus.com`) || Host(`www.lgmateus.com`)"
      entryPoints: [websecure]
      service: legacy-lgmateus
      tls:
        options: cf-aop
    legacy-turmasunb:
      rule: "Host(`turmasunb.com`) || Host(`www.turmasunb.com`)"
      entryPoints: [websecure]
      service: legacy-turmasunb
      tls:
        options: cf-aop
    legacy-albumcopa:
      rule: "Host(`album.lgmateus.com`)"
      entryPoints: [websecure]
      service: legacy-albumcopa
      tls:
        options: cf-aop
    legacy-gestao:
      rule: "Host(`crea.lglabs.tech`)"
      entryPoints: [websecure]
      service: legacy-gestao
      tls:
        options: cf-aop-optional

  services:
    legacy-lgmateus:
      loadBalancer:
        servers:
          - url: "http://host.docker.internal:3000"
    legacy-turmasunb:
      loadBalancer:
        servers:
          - url: "http://host.docker.internal:8000"
    legacy-albumcopa:
      loadBalancer:
        servers:
          - url: "http://host.docker.internal:8001"
    legacy-gestao:
      loadBalancer:
        servers:
          - url: "http://host.docker.internal:8002"
```

- [ ] **Passo 5: Escrever `vps/stacks/traefik/compose.yaml`**

`cap_add: NET_BIND_SERVICE` é obrigatório: com `cap_drop: ALL` o Traefik não consegue dar
bind na 80/443 dentro do container.

```yaml
services:
  socket-proxy:
    image: tecnativa/docker-socket-proxy:0.3.0
    restart: unless-stopped
    read_only: true
    environment:
      CONTAINERS: 1
      POST: 0
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - socket

  traefik:
    image: traefik:v3.7
    restart: unless-stopped
    depends_on:
      - socket-proxy
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    ports:
      ## Portas alternativas ate o corte (Task 6), onde viram 80 e 443.
      - "127.0.0.1:8080:80"
      - "127.0.0.1:8443:443"
    volumes:
      - ./traefik.yml:/etc/traefik/traefik.yml:ro
      - ./dynamic:/etc/traefik/dynamic:ro
      - /etc/ssl/cloudflare:/certs:ro
    extra_hosts:
      - "host.docker.internal:host-gateway"
    networks:
      - edge
      - socket

networks:
  edge:
    external: true
  socket:
    internal: true
```

- [ ] **Passo 6: Commit e push**

O Komodo lê do GitHub, então push aqui não é opcional.

```bash
cd ~/dotfiles
git add vps/stacks/traefik/
git commit -m "add: stack do traefik com origin certs e mTLS da cloudflare"
git push
```

- [ ] **Passo 7: Criar a Stack no Komodo**

UI → Stacks → New → nome `traefik`, modo *Git Repo*:
repo `MateusLG/dotfiles`, branch `main`, run directory `vps/stacks/traefik`.
Deploy.

- [ ] **Passo 8: Verificar que subiu sem erro de config**

```bash
docker logs $(docker ps -qf name=traefik) 2>&1 | grep -iE 'error|fatal' | head
```
Esperado: nenhuma saída. Erro de sintaxe em tls options aparece aqui.

- [ ] **Passo 9: Verificar o roteamento e o mTLS**

```bash
# Sem cert de cliente: a conexao deve ser recusada no handshake (isso e o AOP funcionando)
curl -sv --resolve turmasunb.com:8443:127.0.0.1 https://turmasunb.com:8443/ 2>&1 | \
  grep -iE 'certificate required|alert|SSL_ERROR|subject:'

# O crea esta em modo permissivo e deve responder 200 mesmo sem cert de cliente
curl -s -o /dev/null -w '%{http_code}\n' --resolve crea.lglabs.tech:8443:127.0.0.1 \
  https://crea.lglabs.tech:8443/
```
Esperado: o primeiro comando mostra recusa por falta de cert de cliente; o segundo
imprime `200`, provando que o roteamento até o uvicorn na 8002 funciona.

Se o segundo devolver `404`, o router não casou — confira `docker exec $(docker ps -qf name=traefik) traefik healthcheck` e o `legacy.yml`.

**Rollback:** apagar a Stack no Komodo. O nginx nunca parou.

---

## Task 5: ericsongomes em container

Precisa acontecer **antes** do corte: quem serve o estático dele é o próprio nginx, então
desligar o nginx sem isso derruba o site.

Nesta task o container só monta o build que já existe em `/var/www` — o `deploy ericsongomes`
continua funcionando igual. A conversão para Build próprio é a Task 12, deliberadamente
depois do corte, para não somar variáveis no momento mais arriscado.

**Arquivos:**
- Criar: `vps/stacks/ericsongomes/compose.yaml`, `vps/stacks/ericsongomes/nginx.conf`

**Interfaces:**
- Consome: `cf-aop@file` e `redirect-to-apex@file` (Task 4); `/var/www/ericsongomes/`.
- Produz: serviço `ericsongomes` na rede `edge`, porta interna 8080.

- [ ] **Passo 1: Escrever `vps/stacks/ericsongomes/nginx.conf`**

Tradução fiel do vhost atual: redirect de `/calculadora`, `alias` da calculadora,
`try_files` com index.html, cache imutável nos `_next/static`, cache de 30 dias em imagem
e `must-revalidate` no resto. A porta é 8080 porque a imagem roda como usuário 101.

```nginx
server {
    listen 8080;
    server_name _;

    root /srv/www/site;
    index index.html;
    charset utf-8;

    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css application/javascript application/json
               image/svg+xml application/rss+xml;

    location = /calculadora { return 301 /calculadora/; }

    location ^~ /calculadora/ {
        alias /srv/www/calculadora/;
        try_files $uri $uri/index.html =404;

        location ^~ /calculadora/_next/static/ {
            add_header Cache-Control "public, max-age=31536000, immutable";
        }
    }

    location ^~ /_next/static/ {
        add_header Cache-Control "public, max-age=31536000, immutable";
    }

    location ~* \.(jpg|jpeg|png|webp|avif|svg|ico|woff2)$ {
        add_header Cache-Control "public, max-age=2592000";
    }

    location / {
        add_header Cache-Control "public, max-age=0, must-revalidate";
        try_files $uri $uri/index.html =404;
    }

    error_page 404 /404.html;
}
```

- [ ] **Passo 2: Escrever `vps/stacks/ericsongomes/compose.yaml`**

```yaml
services:
  ericsongomes:
    image: nginxinc/nginx-unprivileged:alpine
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    read_only: true
    tmpfs:
      - /tmp
      - /var/cache/nginx
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
      ## Build gerado pelo `deploy ericsongomes` (vira Build proprio na Task 12).
      - /var/www/ericsongomes:/srv/www:ro
    networks:
      - edge
    labels:
      - traefik.enable=true
      - traefik.docker.network=edge
      - traefik.http.routers.ericsongomes.rule=Host(`ericsongomes.com.br`)
      - traefik.http.routers.ericsongomes.entrypoints=websecure
      - traefik.http.routers.ericsongomes.tls.options=cf-aop@file
      - traefik.http.services.ericsongomes.loadbalancer.server.port=8080
      - traefik.http.routers.ericsongomes-www.rule=Host(`www.ericsongomes.com.br`)
      - traefik.http.routers.ericsongomes-www.entrypoints=websecure
      - traefik.http.routers.ericsongomes-www.tls.options=cf-aop@file
      - traefik.http.routers.ericsongomes-www.middlewares=redirect-to-apex@file
      - traefik.http.routers.ericsongomes-www.service=ericsongomes

networks:
  edge:
    external: true
```

- [ ] **Passo 3: Commit e push**

```bash
cd ~/dotfiles
git add vps/stacks/ericsongomes/
git commit -m "add: stack do ericsongomes (nginx servindo o build estatico)"
git push
```

- [ ] **Passo 4: Criar a Stack no Komodo**

Nome `ericsongomes`, modo *Git Repo*, run directory `vps/stacks/ericsongomes`. Deploy.

- [ ] **Passo 5: Verificar pelo Traefik alternativo**

O `cf-aop` recusa conexão sem cert de cliente, então teste direto no container:

```bash
CID=$(docker ps -qf name=ericsongomes)
docker exec "$CID" curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8080/
docker exec "$CID" curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8080/calculadora/
docker exec "$CID" curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8080/nao-existe
```
Esperado: `200`, `200`, `404`.

Se a imagem não tiver `curl`, use `docker run --rm --network edge curlimages/curl -s -o
/dev/null -w '%{http_code}\n' http://ericsongomes-ericsongomes-1:8080/`.

- [ ] **Passo 6: Confirmar que o Traefik enxergou as labels**

```bash
docker logs $(docker ps -qf name=traefik) 2>&1 | tail -20
```
Esperado: nenhum erro sobre `ericsongomes`.

**Rollback:** apagar a Stack. O nginx ainda serve o site normalmente.

---

## Task 6: Corte — Traefik assume 80/443

O momento crítico. Tudo já foi validado; aqui só se troca quem escuta nas portas.

**Arquivos:**
- Modificar: `vps/stacks/traefik/compose.yaml` (bloco `ports`)
- Modificar: `vps/komodo/compose.yaml` (remove o bind em 9120, adiciona labels)

**Interfaces:**
- Consome: Stack `traefik` validada (Task 4), `ericsongomes` no ar (Task 5).
- Produz: os 5 domínios das apps + `komodo.lgmateus.com` servidos pelo Traefik.

- [ ] **Passo 1: Registrar o estado atual, para comparação depois**

```bash
for h in lgmateus.com turmasunb.com album.lgmateus.com crea.lglabs.tech ericsongomes.com.br; do
  printf '%s -> %s\n' "$h" "$(curl -s -o /dev/null -w '%{http_code}' https://$h/)"
done
```
Esperado: `200` em todos (a requisição sai pela Cloudflare e volta). Guarde a saída.

- [ ] **Passo 2: DNS do Komodo (manual)**

Cloudflare → zona `lgmateus.com` → registro A `komodo` → IP da VPS, **proxied**.

- [ ] **Passo 3: Cloudflare Access (manual)**

Zero Trust → Access → Applications → Self-hosted → `komodo.lgmateus.com`.
Política: Allow, e-mail `mateuslira3105@gmail.com`, método OTP por e-mail.
Sem isso, o passo 6 expõe a UI só com a auth local do Komodo.

- [ ] **Passo 4: Trocar as portas do Traefik**

Em `vps/stacks/traefik/compose.yaml`, substituir o bloco `ports`:

```yaml
    ports:
      - "80:80"
      - "443:443"
```

- [ ] **Passo 5: Adicionar as labels do Komodo no compose dele**

Em `vps/komodo/compose.yaml`, no serviço `core`: apagar o bloco `ports` inteiro e
acrescentar:

```yaml
    labels:
      - traefik.enable=true
      - traefik.docker.network=edge
      - traefik.http.routers.komodo.rule=Host(`komodo.lgmateus.com`)
      - traefik.http.routers.komodo.entrypoints=websecure
      - traefik.http.routers.komodo.tls.options=cf-aop@file
      - traefik.http.services.komodo.loadbalancer.server.port=9120
```

- [ ] **Passo 6: Commit e push**

```bash
cd ~/dotfiles
git add vps/stacks/traefik/compose.yaml vps/komodo/compose.yaml
git commit -m "update: traefik assume 80/443 e komodo passa a ser servido por dominio"
git push
```

- [ ] **Passo 7: O corte**

Três comandos em sequência; a janela de indisponibilidade é o intervalo entre eles.

```bash
sudo systemctl disable --now nginx
cp ~/dotfiles/vps/komodo/compose.yaml /etc/komodo/komodo/compose.yaml
docker compose -p komodo -f /etc/komodo/komodo/compose.yaml \
  --env-file /etc/komodo/komodo/compose.env up -d
```

Depois, na UI do Komodo: Stack `traefik` → Redeploy (ela puxa o compose novo do git).

- [ ] **Passo 8: Verificar os domínios**

```bash
for h in lgmateus.com turmasunb.com album.lgmateus.com crea.lglabs.tech ericsongomes.com.br komodo.lgmateus.com; do
  printf '%s -> %s\n' "$h" "$(curl -s -o /dev/null -w '%{http_code}' https://$h/)"
done
```
Esperado: mesmo resultado do passo 1 para os 5 primeiros. O `komodo.lgmateus.com`
devolve `302` para o Cloudflare Access — se devolver `200`, o Access **não** está ativo,
e é preciso resolver isso antes de seguir.

- [ ] **Passo 9: Verificar que a origem continua fechada**

```bash
curl -sv --resolve lgmateus.com:443:127.0.0.1 https://lgmateus.com/ 2>&1 | \
  grep -iE 'certificate required|alert|SSL_ERROR'
```
Esperado: recusa no handshake — é o AOP barrando quem não vem da Cloudflare.

- [ ] **Passo 10: Verificar o IP real nos logs**

```bash
docker logs $(docker ps -qf name=traefik) 2>&1 | tail -5
```
Esperado: `ClientAddr`/`X-Forwarded-For` com IP de visitante, não com IP de faixa da
Cloudflare. Se vier IP da CF, `trustedIPs` está errado.

**Rollback (< 1 min):**

```bash
docker compose -p traefik down    # ou "Destroy" na UI do Komodo
sudo systemctl enable --now nginx
```
O ericsongomes volta a ser servido pelo vhost, que continua no disco.

---

## Task 7: Postgres acessível pela rede Docker

**Arquivos:**
- Criar: `vps/etc/postgresql/10-docker.conf`
- Modificar: `/etc/postgresql/18/main/pg_hba.conf`, regras do ufw

**Interfaces:**
- Produz: Postgres alcançável em `host.docker.internal:5432` a partir de containers —
  consumido pelas Tasks 8, 9, 11.

- [ ] **Passo 1: Confirmar que o `conf.d` é incluído**

```bash
grep -n "include_dir" /etc/postgresql/18/main/postgresql.conf
```
Esperado: `include_dir = 'conf.d'`. Se não houver, edite `postgresql.conf` direto no
passo 3 em vez de criar arquivo no `conf.d`.

- [ ] **Passo 2: Provar que hoje o container não alcança o banco**

```bash
docker run --rm --network apps --add-host host.docker.internal:host-gateway \
  postgres:18-alpine \
  psql "postgresql://postgres@host.docker.internal:5432/postgres" -c 'select 1' 2>&1 | head -3
```
Esperado: falha de conexão. É o estado que a task corrige.

- [ ] **Passo 3: Criar `vps/etc/postgresql/10-docker.conf`**

`listen_addresses = '*'` em vez do IP da bridge de propósito: se o Postgres subir antes
do `docker0` existir, bind em IP fixo falha e o banco não sobe. O controle de acesso fica
no `pg_hba` e no ufw.

```conf
# Permite conexao vinda das redes Docker. Controle de acesso real:
# pg_hba.conf (scram, faixa 172.16.0.0/12) + ufw (porta fechada pra internet).
listen_addresses = '*'
log_connections = on
```

- [ ] **Passo 4: Instalar e liberar**

```bash
sudo cp ~/dotfiles/vps/etc/postgresql/10-docker.conf /etc/postgresql/18/main/conf.d/
echo "host    all             all             172.16.0.0/12           scram-sha-256" | \
  sudo tee -a /etc/postgresql/18/main/pg_hba.conf
sudo ufw allow from 172.16.0.0/12 to any port 5432 proto tcp comment 'postgres p/ containers'
sudo systemctl restart postgresql@18-main
```

A faixa é `/12` e não a subnet da rede `apps` porque o Docker aplica MASQUERADE quando o
container fala com um IP do próprio host — o `pg_hba` veria um endereço diferente do
esperado.

- [ ] **Passo 5: Verificar que agora conecta**

```bash
docker run --rm --network apps --add-host host.docker.internal:host-gateway \
  postgres:18-alpine \
  psql "postgresql://turmasunb:<senha>@host.docker.internal:5432/turmasunb" -c 'select 1'
```
Esperado: `1`. A senha está em `/srv/turmasunb/.env`.

- [ ] **Passo 6: Conferir o IP de origem que o Postgres enxergou**

```bash
sudo journalctl -u postgresql@18-main --since '2 min ago' | grep 'connection authorized' | tail -3
```
Esperado: a conexão aparece com IP dentro de `172.16.0.0/12`. Se aparecer outro endereço,
ajuste o `pg_hba` para o que foi observado antes de seguir.

- [ ] **Passo 7: Confirmar que a 5432 segue fechada para fora**

```bash
sudo ufw status | grep 5432
```
Esperado: só a regra de `172.16.0.0/12`. Nenhum `Anywhere`.

- [ ] **Passo 8: Commit**

```bash
cd ~/dotfiles
git add vps/etc/postgresql/
git commit -m "add: config do postgres para aceitar conexao das redes docker"
git push
```

**Rollback:** remover o `10-docker.conf`, apagar a linha do `pg_hba`,
`sudo ufw delete allow from 172.16.0.0/12 to any port 5432 proto tcp`, reiniciar.

---

## Task 8: turmasunb em container

Primeira app com Build de verdade. Repo público, então não depende do provider da Task 3.
É a única app com estado em disco.

**Arquivos:**
- Criar: `Dockerfile` no repo `MateusLG/turmasunb`
- Criar: `vps/stacks/turmasunb/compose.yaml`
- Modificar: `vps/stacks/traefik/dynamic/legacy.yml` (remover a entrada `legacy-turmasunb`)

**Interfaces:**
- Consome: Builder `srv1` (Task 3), Postgres via rede (Task 7), `cf-aop@file` (Task 4).
- Produz: imagem `turmasunb:latest`; volume `turmasunb-backups` montado em `/app/backups`.

- [ ] **Passo 1: Escrever o `Dockerfile` no repo do turmasunb**

Python 3.12 é a versão do `.python-version` e do venv atual.

```dockerfile
FROM python:3.12-slim
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    PYTHONUNBUFFERED=1 \
    PATH="/app/.venv/bin:$PATH"

WORKDIR /app

COPY requirements.txt ./
RUN uv venv && uv pip install -r requirements.txt

COPY . .

RUN useradd -u 10001 app && mkdir -p /app/backups && chown -R 10001:10001 /app
USER 10001

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

- [ ] **Passo 2: Testar o build localmente antes de envolver o Komodo**

```bash
cd /tmp && git clone https://github.com/MateusLG/turmasunb.git turmasunb-build
cd turmasunb-build && docker build -t turmasunb:test .
docker run --rm turmasunb:test python -c "import main; print('import ok')"
```
Esperado: `import ok`. Se falhar aqui, o problema é o Dockerfile, não o Komodo.

- [ ] **Passo 3: Commit no repo do turmasunb**

```bash
git add Dockerfile && git commit -m "add: dockerfile" && git push
```

- [ ] **Passo 4: Criar a Build no Komodo**

UI → Builds → New → nome `turmasunb`, repo `MateusLG/turmasunb`, branch `main`,
builder `srv1`, sem registry (imagem fica local). Rodar. Conferir o log até `Success`.

- [ ] **Passo 5: Registrar os segredos como Variables**

UI → Settings → Variables. Criar, com os valores de `/srv/turmasunb/.env`:
`TURMASUNB_DATABASE_URL` (trocando o host por `host.docker.internal`), `TURMASUNB_SEMESTER`,
`TURMASUNB_BACKUP_TOKEN`. Marcar `DATABASE_URL` e `BACKUP_TOKEN` como secret.

- [ ] **Passo 6: Escrever `vps/stacks/turmasunb/compose.yaml`**

Sem `read_only`: esta app grava backups. `BACKUP_PATH` aponta para o volume.

```yaml
services:
  turmasunb:
    image: turmasunb:latest
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    environment:
      DATABASE_URL: ${TURMASUNB_DATABASE_URL}
      SEMESTER: ${TURMASUNB_SEMESTER}
      BACKUP_TOKEN: ${TURMASUNB_BACKUP_TOKEN}
      BACKUP_PATH: /app/backups
      BACKUP_INTERVAL_HOURS: 24
      BACKUP_MAX_FILES: 14
    volumes:
      - turmasunb-backups:/app/backups
    extra_hosts:
      - "host.docker.internal:host-gateway"
    networks:
      - edge
      - apps
    labels:
      - traefik.enable=true
      - traefik.docker.network=edge
      - traefik.http.routers.turmasunb.rule=Host(`turmasunb.com`) || Host(`www.turmasunb.com`)
      - traefik.http.routers.turmasunb.entrypoints=websecure
      - traefik.http.routers.turmasunb.tls.options=cf-aop@file
      - traefik.http.services.turmasunb.loadbalancer.server.port=8000

volumes:
  turmasunb-backups:

networks:
  edge:
    external: true
  apps:
    external: true
```

- [ ] **Passo 7: Remover a rota legada e publicar**

Apagar de `vps/stacks/traefik/dynamic/legacy.yml` o router `legacy-turmasunb` e o service
`legacy-turmasunb`.

```bash
cd ~/dotfiles
git add vps/stacks/turmasunb/ vps/stacks/traefik/dynamic/legacy.yml
git commit -m "add: stack do turmasunb em container"
git push
```

- [ ] **Passo 8: Corte da app**

```bash
sudo systemctl stop turmasunb
```
Em seguida, na UI: criar a Stack `turmasunb` (Git Repo, run directory
`vps/stacks/turmasunb`) e dar Deploy. Depois, Redeploy na Stack `traefik` para recarregar
o `legacy.yml`.

- [ ] **Passo 9: Copiar os backups antigos para o volume**

Depois do deploy, porque é o Compose quem cria o volume:

```bash
VOL=$(docker volume ls -q | grep turmasunb-backups)
sudo cp /srv/turmasunb/backups/*.json "/var/lib/docker/volumes/$VOL/_data/"
docker exec $(docker ps -qf name=turmasunb) ls /app/backups | tail -3
```
Esperado: os arquivos aparecem dentro do container.

- [ ] **Passo 10: Verificar**

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://turmasunb.com/
docker logs $(docker ps -qf name=turmasunb) 2>&1 | tail -20
```
Esperado: `200` e log sem erro de conexão com o banco. Abrir o site e conferir que as
turmas aparecem — é o que prova que o Postgres respondeu.

- [ ] **Passo 11: Desabilitar a unit**

```bash
sudo systemctl disable turmasunb
```
Não apague nada de `/srv/turmasunb` — é o rollback até a Task 15.

- [ ] **Passo 12: Commit final**

```bash
cd ~/dotfiles && git commit --allow-empty -m "chore: turmasunb migrado para container" && git push
```

**Rollback:** restaurar a entrada no `legacy.yml`, push, redeploy do traefik,
`sudo systemctl start turmasunb`, destruir a Stack.

---

## Task 9: album-copa em container

Já tem Dockerfile (herança do Railway). Primeira app de repo privado — usa o provider da
Task 3.

**Arquivos:**
- Modificar: `Dockerfile` no repo `MateusLG/album-copa`
- Criar: `vps/stacks/albumcopa/compose.yaml`
- Modificar: `vps/stacks/traefik/dynamic/legacy.yml`

**Interfaces:**
- Consome: provider `github.com` (Task 3), Postgres via rede (Task 7).
- Produz: imagem `albumcopa:latest`.

- [ ] **Passo 1: Ajustar o Dockerfile existente**

Duas mudanças no arquivo atual: fixar a porta (o `${PORT:-8000}` é resquício do Railway)
e não rodar como root. Substituir o `CMD` final por:

```dockerfile
RUN useradd -u 10001 app && chown -R 10001:10001 /app
USER 10001

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8001"]
```

- [ ] **Passo 2: Testar o build**

```bash
cd /tmp && git clone git@github.com:MateusLG/album-copa.git albumcopa-build
cd albumcopa-build && docker build -t albumcopa:test .
```
Esperado: build completa. O estágio do Vite é o mais lento; se der OOM, pare e reavalie
(2 vCPU, ~1.5G livres depois do Komodo).

- [ ] **Passo 3: Commit no repo do album-copa**

```bash
git add Dockerfile && git commit -m "fix: porta fixa e usuario nao-root no container" && git push
```

- [ ] **Passo 4: Build no Komodo**

Builds → New → nome `albumcopa`, repo `MateusLG/album-copa`, provider `github.com` com a
conta `MateusLG`, builder `srv1`. Rodar até `Success`.

- [ ] **Passo 5: Variable do banco**

Criar `ALBUMCOPA_DATABASE_URL` (secret) com o valor de `/srv/albumcopa/backend/.env`,
trocando o host por `host.docker.internal`.

- [ ] **Passo 6: Escrever `vps/stacks/albumcopa/compose.yaml`**

```yaml
services:
  albumcopa:
    image: albumcopa:latest
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    read_only: true
    tmpfs:
      - /tmp
    environment:
      DATABASE_URL: ${ALBUMCOPA_DATABASE_URL}
    extra_hosts:
      - "host.docker.internal:host-gateway"
    networks:
      - edge
      - apps
    labels:
      - traefik.enable=true
      - traefik.docker.network=edge
      - traefik.http.routers.albumcopa.rule=Host(`album.lgmateus.com`)
      - traefik.http.routers.albumcopa.entrypoints=websecure
      - traefik.http.routers.albumcopa.tls.options=cf-aop@file
      - traefik.http.services.albumcopa.loadbalancer.server.port=8001

networks:
  edge:
    external: true
  apps:
    external: true
```

- [ ] **Passo 7: Remover a rota legada, commit e push**

Apagar `legacy-albumcopa` (router e service) de `legacy.yml`.

```bash
cd ~/dotfiles
git add vps/stacks/albumcopa/ vps/stacks/traefik/dynamic/legacy.yml
git commit -m "add: stack do album-copa em container"
git push
```

- [ ] **Passo 8: Corte**

```bash
sudo systemctl stop albumcopa
```
UI: criar Stack `albumcopa` (run directory `vps/stacks/albumcopa`), Deploy; Redeploy do
`traefik`.

- [ ] **Passo 9: Verificar**

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://album.lgmateus.com/
curl -s -o /dev/null -w '%{http_code}\n' https://album.lgmateus.com/api/colecao \
  -H 'X-Username: teste'
```
Esperado: `200` no primeiro. O segundo prova que a API alcançou o banco — qualquer
resposta que não seja erro 5xx serve; ajuste o path se a rota tiver outro nome.

- [ ] **Passo 10: Desabilitar a unit e fechar**

```bash
sudo systemctl disable albumcopa
```

**Rollback:** igual à Task 8.

---

## Task 10: lgmateus em container

A única que exige mudança de configuração no código da app.

**Arquivos:**
- Modificar: `next.config.ts` no repo `MateusLG/lgmateus.com`
- Criar: `Dockerfile` no mesmo repo
- Criar: `vps/stacks/lgmateus/compose.yaml`
- Modificar: `vps/stacks/traefik/dynamic/legacy.yml`

**Interfaces:**
- Consome: provider `github.com` (Task 3).
- Produz: imagem `lgmateus:latest`.

- [ ] **Passo 1: Ligar o output standalone**

Em `next.config.ts`, o objeto de config está vazio hoje. Trocar por:

```ts
const nextConfig: NextConfig = {
  output: "standalone",
};
```

Sem isso a imagem carrega `node_modules` inteiro.

- [ ] **Passo 2: Escrever o `Dockerfile`**

Node 24 é o que o mise do user `lgmateus` usa hoje (24.19.0).

```dockerfile
FROM node:24-slim AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

FROM node:24-slim AS build
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm run build

FROM node:24-slim AS runtime
WORKDIR /app
ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    PORT=3000 \
    HOSTNAME=0.0.0.0

COPY --from=build /app/.next/standalone ./
COPY --from=build /app/.next/static ./.next/static
COPY --from=build /app/public ./public

USER node
EXPOSE 3000
CMD ["node", "server.js"]
```

- [ ] **Passo 3: Testar o build**

```bash
cd /tmp && git clone git@github.com:MateusLG/lgmateus.com.git lgmateus-build
cd lgmateus-build && docker build -t lgmateus:test .
docker run --rm -d --name lgm-test -p 127.0.0.1:3999:3000 lgmateus:test
sleep 5 && curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3999/
docker rm -f lgm-test
```
Esperado: `200`. É o build mais pesado dos cinco — acompanhe a RAM com `free -h` em outro
terminal.

- [ ] **Passo 4: Commit no repo do lgmateus**

```bash
git add next.config.ts Dockerfile
git commit -m "add: dockerfile e output standalone para deploy em container"
git push
```

- [ ] **Passo 5: Build no Komodo**

Nome `lgmateus`, repo `MateusLG/lgmateus.com`, provider `github.com`, builder `srv1`.

- [ ] **Passo 6: Escrever `vps/stacks/lgmateus/compose.yaml`**

O `tmpfs` em `.next/cache` não é opcional: a app usa `next/image` em dois componentes e a
otimização de imagem escreve em runtime — com `read_only` e sem tmpfs, ela quebra ao
servir a primeira imagem.

```yaml
services:
  lgmateus:
    image: lgmateus:latest
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    read_only: true
    tmpfs:
      - /tmp
      - /app/.next/cache
    environment:
      NODE_ENV: production
    networks:
      - edge
    labels:
      - traefik.enable=true
      - traefik.docker.network=edge
      - traefik.http.routers.lgmateus.rule=Host(`lgmateus.com`) || Host(`www.lgmateus.com`)
      - traefik.http.routers.lgmateus.entrypoints=websecure
      - traefik.http.routers.lgmateus.tls.options=cf-aop@file
      - traefik.http.services.lgmateus.loadbalancer.server.port=3000

networks:
  edge:
    external: true
```

- [ ] **Passo 7: Remover a rota legada, commit e push**

```bash
cd ~/dotfiles
git add vps/stacks/lgmateus/ vps/stacks/traefik/dynamic/legacy.yml
git commit -m "add: stack do lgmateus em container"
git push
```

- [ ] **Passo 8: Corte**

```bash
sudo systemctl stop lgmateus
```
UI: criar Stack `lgmateus`, Deploy; Redeploy do `traefik`.

- [ ] **Passo 9: Verificar, inclusive imagem**

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://lgmateus.com/
curl -s -o /dev/null -w '%{http_code}\n' 'https://lgmateus.com/_next/image?url=%2Ffavicon.ico&w=64&q=75'
```
Esperado: `200` nos dois. O segundo é o teste do tmpfs — se der `500`, o cache não está
gravável.

Conferir também que a troca de idioma (next-intl) funciona, já que o `proxy.ts` roda em
standalone.

- [ ] **Passo 10: Desabilitar a unit**

```bash
sudo systemctl disable lgmateus
```

**Rollback:** igual à Task 8.

---

## Task 11: os48/gestao em container

Por último entre as apps porque é a que tem cliente validando dado. Repo em org
(`KodiumAI`), e o único que ainda dependia do `gh` do `mateus` — aqui essa exceção morre.

**Arquivos:**
- Criar: `Dockerfile` no repo `KodiumAI/OS0048-Modulo-Gestao-CREA`
- Criar: `vps/stacks/gestao/compose.yaml`
- Modificar: `vps/stacks/traefik/dynamic/legacy.yml`

**Interfaces:**
- Consome: provider `github.com` (Task 3), Postgres via rede (Task 7).
- Produz: imagem `gestao:latest`.

- [ ] **Passo 1: Escrever o `Dockerfile` na raiz do repo**

O backend serve o build do Vite. Python 3.12 (venv atual), deps com `uv sync --frozen`
(o repo tem `uv.lock`). Ajuste os caminhos se a estrutura do repo divergir de
`gestao/backend` e `gestao/frontend`.

```dockerfile
FROM node:24-slim AS frontend
WORKDIR /app/frontend
COPY gestao/frontend/package.json gestao/frontend/package-lock.json ./
RUN npm ci
COPY gestao/frontend/ ./
RUN npm run build

FROM python:3.12-slim AS runtime
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    PYTHONUNBUFFERED=1 \
    PATH="/app/backend/.venv/bin:$PATH"

WORKDIR /app/backend

COPY gestao/backend/pyproject.toml gestao/backend/uv.lock ./
RUN uv sync --frozen --no-dev

COPY gestao/backend/ ./
COPY --from=frontend /app/frontend/dist /app/frontend/dist

RUN useradd -u 10001 app && chown -R 10001:10001 /app
USER 10001

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8002"]
```

- [ ] **Passo 2: Testar o build**

```bash
cd /tmp && git clone git@github.com:KodiumAI/OS0048-Modulo-Gestao-CREA.git gestao-build
cd gestao-build && docker build -t gestao:test .
```

- [ ] **Passo 3: Commit no repo do os48**

```bash
git add Dockerfile && git commit -m "add: dockerfile para deploy em container" && git push
```

- [ ] **Passo 4: Build no Komodo**

Nome `gestao`, repo `KodiumAI/OS0048-Modulo-Gestao-CREA`, provider `github.com`,
builder `srv1`. O PAT da Task 3 precisa ter acesso a esse repo da org — se der 403, é aí.

- [ ] **Passo 5: Migrar as 19 variáveis para Variables do Komodo**

```bash
sudo cat /srv/gestao/repo/gestao/backend/.env
```

Criar uma Variable por linha, prefixadas com `GESTAO_`. Marcar como **secret**:
`SESSION_SECRET`, `SSO_SHARED_SECRET`, `COBLI_API_KEY`, `COBLI_WEBHOOK_SECRET`,
`TRACKING_JOB_TOKEN`, `COBLI_SYNC_TOKEN`, `DATABASE_URL`.
No `DATABASE_URL`, trocar o host por `host.docker.internal`.

- [ ] **Passo 6: Escrever `vps/stacks/gestao/compose.yaml`**

Repetir todas as variáveis — a app lê cada uma delas, e omitir uma só aparece como bug
em runtime.

```yaml
services:
  gestao:
    image: gestao:latest
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    read_only: true
    tmpfs:
      - /tmp
    environment:
      ENV: ${GESTAO_ENV}
      DATABASE_URL: ${GESTAO_DATABASE_URL}
      SSO_SHARED_SECRET: ${GESTAO_SSO_SHARED_SECRET}
      SESSION_SECRET: ${GESTAO_SESSION_SECRET}
      SSO_TOKEN_MAX_AGE_SECONDS: ${GESTAO_SSO_TOKEN_MAX_AGE_SECONDS}
      SESSION_TTL_HOURS: ${GESTAO_SESSION_TTL_HOURS}
      COOKIE_NAME: ${GESTAO_COOKIE_NAME}
      COOKIE_DOMAIN: ${GESTAO_COOKIE_DOMAIN}
      COOKIE_SECURE: ${GESTAO_COOKIE_SECURE}
      POST_SSO_REDIRECT: ${GESTAO_POST_SSO_REDIRECT}
      DEV_FRONTEND_ORIGIN: ${GESTAO_DEV_FRONTEND_ORIGIN}
      TRACKING_UI_ATIVO: ${GESTAO_TRACKING_UI_ATIVO}
      TRACKING_PERMISSIONS_BY_PROFILE: ${GESTAO_TRACKING_PERMISSIONS_BY_PROFILE}
      TRACKING_ATIVO: ${GESTAO_TRACKING_ATIVO}
      COBLI_ATIVO: ${GESTAO_COBLI_ATIVO}
      COBLI_API_KEY: ${GESTAO_COBLI_API_KEY}
      COBLI_WEBHOOK_ATIVO: ${GESTAO_COBLI_WEBHOOK_ATIVO}
      COBLI_WEBHOOK_SECRET: ${GESTAO_COBLI_WEBHOOK_SECRET}
      TRACKING_JOB_TOKEN: ${GESTAO_TRACKING_JOB_TOKEN}
      COBLI_SYNC_TOKEN: ${GESTAO_COBLI_SYNC_TOKEN}
    extra_hosts:
      - "host.docker.internal:host-gateway"
    networks:
      - edge
      - apps
    labels:
      - traefik.enable=true
      - traefik.docker.network=edge
      - traefik.http.routers.gestao.rule=Host(`crea.lglabs.tech`)
      - traefik.http.routers.gestao.entrypoints=websecure
      - traefik.http.routers.gestao.tls.options=cf-aop-optional@file
      - traefik.http.services.gestao.loadbalancer.server.port=8002

networks:
  edge:
    external: true
  apps:
    external: true
```

- [ ] **Passo 7: Remover a rota legada, commit e push**

Com isso o `legacy.yml` fica sem nenhum router — deixe o arquivo com a estrutura vazia
`http: {}` até a Task 15.

```bash
cd ~/dotfiles
git add vps/stacks/gestao/ vps/stacks/traefik/dynamic/legacy.yml
git commit -m "add: stack do os48 em container"
git push
```

- [ ] **Passo 8: Corte**

```bash
sudo systemctl stop gestao
```
UI: criar Stack `gestao`, Deploy; Redeploy do `traefik`.

- [ ] **Passo 9: Verificar, com atenção ao SSO e ao upload**

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://crea.lglabs.tech/
docker logs $(docker ps -qf name=gestao) 2>&1 | tail -30
```

Depois, no navegador: entrar pelo fluxo de SSO, abrir a aba Documentos, **baixar** um
documento existente e **subir** um novo (o conteúdo vai para coluna binária no banco, não
para disco — é o teste de que nada dependia do filesystem). Confira também que o limite
de 25MB some: um arquivo maior que isso agora passa, onde antes o nginx recusava.

- [ ] **Passo 10: Desabilitar a unit**

```bash
sudo systemctl disable gestao
```

**Rollback:** restaurar a entrada no `legacy.yml`, push, redeploy do traefik,
`sudo systemctl start gestao`, destruir a Stack. O `/srv/gestao` está intacto.

---

## Task 12: ericsongomes com Build próprio

Fecha o provisório da Task 5: o container passa a carregar o próprio build, e o
`deploy ericsongomes` deixa de ser necessário.

**Arquivos:**
- Criar: `Dockerfile` e `nginx.conf` no repo `MateusLG/site-ericson`
- Modificar: `vps/stacks/ericsongomes/compose.yaml` (remove o bind-mount de `/var/www`)
- Remover: `vps/stacks/ericsongomes/nginx.conf` (passa a viver no repo da app)

**Interfaces:**
- Consome: provider `github.com` (Task 3).
- Produz: imagem `ericsongomes:latest`, sem dependência de `/var/www`.

- [ ] **Passo 1: Conferir como o site é buildado hoje**

```bash
grep -A15 'ericsongomes' ~/dotfiles/vps/bin/deploy.sh
```
São dois builds (site e calculadora) com rsync para `/var/www/ericsongomes/{site,calculadora}`.
O Dockerfile precisa reproduzir exatamente esses dois destinos.

- [ ] **Passo 2: Escrever o `Dockerfile` no repo do site**

Ajuste os caminhos conforme a estrutura real do repo, confirmada no passo 1.

```dockerfile
FROM node:24-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginxinc/nginx-unprivileged:alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/out /srv/www/site
COPY --from=build /app/calculadora/out /srv/www/calculadora
EXPOSE 8080
```

- [ ] **Passo 3: Mover o `nginx.conf` para o repo do site**

Copiar o arquivo criado na Task 5 (`vps/stacks/ericsongomes/nginx.conf`) para a raiz do
repo `site-ericson`, sem alterações — os caminhos `/srv/www/...` já batem.

- [ ] **Passo 4: Testar o build**

```bash
cd /tmp && git clone git@github.com:MateusLG/site-ericson.git ericson-build
cd ericson-build && docker build -t ericsongomes:test .
docker run --rm -d --name eric-test -p 127.0.0.1:3998:8080 ericsongomes:test
sleep 3
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3998/
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3998/calculadora/
docker rm -f eric-test
```
Esperado: `200` nos dois.

- [ ] **Passo 5: Build no Komodo e atualização da Stack**

Criar a Build `ericsongomes`. Depois, em `vps/stacks/ericsongomes/compose.yaml`: trocar
`image: nginxinc/nginx-unprivileged:alpine` por `image: ericsongomes:latest` e remover os
dois volumes (o `nginx.conf` e o `/var/www`), mantendo os tmpfs.

- [ ] **Passo 6: Commit, push e redeploy**

```bash
cd ~/dotfiles
git rm vps/stacks/ericsongomes/nginx.conf
git add vps/stacks/ericsongomes/compose.yaml
git commit -m "update: ericsongomes passa a usar imagem propria"
git push
```
UI: Redeploy da Stack `ericsongomes`.

- [ ] **Passo 7: Verificar**

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://ericsongomes.com.br/
curl -s -o /dev/null -w '%{http_code}\n' https://ericsongomes.com.br/calculadora/
curl -s -o /dev/null -w '%{http_code}\n' https://www.ericsongomes.com.br/
```
Esperado: `200`, `200`, e `301` no www (o middleware de redirect).

---

## Task 13: rustdesk adotado como Stack

Não muda nada no funcionamento — só passa a ser gerenciado pelo Komodo em vez de compose
solto na home.

**Arquivos:**
- Criar: `vps/stacks/rustdesk/compose.yaml` (cópia de `~/rustdesk/docker-compose.yml`)

**Interfaces:**
- Consome: Komodo (Task 2).
- Produz: Stack `rustdesk` visível e gerenciável na UI.

- [ ] **Passo 1: Copiar o compose atual**

```bash
mkdir -p ~/dotfiles/vps/stacks/rustdesk
cp ~/rustdesk/docker-compose.yml ~/dotfiles/vps/stacks/rustdesk/compose.yaml
```

Não mexer no `network_mode: host` nem no `-r srv1.lgmateus.com:21117`: o rustdesk precisa
de host network por causa de NAT/UDP, e o hostname já foi corrigido em agosto.

- [ ] **Passo 2: Ajustar o caminho do volume**

O compose usa `./data`, relativo a `~/rustdesk`. Trocar por caminho absoluto, já que o
Komodo vai rodar de outro diretório:

```yaml
    volumes:
      - /home/mateus/rustdesk/data:/root
```

- [ ] **Passo 3: Commit e push**

```bash
cd ~/dotfiles
git add vps/stacks/rustdesk/
git commit -m "add: stack do rustdesk versionada"
git push
```

- [ ] **Passo 4: Adotar sem derrubar a sessão**

```bash
cd ~/rustdesk && docker compose down
```
UI: criar Stack `rustdesk` (run directory `vps/stacks/rustdesk`), Deploy.

- [ ] **Passo 5: Verificar**

```bash
docker ps --filter name=hbb --format '{{.Names}} {{.Status}}'
sudo ss -tulpn | grep -E '2111[5-9]'
```
Esperado: `hbbs` e `hbbr` no ar, portas 21115-21119 escutando. Testar uma conexão real
pelo cliente RustDesk.

---

## Task 14: Resource Sync — a configuração do Komodo em TOML versionado

Sem isso, quem sabe a configuração das Builds e Stacks é o Mongo, e o backup dele vira
ponto único de falha.

**Arquivos:**
- Criar: `vps/komodo-sync/resources.toml`

**Interfaces:**
- Consome: todos os recursos criados nas Tasks 3-13.
- Produz: representação declarativa de Servers, Builders, Builds e Stacks no git.

- [ ] **Passo 1: Exportar o que já existe**

UI → Settings → Export, ou o botão de export na tela de Resource Sync. Salvar o TOML
gerado em `~/dotfiles/vps/komodo-sync/resources.toml`.

- [ ] **Passo 2: Conferir que não vazou segredo**

```bash
grep -iE 'password|secret|token|api_key|DATABASE_URL' ~/dotfiles/vps/komodo-sync/resources.toml
```
Esperado: nenhuma saída, ou só referências a Variables (`[[variable]]` sem o valor).
**Se aparecer valor de segredo, não commite** — remova antes.

- [ ] **Passo 3: Criar o Resource Sync**

UI → Syncs → New → modo Git Repo, repo `MateusLG/dotfiles`, resource path
`vps/komodo-sync/resources.toml`. Rodar em modo de execução seca primeiro e conferir que
o diff apresentado é vazio — diff vazio significa que o TOML descreve fielmente o que está
rodando.

- [ ] **Passo 4: Commit e push**

```bash
cd ~/dotfiles
git add vps/komodo-sync/
git commit -m "add: resource sync do komodo em toml"
git push
```

---

## Task 15: Limpeza e documentação

Só depois que as 5 apps estiverem verdes em container por pelo menos alguns dias.

**Arquivos:**
- Remover: `vps/bin/deploy.sh`, `vps/etc/nginx/`, `vps/etc/systemd/` (units das apps),
  `vps/stacks/traefik/dynamic/legacy.yml`
- Modificar: `vps/apps.md`, `vps/README.md`

**Interfaces:**
- Consome: Tasks 5-13 concluídas e estáveis.

- [ ] **Passo 1: Confirmar que nenhuma unit de app está ativa**

```bash
systemctl list-units --type=service --state=running --no-legend | \
  grep -E 'lgmateus|turmasunb|albumcopa|gestao|nginx'
```
Esperado: nenhuma saída.

- [ ] **Passo 2: Remover as units e o nginx**

```bash
sudo systemctl disable --now nginx
for u in lgmateus turmasunb albumcopa gestao; do
  sudo rm -f /etc/systemd/system/$u.service
  sudo rm -rf /etc/systemd/system/$u.service.d
done
sudo systemctl daemon-reload
sudo apt-get purge -y nginx nginx-common
```

- [ ] **Passo 3: Remover o `legacy.yml`**

```bash
cd ~/dotfiles && git rm vps/stacks/traefik/dynamic/legacy.yml
```

- [ ] **Passo 4: Limpar o resto**

```bash
sudo rm -rf /srv/plataforma
sudo systemctl disable --now certbot.timer
cd ~/dotfiles && git rm -r vps/bin/deploy.sh vps/etc/nginx vps/etc/systemd
```

Os diretórios `/srv/<app>` e os users de sistema podem ficar mais um tempo — são o último
rollback possível. Remova só quando tiver certeza.

- [ ] **Passo 5: Reescrever `vps/apps.md`**

Atualizar a tabela (coluna "Serviço" vira "Stack"), trocar a seção de fluxo de requisição
pelo diagrama novo, substituir a seção de deploy pelo fluxo do Komodo e remover a seção
de deploy keys — que deixou de existir.

- [ ] **Passo 6: Atualizar `vps/README.md`**

Trocar as referências a nginx e `deploy.sh` pelo Komodo e Traefik. Documentar como
acessar a UI, onde vive o `compose.env` e como fazer rollback de uma stack.

- [ ] **Passo 7: Endurecer o mTLS do crea**

Pendência aberta desde a Task 4. Cloudflare → zona `lglabs.tech` → SSL/TLS → Origin
Server → ligar **Authenticated Origin Pulls**. Depois, em
`vps/stacks/gestao/compose.yaml`, trocar `cf-aop-optional@file` por `cf-aop@file`, commit,
push e redeploy da stack.

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://crea.lglabs.tech/
curl -sv --resolve crea.lglabs.tech:443:127.0.0.1 https://crea.lglabs.tech/ 2>&1 | \
  grep -iE 'certificate required|alert'
```
Esperado: `200` pela Cloudflare, e recusa no acesso direto à origem.

- [ ] **Passo 8: Verificação final**

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}'
for h in lgmateus.com turmasunb.com album.lgmateus.com crea.lglabs.tech ericsongomes.com.br; do
  printf '%s -> %s\n' "$h" "$(curl -s -o /dev/null -w '%{http_code}' https://$h/)"
done
free -h && df -h /
```
Esperado: todos os containers `Up`, `200` nos cinco domínios, e memória/disco em nível
comparável ao anterior à migração.

- [ ] **Passo 9: Commit final**

```bash
cd ~/dotfiles
git add -A vps/
git commit -m "chore: remove nginx, deploy.sh e units apos migracao para komodo"
git push
```

---

## Ordem e pontos de parada

Tasks 1-3 não tocam produção. A Task 6 é o único momento de indisponibilidade planejada.
As Tasks 8-11 são independentes entre si: se uma der problema, faça rollback só dela e
siga para a próxima.

Pare e reavalie se: a memória disponível cair abaixo de 1G, um build der OOM, ou o
handshake mTLS falhar para tráfego vindo da Cloudflare (e não só para teste local).
