# Migração para Komodo + Traefik

**Data:** 2026-08-23
**Status:** design aprovado, não implementado
**Escopo:** as 5 aplicações web da VPS passam a rodar em containers Docker,
gerenciadas pelo Komodo, com Traefik substituindo o nginx como proxy reverso.

---

## 1. Objetivo e motivação

Hoje cada app roda como serviço systemd nativo, com user de sistema dedicado, build
feito na própria VPS por `bin/deploy.sh` e nginx publicando tudo. Funciona, mas cada
app tem seu próprio jeito de subir (venv do uv, mise do user, npm), e não existe
visibilidade centralizada de estado, logs ou deploy.

A migração unifica: toda app vira imagem Docker, todo deploy passa pelo Komodo, todo
roteamento HTTP passa pelo Traefik.

## 2. Decisões

| Decisão | Escolha | Por quê |
|---|---|---|
| Gerenciador | **Komodo v2** (v2.3.2, ago/2026) | Build + deploy + monitoramento num só lugar; config declarativa em TOML versionável |
| Escopo | **Só as 5 apps web** | Postgres e minecraft ficam nativos; migrá-los junto multiplicaria os pontos de falha |
| Build das imagens | **Na VPS, via Komodo Build** | O `deploy.sh` já builda aqui hoje; evita montar CI em 5 repos e credencial de registry |
| Proxy reverso | **Traefik v3.7** | Roteamento por label, config dinâmica sem reload |
| TLS | **Origin Certs da Cloudflare (existentes) + AOP** | Paridade com hoje; com proxy laranja + Full strict não há motivo pra ACME |
| Acesso à UI do Komodo | **Subdomínio atrás do Cloudflare Access** | A UI controla o socket do Docker; auth do Komodo sozinha não basta |
| Onde mora a config | **`dotfiles/vps/` (repo público)** | Consistente com `etc/nginx` e `etc/systemd`, que já estão lá. Segredos ficam nas Variables do Komodo, nunca no arquivo |
| Ordem de execução | **Traefik primeiro, apps depois** | A troca da borda é a parte arriscada; isolá-la permite validar antes de mexer nas apps |

## 3. Estado atual (baseline)

| App | Stack | Serviço | Porta | Domínio | Estado em disco |
|---|---|---|---|---|---|
| lgmateus | Next.js 16 + next-intl | `lgmateus.service` | 3000 | lgmateus.com | nenhum |
| turmasunb | FastAPI | `turmasunb.service` | 8000 | turmasunb.com | **`backups/*.json`** |
| album-copa | FastAPI + Vite | `albumcopa.service` | 8001 | album.lgmateus.com | nenhum |
| os48/gestao | FastAPI + Vite | `gestao.service` | 8002 | crea.lglabs.tech | nenhum |
| ericsongomes | Next static export | nginx (`/var/www`) | — | ericsongomes.com.br | nenhum |

Fora do escopo, permanecem como estão: Postgres 18 (apt, loopback, 4 bancos + backup
diário por timer), `minecraft.service` (Fabric, heap 3G, `MemoryMax=4600M`) e o
rustdesk (já em Docker com `network_mode: host`).

Borda hoje: Cloudflare (proxy laranja, Full strict) → ufw libera 80/443 só das faixas
da CF → nginx com Origin Certs em `/etc/ssl/cloudflare` e Authenticated Origin Pulls
(`ssl_verify_client on`; `optional` só em `crea.lglabs.tech`) → `127.0.0.1:porta`.

Achados relevantes do levantamento:

- **Nenhuma app guarda estado em disco, exceto o turmasunb.** Os documentos do os48
  (upload até 25MB) vão para coluna binária no banco (`documento.conteudo`), não para
  o filesystem — o container é stateless.
- O turmasunb grava backups periódicos de `links` em `BACKUP_PATH`
  (`BACKUP_INTERVAL_HOURS`, retenção `BACKUP_MAX_FILES`) → precisa de volume.
