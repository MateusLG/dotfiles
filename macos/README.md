# macos

Configuração adaptada pro **macOS (Apple Silicon)**. Terceira variante do zsh,
ao lado de [`zsh/`](../zsh/) (Omarchy/Arch) e [`wsl/`](../wsl/) (WSL2/Arch).

Partiu do `wsl/zshrc` — que já é a versão sem Omarchy/Hyprland — e trocou o que
era específico de Linux/Windows.

## Arquivos

- `zshrc` — vai em `~/.zshrc`.
- `terminal/` — perfil do Terminal.app com o tema, e o gerador dele.
- `Brewfile` — dependências. `brew bundle --file=macos/Brewfile`.
- `install.sh` — instalador idempotente (symlinks + backup do que existia).
- `merge-codex-config.py` — merge do config do Codex (ver abaixo).
- `install-nerdfonts.sh` — Nerd Fonts em `~/Library/Fonts`, sem sudo. Equivalente macOS do [`wsl/install-nerdfonts.ps1`](../wsl/install-nerdfonts.ps1).

## Diferenças em relação ao `wsl/zshrc`

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
ele precisa é da fonte certa — sem uma Nerd Font, o p10k vira um monte de
caixinhas.

`terminal/make-profile.py` gera um perfil `.terminal` a partir do
`colors.toml` do tema — a paleta segue morando num lugar só, como já
acontece com os terminais do Linux, e cada um deriva dela.

```bash
python3 macos/terminal/make-profile.py            # lg-abissal, MesloLGS NF 13pt
python3 macos/terminal/make-profile.py lg-umbra   # outro tema
```

Para instalar: duplo clique no `.terminal` (ou `open`), e depois
**Terminal > Configurações > Perfis > lg-abissal > Padrão**. Não dá pra
symlinkar — o Terminal.app guarda os perfis nos próprios defaults, não em
arquivo.

O perfil já vem com `useOptionAsMetaKey`, senão os atalhos de shell com Meta
não chegam no zsh.

## Codex

O `~/.codex/config.toml` é escrito pelo próprio Codex e guarda estado da
máquina (`[marketplaces.*]`, `[mcp_servers.*]`, `[projects.*]`, `notify`) com
paths absolutos — copiar o do repo por cima destrói isso. O
`merge-codex-config.py` junta os dois: preferências do repo mandam, blocos da
máquina são preservados. Roda dentro do `install.sh`, com backup antes.

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

## O que NÃO se aplica ao macOS

`hypr/`, `waybar/`, `omarchy/` (Wayland/Arch), `system/` (systemd), `wsl/`,
e `scripts/` (`work.sh` depende de FortiClient+Remmina; `lgfetch.sh` lê o tema
atual do Omarchy).

## Instalação

```bash
# 1. Homebrew (pede senha de sudo — precisa ser você)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 2. Resto
bash ~/DEV/dotfiles/macos/install.sh
```

Depois, `p10k configure` se quiser regerar o `~/.p10k.zsh` (o instalador linka o
do `zsh/`, gerado no Linux — funciona, mas foi feito pra outra fonte/terminal).

O instalador move qualquer arquivo existente pra `<arquivo>.bak-<timestamp>`
antes de criar o symlink.
