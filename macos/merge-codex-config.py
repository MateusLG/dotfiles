#!/usr/bin/env python3
"""Faz o merge do codex/config.toml do repo com o ~/.codex/config.toml local.

O config local é escrito pelo próprio Codex e carrega estado da máquina
(paths absolutos em [marketplaces.*], [mcp_servers.*], [projects.*]). O do
repo carrega as preferências versionadas. Copiar por cima destruiria um dos
dois, então: preferências do repo mandam, o resto do local é preservado.

Merge é textual por bloco (o tomllib só existe no Python 3.11+, e o macOS
ainda vem com o 3.9).

Uso: merge-codex-config.py <repo_config> <local_config> <saida>
"""
import sys


def parse(text):
    """Divide o TOML em (preambulo, [(header, corpo), ...]).

    Comentários e linhas em branco logo antes de um header pertencem a ele.
    """
    preamble, blocks = [], []
    header, body, pending = None, [], []

    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            # Fecha o bloco anterior, devolvendo o pending pro próximo.
            if header is None:
                preamble.extend(body)
            else:
                blocks.append((header, body))
            header, body, pending = stripped, pending + [line], []
        elif stripped == "" or stripped.startswith("#"):
            pending.append(line)
        else:
            body.extend(pending)
            pending = []
            body.append(line)

    if header is None:
        preamble.extend(body)
    else:
        blocks.append((header, body))
    return preamble, blocks


def keys(lines):
    """Nomes das chaves top-level definidas nessas linhas."""
    out = set()
    for line in lines:
        s = line.strip()
        if s and not s.startswith("#") and "=" in s:
            out.add(s.split("=", 1)[0].strip())
    return out


def main():
    repo_path, local_path, out_path = sys.argv[1:4]
    with open(repo_path, encoding="utf-8") as fh:
        repo_pre, repo_blocks = parse(fh.read())
    with open(local_path, encoding="utf-8") as fh:
        local_pre, local_blocks = parse(fh.read())

    repo_keys = keys(repo_pre)
    repo_headers = {h for h, _ in repo_blocks}

    out = list(repo_pre)

    # Chaves top-level que só o local tem (ex: notify, apontando pro app).
    kept_pre = [l for l in local_pre
                if not (l.strip() and not l.strip().startswith("#")
                        and "=" in l and l.split("=", 1)[0].strip() in repo_keys)]
    if any(l.strip() for l in kept_pre):
        out.append("")
        out.append("# ── preservado do ~/.codex/config.toml desta máquina ──")
        out.extend(l for l in kept_pre if l.strip())

    for _, body in repo_blocks:
        out.extend(body)

    machine = [(h, b) for h, b in local_blocks if h not in repo_headers]
    if machine:
        out.append("")
        out.append("# ── blocos desta máquina (escritos pelo Codex) ──")
        out.append("# Não versionar: paths absolutos. Ver codex/README.md.")
        for _, body in machine:
            out.extend(body)

    text = "\n".join(out).rstrip() + "\n"
    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write(text)

    dropped = sorted(h for h, _ in local_blocks if h in repo_headers)
    if dropped:
        print("blocos locais substituídos pela versão do repo: "
              + ", ".join(dropped))


if __name__ == "__main__":
    main()
