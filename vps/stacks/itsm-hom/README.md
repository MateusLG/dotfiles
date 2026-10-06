# ITSM — homologação RDM

Stack de dados sintéticos em `itsm.lglabs.tech`, com imagem de aplicação
fixada pelo commit. Startup é `node server.js`; migrações são operações
explícitas, com backup, fora da inicialização. Volume de anexos externo
existente e socket ClamAV preservados. Segredos permanecem no arquivo de
ambiente privado do operador; nenhum segredo é versionado. Passe esse arquivo
explicitamente por `docker compose --env-file CAMINHO_PRIVADO` em operações
fora do Komodo, preservando os valores existentes.

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
