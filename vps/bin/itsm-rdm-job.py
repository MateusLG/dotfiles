#!/usr/bin/env python3
"""Gatilho da fila/reconciliacao RDM na homologacao, via HTTP interno.

O segredo permanece no ambiente do container. Nenhuma credencial e impressa
ou passada pela linha de comando; falhas HTTP resultam em falha do servico.
"""
import subprocess

SCRIPT = r'''
fetch("http://127.0.0.1:5000/api/internal/rdm/jobs", {
  method: "POST",
  redirect: "manual",
  headers: { authorization: "Bearer " + process.env.RDM_JOBS_SECRET },
  signal: AbortSignal.timeout(240000),
}).then(async response => {
  if (!response.ok) throw new Error("RDM job HTTP " + response.status);
  if (!response.headers.get("content-type")?.includes("application/json")) {
    throw new Error("RDM job respondeu em formato inesperado");
  }
  console.log(JSON.stringify(await response.json()));
}).catch(error => { console.error(error.message); process.exitCode = 1; });
'''
subprocess.run([
    "docker", "exec", "itsm-hom-itsm-hom-1", "node", "-e", SCRIPT
], check=True, timeout=260)
