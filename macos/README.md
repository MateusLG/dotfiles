# macos

Configuração do **macOS (Apple Silicon)** — Zsh + Powerlevel10k, fontes,
pacotes e o instalador.

Veio da variante WSL2 do setup antigo (Arch), que já era a versão sem
Omarchy/Hyprland, trocando o que era específico de Linux/Windows. A tabela
abaixo registra o que mudou e por quê; as pastas do Linux não existem mais
aqui, mas estão no histórico do git.

## Arquivos

- `zshrc` — vai em `~/.zshrc`.
- `p10k.zsh` — vai em `~/.p10k.zsh`. Gerado pelo `p10k configure`.
- `gitconfig` — vai em `~/.gitconfig`. Identidade, editor, aliases e credential via `gh`.
- `gitignore_global` — vai em `~/.gitignore_global`.
- `Brewfile` — dependências. `brew bundle --file=macos/Brewfile`.
- `install.sh` — instalador idempotente (symlinks + backup do que existia).
- `install-nerdfonts.sh` — Nerd Fonts em `~/Library/Fonts`, sem sudo.
- `merge-codex-config.py` — merge do config do Codex (ver abaixo).
- `power-watch.sh` — vai em `~/.local/bin/power-watch`. Daemon de energia (ver abaixo).
- `com.mateus.power-watch.plist` — LaunchAgent do power-watch (copiado, não linkado).
- `sudoers-pmset` — regra de sudo pro power-watch alternar o sleep. Instalação manual.

## Diferenças em relação ao zshrc do WSL/Arch

| | WSL/Arch | macOS |
|---|---|---|
| Gerenciador | pacman, paths em `/usr/share/...` | Homebrew, `$HOMEBREW_PREFIX/share/...` |
| `open()` | wrapper de `wslview`/`explorer.exe` | **removido** — o macOS já tem `open` nativo, e a função atropelava ele |
| `chrome()` | `cmd.exe /c start chrome` + `wslpath` | `open -a "Google Chrome"` |
| `sff()` | `find -printf` (GNU) | glob do zsh `**/*(.omN)` — o find BSD não tem `-printf` |
| `fzf` | `/usr/share/fzf/*.zsh` | `fzf --zsh`, com fallback pros arquivos do brew |
| Godot | aliases `mowgul`/`icebite`/`pingado` em `/mnt/c/...` | **removidos** (paths do host Windows) |
| PATH | — | `brew shellenv` antes do `compinit`, senão as completions não entram no FPATH |
| `chsh` | necessário | desnecessário, zsh já é o shell padrão do macOS |

Mantidos iguais: history, completion, aliases `eza`/git/`..`, `zd` do zoxide,
`n()`, `claude-sessions`, mise, p10k.

## Terminal.app

O macOS já traz o Terminal.app, então não instalamos terminal nenhum. O que
ele precisa é da fonte: sem uma Nerd Font, o prompt do p10k vira um monte de
caixinhas, porque ele desenha com glifos que não existem nas fontes comuns.

**Terminal > Configurações > Perfis > Texto > Fonte** → `MesloLGS NF`
(instalada pelo `install-nerdfonts.sh`). A `JetBrainsMono Nerd Font` também é
instalada, se preferir.

Vale ligar **Usar Option como tecla Meta**, na aba Teclado do perfil — sem
isso os atalhos de shell com Meta não chegam no zsh.

## Codex

O `~/.codex/config.toml` é escrito pelo próprio Codex e guarda estado da
máquina (`[marketplaces.*]`, `[mcp_servers.*]`, `[projects.*]`, `notify`) com
paths absolutos — copiar o do repo por cima destrói isso. O
`merge-codex-config.py` junta os dois: preferências do repo mandam, blocos da
máquina são preservados. Roda dentro do `install.sh`, com backup antes.

## power-watch

Padrão do macOS: fechar a tampa ou ficar ocioso põe o Mac pra dormir e mata
qualquer coisa rodando no terminal (Claude Code, Codex). O `power-watch`
inverte isso, sem nenhum comando no dia a dia:

- **Sempre acordado (tomada ou bateria):** `pmset disablesleep 1`. Fechar a
  tampa ou bloquear a tela só apaga o painel; o sistema segue rodando. Com
  "exigir senha imediatamente" ligado em Ajustes > Tela de Bloqueio, apagar
  a tela já bloqueia.
- **Bateria em 15%** desplugado: o sleep volta ao normal. Se o Mac estiver
  fechado ou bloqueado, dorme na hora (hiberna em vez de desligar seco). Ao
  plugar ou subir de 15%, volta ao acordado.

Na mochila com a tampa fechada ele fica ligado e morno até os 15%. É o
preço de não ter passo manual.

O daemon faz polling a cada 3 s (tampa, bloqueio, carregador, bateria) e
escreve em `~/.local/state/power-watch/log`. A troca do `disablesleep` passa
por `sudo`, por isso a regra em `/etc/sudoers.d/pmset` — o `install.sh` avisa
se ela não existir. Pra desinstalar: `launchctl bootout gui/$(id -u)/com.mateus.power-watch`,
apagar o plist e a regra de sudo, e `sudo pmset -a disablesleep 0`.

## Rede com inspeção TLS

Em rede que reassina TLS (FortiGate e cia), o `curl` recusa a conexão com
`unable to get local issuer certificate` e o Homebrew não instala — nem o
`portable-ruby`, nem bottle nenhum. Para diagnosticar, veja quem emitiu o
certificado:

```bash
echo | openssl s_client -connect formulae.brew.sh:443 -servername formulae.brew.sh 2>/dev/null \
  | openssl x509 -noout -issuer
```

Se o issuer não for a CA real do site, a rede está interceptando. Pegue o CA
raiz do proxy com o TI (ou exporte de outra máquina da rede que já o tenha) e:

```bash
# 1. confira que é CA raiz mesmo: subject == issuer e CA:TRUE
openssl x509 -in ca.pem -noout -subject -issuer
openssl x509 -in ca.pem -noout -text | grep -A1 "Basic Constraints"

# 2. confie nele no sistema (resolve curl, git e o Homebrew)
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain ca.pem
sudo cp ca.pem /usr/local/share/ca-certificates/fortinet-ca.pem

# 3. bundle combinado para Node/Python, que não leem o keychain
security find-certificate -a -p \
  /System/Library/Keychains/SystemRootCertificates.keychain > /tmp/bundle.pem
cat ca.pem >> /tmp/bundle.pem
sudo cp /tmp/bundle.pem /usr/local/share/ca-certificates/ca-bundle.pem
```

O `zshrc` detecta esses dois arquivos e exporta `NODE_EXTRA_CA_CERTS`,
`SSL_CERT_FILE` e `REQUESTS_CA_BUNDLE` sozinho. **O bundle precisa ser
combinado** (CAs do sistema + o do proxy): `SSL_CERT_FILE` e
`REQUESTS_CA_BUNDLE` substituem o bundle padrão em vez de somar, então
apontá-los só pro CA do proxy quebra todo host que não passa por ele.

Os certificados não são versionados aqui — são específicos da rede.

## Instalação

```bash
# 1. Homebrew (pede senha de sudo — precisa ser você)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 2. Resto
bash ~/DEV/dotfiles/macos/install.sh
```

Depois, `p10k configure` se quiser regerar o `~/.p10k.zsh` — o versionado aqui
foi gerado no Linux, para outra fonte e outro terminal. Funciona, mas pode não
ficar do jeito que você quer.

O instalador move qualquer arquivo existente pra `<arquivo>.bak-<timestamp>`
antes de criar o symlink.
