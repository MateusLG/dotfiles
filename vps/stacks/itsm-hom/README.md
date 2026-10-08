# ITSM — homologação

Aplicação em https://itsm.lglabs.tech, sincronizada com `gtd-embratur/itsm`
`main`, commit `e03b0617145af60b0382eee60bb5d037184994aa`. Os PRs RDM
fechados foram retirados do runtime; o agendador RDM foi desativado.

O contexto de build vem de `git archive` da revisão, com autenticação privada
do registry via segredo BuildKit `npm_auth`. A imagem registra o SHA no label
`org.opencontainers.image.revision`.

A aplicação inicia com `node server.js`, preservando banco e volume externo
de anexos. Esta reversão de código não apaga as tabelas adicionais do banco.
Segredos permanecem no arquivo privado de ambiente do operador, passado a
`docker compose --env-file CAMINHO_PRIVADO`; nenhum segredo é versionado.