- Só o album-copa tem Dockerfile (multi-stage node 22 + python 3.14, herdado do Railway).
- Recursos: 2 vCPU, 7.8G RAM (**5.5G já em uso**, ~2.2G livres), 28G de disco livre.

## 4. Arquitetura alvo

```
Cloudflare (proxy laranja, Full strict, AOP)
   │  ufw: 80/443 só das faixas da CF
   ▼
traefik ──rede `edge`──┬── lgmateus      (container)
 :80 :443              ├── turmasunb     (container + volume de backups)
                       ├── albumcopa     (container)
                       ├── gestao/os48   (container)
                       ├── ericsongomes  (nginx:alpine com o export estático)
                       └── komodo-core   (:9120, atrás do Cloudflare Access)

komodo-periphery ── docker.sock ── gerencia todas as stacks
Postgres 18 nativo  ◄── containers via host-gateway (rede `apps`)
minecraft (systemd) · rustdesk (stack, network_mode host)  — não passam pelo Traefik
```

## 5. Componentes

### 5.1 Komodo

Compose oficial `mongo.compose.yaml` adaptado: Mongo (com `--wiredTigerCacheSizeGB 0.25`),
Core e Periphery. Vive em `/etc/komodo` (o `PERIPHERY_ROOT_DIRECTORY` — todo compose e
repo precisa ser filho desse diretório para o Periphery enxergar).

Adaptações em relação ao arquivo oficial:

- Core **não publica** `9120:9120` no host: entra na rede `edge` e é exposto pelo
  Traefik em `komodo.lgmateus.com` (coberto pelo cert wildcard `*.lgmateus.com` que já existe).
- `KOMODO_HOST=https://komodo.lgmateus.com` (usado em webhooks e links da UI).
- Backups datados do banco em `/etc/komodo/backups` (nativo do Komodo).
- `init: true` em Core e Periphery é obrigatório na v2.

Autenticação Core↔Periphery é PKI Ed25519 com onboarding key, gerada na UI; após a
primeira conexão a chave não é mais necessária e a rotação é automática.

**Proteção da UI:** Cloudflare Access (Zero Trust) na frente, com política de e-mail
OTP. Configuração manual no dashboard da Cloudflare — não é versionável aqui.

### 5.2 Traefik

Static config (`vps/traefik/traefik.yml`):

```yaml
entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint: { to: websecure, scheme: https, permanent: true }
    forwardedHeaders:
      trustedIPs: &cf_ips [ <faixas IPv4 e IPv6 da Cloudflare> ]
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

`forwardedHeaders.trustedIPs` é o substituto do `bin/nginx-cloudflare-realip.sh`: sem
ele, todo log e rate-limit passa a enxergar o IP da Cloudflare em vez do visitante.
As faixas são as mesmas já usadas pelo `bin/ufw-cloudflare.sh`.

Dynamic config (`vps/traefik/dynamic/tls.yml`):

```yaml
tls:
  options:
    cf-aop:
      minVersion: VersionTLS12
      sniStrict: true
      clientAuth:
        caFiles: [ /certs/authenticated_origin_pull_ca.pem ]
        clientAuthType: RequireAndVerifyClientCert
    cf-aop-optional:          # só para crea.lglabs.tech, até ligar AOP na zona
      minVersion: VersionTLS12
      clientAuth:
        caFiles: [ /certs/authenticated_origin_pull_ca.pem ]
        clientAuthType: VerifyClientCertIfGiven
  certificates:
    - { certFile: /certs/lgmateus.crt,     keyFile: /certs/lgmateus.key }
    - { certFile: /certs/turmasunb.crt,    keyFile: /certs/turmasunb.key }
    - { certFile: /certs/lglabs.tech.crt,  keyFile: /certs/lglabs.tech.key }
    - { certFile: /certs/ericsongomes.crt, keyFile: /certs/ericsongomes.key }
