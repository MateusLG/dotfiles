#!/bin/bash
# power-watch: o Mac não dorme (tomada ou bateria); tampa fechada e bloqueio só
# apagam a tela. Com LOW_BATT% na bateria o sleep volta ao normal, e se o Mac
# estiver fechado/bloqueado dorme na hora (hiberna em vez de desligar seco).
#
# Roda como LaunchAgent (com.mateus.power-watch). Precisa da regra em
# /etc/sudoers.d/pmset pra alternar `pmset disablesleep` sem senha.
set -u

PMSET=/usr/bin/pmset
IOREG=/usr/sbin/ioreg
STATE_DIR="$HOME/.local/state/power-watch"
LOG="$STATE_DIR/log"
LOW_BATT=${POWER_WATCH_LOW_BATT:-15}
INTERVAL=3

mkdir -p "$STATE_DIR"
exec 2>>"$LOG"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG"; }

on_ac()          { $PMSET -g batt | head -1 | grep -q "AC Power"; }
batt_pct()       { $PMSET -g batt | grep -o '[0-9]*%' | head -1 | tr -d '%'; }
lid_closed()     { $IOREG -r -k AppleClamshellState -d 4 | grep -q '"AppleClamshellState" = Yes'; }
screen_locked()  { $IOREG -n Root -d1 -a | grep -q CGSSessionScreenIsLocked; }
sleep_disabled() { $PMSET -g | grep -qE 'SleepDisabled[[:space:]]+1'; }

# Mantém o log pequeno: corta pra 500 linhas quando passar de 2000.
trim_log() {
  [[ $(wc -l <"$LOG") -gt 2000 ]] || return 0
  tail -n 500 "$LOG" >"$LOG.tmp" && mv "$LOG.tmp" "$LOG"
}

cur=0; sleep_disabled && cur=1
prev_lid=0; prev_locked=0; prev_low=0; fail_want=""
log "iniciado (disablesleep=$cur, limite ${LOW_BATT}%)"

while :; do
  ac=0; on_ac && ac=1
  pct=$(batt_pct); pct=${pct:-100}
  lid=0; lid_closed && lid=1
  locked=0; screen_locked && locked=1
  low=0; [[ $ac == 0 && $pct -le $LOW_BATT ]] && low=1

  want=1; [[ $low == 1 ]] && want=0

  if [[ $want != "$cur" ]]; then
    if /usr/bin/sudo -n $PMSET -a disablesleep "$want" 2>/dev/null; then
      cur=$want; fail_want=""
      log "disablesleep=$cur (ac=$ac bat=${pct}%)"
    elif [[ $fail_want != "$want" ]]; then
      fail_want=$want
      log "ERRO: sudo pmset falhou (regra em /etc/sudoers.d/pmset instalada?)"
    fi
  fi

  # Bateria acabando sem ninguém usando: dorme já em vez de desligar seco.
  if [[ $low == 1 && $prev_low == 0 && ($lid == 1 || $locked == 1) ]]; then
    log "bateria em ${pct}% e Mac fechado/bloqueado: dormindo"
    $PMSET sleepnow
  fi

  if [[ $cur == 1 ]]; then
    if [[ ($lid == 1 && $prev_lid == 0) || ($locked == 1 && $prev_locked == 0) ]]; then
      $PMSET displaysleepnow
      log "tela apagada (tampa=$lid bloqueio=$locked)"
      # Apagar a tela bloqueia em seguida; não tratar esse bloqueio como novo.
      locked=1
    fi
  fi
  prev_lid=$lid; prev_locked=$locked; prev_low=$low

  trim_log
  sleep $INTERVAL
done
