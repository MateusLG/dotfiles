# ITSM RDM — imagem da homologação

Fonte ITSM `7692407a7530b72e70f0bfe10ba4c72b95ceee99`, cadeia draft #197–#215.
Imagem `itsm-hom:rdm-7692407`, ID
`sha256:a87f50a63e1b4e2349f0464a119b52eaf4d92defb355ac4d466bf56cb96f3b12`.

Build Linux completo com `--no-cache`, lockfile congelado e npmrc efêmero
montado exclusivamente por BuildKit. Label e manifesto conferidos; UID 10001,
CMD `node server.js`, token ausente de history/config e arquivos privados
ausentes na imagem. Npmrc removido no Mac e no servidor.

Smoke em containers exclusivos, rede `none` e banco sintético inacessível:
login 200 em ambos, fluxo desligado/jobs 404, fluxo ativo sem segredo/jobs 403.
Revisão do manifesto igual ao label. Containers do smoke removidos.

A troca de Compose altera somente a imagem e a referência do comentário.
Não muda schema, migrações, segredos, transporte de e-mail, rede ou volumes.
Publicação depende dos gates do ITSM; este registro prova build/smoke,
sem antecipar publicação, merge ou aceite institucional. Os dois ambientes
citados pelo mantenedor são homologação. Não há operação de migração ou reset
nesta atualização.

Gates de corte desta imagem, seguindo também o [procedimento geral](../stacks/itsm-hom/README.md):

1. Aguardar CI RDM e Quadros do SHA final verde; conferir o ID local da tag
   contra `sha256:a87f50a63e1b4e2349f0464a119b52eaf4d92defb355ac4d466bf56cb96f3b12`
   imediatamente antes do redeploy. Preservar `itsm-hom:rdm-8f071ce`.
2. Atualizar somente a aplicação, usando a configuração privada existente.
   Conferir imagem efetiva do container contra esse mesmo ID, saúde e manifesto.
3. Comparar com a leitura anterior: 54 usuários, 208 chamados, 73 arquivos
   (conteúdo por SHA-256) e hashes das quatro chaves existentes, sem imprimir
   seus valores. Nenhum teste cria pessoas ou RDM reais nesta conferência.
4. Se saúde, manifesto, imagem ou integridade falharem, restaurar o Compose
   e a tag anterior com os mesmos segredos/volumes; não aplicar migrações nem
   apagar dados. Registrar o resultado do corte separado do build/smoke.

Ensaio no host `lglabs`, build encerrado em `2026-10-08T02:35:49.352372+00:00`.
Artefatos locais em `/home/mateus/rdm-build-7692407`, com índice não secreto
copiado para o Mac. SHA-256:

- `build.log`: `b0d128a0e3635fccbe34890f652ab5a8eca31adf20138d96efe49577dae1be44`.
- `source.tar`: `08123c1b2cfbebb21117e5d92344b181d64bf53d38ab7fd5c8c9504071742978`.
- `image-proof.json`: `7ef6d73de598f68984d2558cb11235e9b1bb9692cea02f0074f7ee1c481c9834`.
- `smoke.json`: `eeaedbebfa0261e6f1f1cf02fdd1e320a7a07713ce94887e0b17905eeeb7da34`.

Comandos do build e da conferência (npmrc privado fora do contexto):

```sh
docker build --no-cache \
  --secret id=npm_auth,src="$RDM_NPMRC_PRIVADO" \
  --build-arg DEPLOYED_REVISION=7692407a7530b72e70f0bfe10ba4c72b95ceee99 \
  -f vps/stacks/itsm-hom/Dockerfile \
  -t itsm-hom:rdm-7692407 "$RDM_CONTEXTO_GIT_ARCHIVE"
docker image inspect itsm-hom:rdm-7692407 --format '{{.Id}}'
docker image inspect itsm-hom:rdm-7692407 --format '{{index .Config.Labels "org.opencontainers.image.revision"}}'
```

`check-image.py` no diretório do ensaio lê a credencial pelo stdin e emite só
booleanos, revisão, ID/CMD/UID; não passa token em ARG/ENV ou argumentos.
A matriz HTTP foi executada com `docker run --network none --read-only
--cap-drop ALL --security-opt no-new-privileges`, tmpfs em `/tmp` e no cache,
1 GiB/1 CPU, URL PostgreSQL sintética de loopback e ausência de segredo do job.
O probe usou `docker exec … node -e` para login, POST jobs e GET manifesto;
`smoke.json` registra os status exatos, e os containers foram removidos.
