#!/usr/bin/env bash
# Dump diario dos bancos Postgres locais, formato custom (-Fc, ja comprimido e
# restauravel com pg_restore), com retencao. Roda como o user postgres (peer auth).
# O diretorio de destino precisa existir e ser gravavel pelo postgres (criado no setup).
set -euo pipefail

DIR=/var/backups/postgres
DBS="turmasunb albumcopa dotsmith"
KEEP_DAYS=14
TS=$(date +%Y%m%d-%H%M%S)

for db in $DBS; do
  pg_dump -Fc "$db" -f "$DIR/$db-$TS.dump"
done

# retencao: apaga dumps com mais de KEEP_DAYS dias
find "$DIR" -maxdepth 1 -name '*.dump' -mtime +"$KEEP_DAYS" -delete