```

`/etc/ssl/cloudflare` é montado read-only como `/certs`. As chaves continuam fora do
git (permissão `600`, root).

**Socket do Docker:** o Traefik é o processo exposto à internet, então não recebe o
socket direto — fica atrás de um `docker-socket-proxy` com apenas `CONTAINERS=1`. Isso
não elimina o risco global (o Periphery tem socket read-write), só o tira do componente
na linha de frente.

**Redirects preservados:** `www.lgmateus.com` → apex e `www.ericsongomes.com.br` → apex
viram middlewares `redirectregex`.

**Perda conhecida:** o `client_max_body_size 25m` do vhost do crea não tem equivalente
direto — o Traefik não limita body por padrão. Fica mais permissivo que hoje.

### 5.3 Stacks das apps

Cada app fica em **duas redes**: `edge` (só Traefik ↔ app, é onde o roteamento acontece)
e `apps` (saída para o Postgres do host). Quem não fala com banco — ericsongomes — fica
só na `edge`.

Padrão de labels (exemplo turmasunb):

```yaml
labels:
  - traefik.enable=true
  - traefik.http.routers.turmasunb.rule=Host(`turmasunb.com`)
  - traefik.http.routers.turmasunb.entrypoints=websecure
  - traefik.http.routers.turmasunb.tls.options=cf-aop@file
  - traefik.http.services.turmasunb.loadbalancer.server.port=8000
