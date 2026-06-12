# Claude Code no celular (mosh + tmux + Termius)

Usar o Claude Code da VPS de qualquer lugar pelo iPhone, sobrevivendo a troca de
rede (WiFi↔4G), sono do celular e mudança de IP.

- **Transporte:** mosh (UDP) — a sessão sobrevive a roaming/sleep/IP novo.
- **Persistência:** tmux — o processo do Claude fica vivo na VPS mesmo desconectado.
- **Auth:** só chave SSH (a VPS é key-only; ver `00-hardening.conf`).
- **Cliente:** Termius (iOS), com chave dedicada `iphone`.

## Lado da VPS

Reproduzido pelo [`setup.sh`](setup.sh):

- pacote `mosh`;
- ufw libera `60000:60010/udp` (~10 sessões simultâneas);
- keepalive sshd em [`etc/ssh/sshd_config.d/10-keepalive.conf`](etc/ssh/sshd_config.d/10-keepalive.conf).

Falta só, por dispositivo, a chave pública do celular no `~/.ssh/authorized_keys`
(passo manual, igual à do PC). Locale precisa ser UTF-8 (a imagem já vem `C.UTF-8`).

## Lado do Termius (iPhone)

1. **Chave:** Keychain → Generate Key → **Ed25519**, nome `iphone`.
   Acrescentar a pública (`ssh-ed25519 AAAA…`) no `~/.ssh/authorized_keys` da VPS.
2. **Host:** IP da VPS, porta `22`, usuário `mateus`, key `iphone`.
3. **Mosh:** ligar o toggle **Use Mosh** nas configs do host.
4. **Startup snippet:** `tmux new -A -s mobile`
   (`-A -s mobile` = anexa na sessão `mobile` se existir, senão cria — fica só nesse
   host, não afeta o login do PC.)

## Uso

- Abrir o host no Termius → cai direto na sessão tmux `mobile`.
- Rodar o Claude: `cx` (alias do `zsh/zshrc`: limpa a tela + `claude --dangerously-skip-permissions`).
- Destacar sem matar: `Ctrl b` depois `d` (tecla `Ctrl` na barrinha do Termius).
- Trocar de rede / celular dormir: mosh reconecta sozinho, a sessão continua.

## Troubleshooting

- **`Permission denied (publickey)`** → o host no Termius não está usando a key `iphone`.
- **mosh trava em "Connecting…"** → rede/operadora bloqueando UDP, ou CGNAT. Desligar
  `Use Mosh` (cair pra SSH puro) confirma se o problema é só o transporte.
- **Aviso de locale do mosh** → garantir `LANG`/`LC_CTYPE` UTF-8 na VPS.

## Revogar acesso de um celular

Remover a linha correspondente (ex: `iphone-termius`) do `~/.ssh/authorized_keys`.
