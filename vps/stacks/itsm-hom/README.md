# ITSM — homologação RDM

Stack de dados sintéticos em `itsm.lglabs.tech`, com imagem de aplicação
fixada pelo commit. Startup é `node server.js`; migrações são operações
explícitas, com backup, fora da inicialização. Volume de anexos externo
existente e socket ClamAV preservados. Segredos permanecem no arquivo de
ambiente privado do operador; nenhum segredo é versionado. Passe esse arquivo
explicitamente por `docker compose --env-file CAMINHO_PRIVADO` em operações
fora do Komodo, preservando os valores existentes.

## Build com dependências privadas

O `Dockerfile` desta pasta usa Node e frontend BuildKit presos por digest,
pnpm 10.34.5, lockfile congelado e segredo obrigatório `npm_auth`. O contexto
deve vir de `git archive` da revisão do ITSM, sem configuração do operador.
Passar o mesmo SHA em `DEPLOYED_REVISION` e no manifesto público.

O segredo é um arquivo npmrc privado (`0600`), fora do contexto, contendo
autenticação do registry GitHub Packages com permissão de leitura. Montar com
`--secret id=npm_auth,src=CAMINHO_PRIVADO_NPMRC`; nunca usar token em ARG, ENV,
linha de comando ou arquivo versionado. A instalação ignora hooks e scripts;
somente os rebuilds permitidos rodam depois de desmontar o segredo.

Para provar instalação do zero, construir com `--no-cache`: o conteúdo de
secrets não invalida cache BuildKit. Cache e imagens de dependências ficam
privados no host. Conferir código de saída, label, CMD/UID, ausência do token
em history/config e arquivos de credencial na imagem. Remover o npmrc privado
após a operação. Atualizar Compose só após build completo e smoke aprovados;
comparar banco/anexos/segredos antes/depois e preservar a imagem compatível.

## SMTP capturado

`rdm-mailpit` aceita SMTP em 1025 na rede Docker `rdm-email` interna, sem
relay/forward, rede externa, portas publicadas ou labels de exposição.
UI/API 8025 também ficam internas. A aplicação usa esse capturador em HOMOL;
aceite SMTP significa captura de teste, nunca entrega institucional.
Imagem Mailpit fixada por versão/digest, volume privado persistente e
captura limitada a 1.000 mensagens/7 dias e 1 MB por mensagem. Fila e logs
de auditoria no PostgreSQL mantêm a prova durável; esse limite vale somente
para a captura sintética. Não colocar dados reais nesse ambiente.

Status: `docker compose ps`. Para verificar as capturas sem publicar UI,
usar o Node do container da aplicação para GET `http://rdm-mailpit:8025/api/v1/messages`
e emitir somente contagem/identificadores de teste, sem corpo/token das mensagens.

Conter falha do SMTP: interromper o timer RDM e restaurar a configuração
anterior sem SMTP; a fila mantém retry e não confirma entrega ausente.
Manter código compatível, flags de RDM e volumes de banco/anexos/captura.
Não apagar snapshots, votos, fila, logs ou volumes como rollback.

## Dependências institucionais

Cargos/autoridades e calendário reais exigem atestado/designação da GTD;
nenhum seed automático configura esses dados ou fabrica aprovações.
Produção exige transporte institucional autorizado e aceite da supervisora/GTD.