```

Endurecimento padrão em toda stack, compensando o sandbox systemd que se perde:

```yaml
security_opt: [ "no-new-privileges:true" ]
cap_drop: [ ALL ]
read_only: true          # onde a app não precisa escrever
tmpfs: [ /tmp ]
user: "10001:10001"      # não-root, definido no Dockerfile
```

Por app:

- **turmasunb** — python-slim + uv (`requirements.txt`). Volume nomeado para
  `BACKUP_PATH`. Não pode ser `read_only`. Continua carregando `data.json` em memória
  no boot: mexeu no banco, reinicia o container (mesmo comportamento de hoje).
- **album-copa** — Dockerfile existente serve; revisar o `CMD` com `${PORT:-8000}`
  (herança do Railway) e adicionar `USER` não-root.
- **lgmateus** — exige `output: "standalone"` no `next.config.ts` (**mudança no repo da
  app**, não aqui): sem isso a imagem carrega `node_modules` inteiro. Node 24, multi-stage
  deps → build → runner. O `proxy.ts` (middleware do Next 16) funciona normal em standalone.
  Usa `next/image` em dois componentes, e a otimização de imagem escreve em runtime → com
  `read_only`, precisa de `tmpfs: [/app/.next/cache]`, senão quebra ao servir imagem.
- **os48/gestao** — multi-stage: node builda o Vite, python 3.12 + uv roda o backend que
  serve o `dist`. As 19 variáveis do `.env` (incluindo `SESSION_SECRET`, `COBLI_API_KEY`,
  `SSO_SHARED_SECRET`) viram Secrets do Komodo; o `.env` sai do disco.
- **ericsongomes** — `nginx:alpine` com o export estático. As regras do vhost atual não
  somem, mudam de lugar (para um `nginx.conf` na imagem): redirect `/calculadora` →
  `/calculadora/`, `try_files` com `index.html`, cache imutável em `_next/static`, gzip.

### 5.4 Postgres

Permanece nativo. Hoje escuta só em `localhost` com `pg_hba` restrito a `127.0.0.1` —
container nenhum alcança. Mudanças mínimas:

1. `listen_addresses = '*'` em `conf.d/`. **Não** usar o IP da bridge: se o Postgres
   subir antes do `docker0` existir, ele falha ao dar bind. O controle de acesso fica no
   `pg_hba` e no ufw, não no bind.
2. `pg_hba.conf`: `host all all 172.16.0.0/12 scram-sha-256` — a faixa Docker inteira, e
   não a subnet da rede `apps`. Motivo: quando o container fala com um IP do próprio host,
   a regra de MASQUERADE do Docker reescreve o IP de origem para o da bridge de saída, e
   o `pg_hba` veria um endereço diferente do esperado. Autenticação continua sendo scram
   com senha; a faixa é privada e fechada no ufw.
3. `ufw allow from 172.16.0.0/12 to any port 5432 proto tcp` — a 5432 continua sem regra
   para a internet, ou seja, fechada.
4. **Verificar na implementação:** confirmar o IP de origem que o Postgres realmente
   enxerga (`log_connections = on` durante o teste) antes de fechar o `pg_hba`.
5. `DATABASE_URL` das apps aponta para `host.docker.internal`, com
   `extra_hosts: ["host.docker.internal:host-gateway"]` no compose.

O `bin/pg-backup.sh` e o timer continuam funcionando sem alteração.

## 6. Estrutura no dotfiles

```
vps/
├── komodo/compose.yaml + compose.env.example
├── stacks/traefik/{compose.yaml,traefik.yml,dynamic/}
├── stacks/{lgmateus,turmasunb,albumcopa,gestao,ericsongomes,rustdesk}/compose.yaml
├── komodo-sync/*.toml          # Resource Sync: Servers, Builds, Stacks declarativos
└── docs/2026-08-23-migracao-komodo-traefik{,-plano}.md
```

Cada compose fica no seu diretório junto com os arquivos que ele monta: o Komodo aponta
uma Stack para um `run_directory` do repo, e mounts relativos resolvem a partir dali.

`stacks/traefik/dynamic/legacy.yml` é temporário: existe só durante a fase 1, roteando para as
apps ainda em systemd. É esvaziado app a app na fase 2 e apagado no fim.

## 7. Fluxo de deploy

| Hoje | Depois |
|---|---|
| `deploy <app>` → git pull (deploy key do user) → build → `systemctl restart` → health check | Komodo **Build** (clona repo, `docker build`) + **Stack** (compose do dotfiles) → deploy por botão, webhook de push ou CLI |
| 4 deploy keys em `/srv/<app>/.ssh`; os48 usa o `gh` do `mateus` | Uma credencial git nas Variables do Komodo; o os48 sai da exceção |
| Segredos em `.env` no disco, `chmod 640` | Variables/Secrets do Komodo, injetados no container |

## 8. Segurança: o que muda

**Some:** o sandbox systemd (`ProtectHome`, `ProtectSystem=strict`, `NoNewPrivileges`,
`ReadWritePaths`, user de sistema sem sudo).

**Compensações:** `user:` não-root, `no-new-privileges`, `cap_drop: ALL`, `read_only` +
tmpfs, rede `edge` restrita a Traefik↔app. O isolamento de filesystem melhora: o
container não enxerga `/srv` nem `/home`.

**Regressão que não dá para compensar:** o Periphery tem `docker.sock` read-write, o que
é root-equivalente na máquina. Hoje um RCE numa app custa o user daquela app; depois, um
escape de container custa a VPS. É o preço de usar o Komodo — decisão consciente.

Mantidos sem alteração: ufw restrito às faixas da CF, AOP/mTLS na borda, fail2ban,
SSH só por chave.

## 9. Fases

Cada fase tem critério de aceite e rollback próprios. Nenhuma avança sem a anterior verde.

### Fase 0 — Komodo no ar
Sobe `komodo/compose.yaml` e conecta o servidor pelo onboarding key. O Traefik ainda não
existe, então o Core publica temporariamente em `127.0.0.1:9120` e o acesso é por túnel
SSH (`ssh -L 9120:localhost:9120 srv1`). O DNS e o Cloudflare Access entram na fase 1,
junto com o Traefik; o bind em localhost é removido nessa hora.
**Aceite:** UI acessível pelo túnel; servidor conectado com métricas de CPU/disco;
rustdesk visível como stack já existente.
**Rollback:** `docker compose down`. Produção não foi tocada.

### Fase 1 — Traefik assume a borda
Traefik sobe com `legacy.yml` roteando para as 4 apps que rodam em systemd via
`host.docker.internal`. nginx é **parado, não removido** (`systemctl disable --now nginx`).

O **ericsongomes tem que virar container nesta fase**, e não na seguinte: quem serve o
estático dele hoje é o próprio nginx, então desligar o nginx sem containerizar antes o
deixa sem servidor. É também a app de menor risco, o que a torna um bom primeiro teste do
padrão de Stack.

Entram junto: DNS `komodo.lgmateus.com` (A proxied), política do Cloudflare Access e a
remoção do bind em `127.0.0.1:9120` do Core.
**Aceite:** os 5 domínios das apps + `komodo.lgmateus.com` respondem por HTTPS; acesso
direto na origem continua recusado (AOP); `X-Forwarded-For` traz o IP real do visitante.
**Rollback:** `docker compose down traefik && systemctl start nginx` (< 1 min). O
ericsongomes volta a ser servido pelo vhost, que continua no disco.

### Fase 2 — Containerização, uma app por vez
As 4 restantes, em ordem de risco crescente: **turmasunb** → **album-copa** (Dockerfile
pronto) → **lgmateus** (precisa do `output: standalone`) → **os48** por último, que é
onde há cliente validando dado.
Para cada uma: Dockerfile no repo da app → Build no Komodo → Stack com labels → remover
a entrada do `legacy.yml` → parar e desabilitar a unit systemd.
**Aceite (por app):** domínio responde, dado do Postgres aparece, logs limpos, e a unit
antiga desabilitada.
**Rollback (por app):** restaurar a entrada no `legacy.yml` e `systemctl start <app>`.
O `/srv/<app>` e a unit ficam intactos até a fase 3.

### Fase 3 — Limpeza
Adota o rustdesk como Stack (sem mudar o compose dele). Remove nginx, `bin/deploy.sh`,
as units e drop-ins de `etc/systemd`, os vhosts de `etc/nginx`, `/srv/plataforma` (resto
de projeto removido) e o `certbot.timer` órfão. Atualiza `apps.md` e `README.md`.
**Aceite:** `systemctl list-units` sem serviço de app; `docker ps` com tudo; dotfiles
sem arquivo morto.

## 10. Riscos

| Risco | Mitigação |
|---|---|
| mTLS/AOP mal configurado derruba todos os domínios de uma vez | É por isso que a borda migra sozinha na fase 1; rollback para nginx em menos de 1 min |
| RAM: Komodo (~600MB) + Traefik (~50MB) sobre 2.2G livres | Sobra ~1.5G. Se apertar, o candidato de corte é o heap de 3G do minecraft |
| Disco: imagens + build cache na VPS | 28G livres; prune periódico pelo próprio Komodo |
| Build competindo com produção por CPU (2 vCPU) | Buildar fora de horário de uso; se virar problema recorrente, mover o lgmateus para GitHub Actions + GHCR |
| `crea.lglabs.tech` sem AOP na zona | Nasce em `cf-aop-optional`; endurecer depois de ligar AOP no dashboard |
| Perda do limite de upload de 25MB no crea | Aceito conscientemente; se necessário, `buffering` middleware do Traefik |

## 11. Fora de escopo

Postgres em container, minecraft em container, rustdesk saindo de `network_mode: host`,
build em GitHub Actions/GHCR, e qualquer mudança de comportamento das aplicações. A
migração é de empacotamento e roteamento, não de funcionalidade.

## 12. Pendências manuais (não versionáveis)

- DNS `komodo.lgmateus.com` → A proxied para o IP da VPS.
- Política do Cloudflare Access para o subdomínio do Komodo.
- Ligar Authenticated Origin Pulls na zona `lglabs.tech`.
- `output: "standalone"` no repo `lgmateus.com`.
