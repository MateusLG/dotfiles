#!/usr/bin/env bash
# lgfetch — fastfetch com mascote/cor por tema do Omarchy.
#
#   lg-umbra    → bonsai (verde)
#   lg-abissal  → tubarão estilo "Jaws" (azul)
#   outro/desconhecido → fastfetch padrão

set -uo pipefail

if ! command -v fastfetch >/dev/null 2>&1; then
  echo "lgfetch: fastfetch não está instalado." >&2
  exit 1
fi

THEME_FILE="${HOME}/.config/omarchy/current/theme.name"
if [[ -r "$THEME_FILE" ]]; then
  THEME="$(tr -d '[:space:]' < "$THEME_FILE")"
else
  THEME="unknown"
fi

# Logos: $1 vira a cor configurada via --logo-color-1 no fastfetch.
# Árvore: oak "Krogg" (ascii.co.uk/art/tree).
PLANT="$(cat <<'EOF'
$1                      ___
$1                _,-'""   """"`--.
$1             ,-'          __,,-- \
$1           ,'    __,--""""dF      )
$1          /   .-"Hb_,--""dF      /
$1        ,'       _Hb ___dF"-._,-'
$1      ,'      _,-""""   ""--..__
$1     (     ,-'                  `.
$1      `._,'     _   _             ;
$1       ,'     ,' `-'Hb-.___..._,-'
$1       \    ,'"Hb.-'HH`-.dHF"
$1        `--'   "Hb  HH  dF"
$1                "Hb HH dF
$1                 "HbHHdF
$1                  |HHHF
$1                  |HHH|
$1                  |HHH|
$1                  |HHH|
$1                  |HHH|
$1                  dHHHb
$1                .dFd|bHb.               o
$1      o       .dHFdH|HbTHb.          o /
$1\  Y  |  \__,dHHFdHH|HHhoHHb.__Krogg  Y
$1##########################################
EOF
)"

# Tubarão: "Sammy the Shark" (gist: lorentzca/a73218fa97225d05e9fef22cf4984d6a).
SHARK="$(cat <<'EOF'
$1                      ■■■
$1                     ■■  ■■■■
$1                     ■■      ■■■
$1   ■■■               ■■        ■■
$1   ■ ■■               ■■         ■■
$1   ■  ■■               ■■         ■■
$1   ■   ■■              ■■           ■■
$1   ■   ■■              ■■            ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
$1    ■   ■■    ■■■      ■■                                         ■■■■
$1    ■■    ■■■■   ■■■■■■           ■  ■  ■        ■■■■■■■             ■■■■
$1     ■                           ■  ■  ■       ■■   ■■■■■               ■■
$1   ■■                            ■  ■  ■      ■■   ■■■■■■■             ■■
$1  ■    ■■■■■                     ■  ■  ■      ■    ■■  ■■■            ■■
$1 ■   ■■    ■                     ■  ■  ■      ■    ■■■■■■■           ■■
$1■■■■■      ■■■■■                 ■  ■  ■       ■■■    ■■■          ■■
$1               ■■                ■  ■  ■         ■■■■■■           ■■
$1                ■■                ■  ■  ■  ■■                    ■■
$1                  ■■                      ■  ■■■               ■■■
$1                    ■■                    ■    ■■■           ■■■
$1                     ■■■                  ■■ ■■■  ■■■■■■■■■■■■
$1                    ■■■■                   ■■■ ■■■       ■■
$1              ■■■■■■                         ■■■ ■■■      ■■
$1            ■■                                 ■■■ ■      ■■
$1             ■■         ■■■■■■■                   ■■■■■■■■■
$1               ■■■■■■■■■      ■■■                       ■■
$1                                 ■■■■■■■           ■■■■■
$1                                        ■■■■■■■■■■■
EOF
)"

case "$THEME" in
  lg-umbra)
    LOGO="$PLANT"
    COLOR="38;2;156;204;133"   # #9ccc85
    ;;
  lg-abissal)
    LOGO="$SHARK"
    COLOR="38;2;94;179;209"    # #5eb3d1
    ;;
  *)
    exec fastfetch "$@"
    ;;
esac

exec fastfetch \
  --logo-type data \
  --logo "$LOGO" \
  --logo-color-1 "$COLOR" \
  "$@"
