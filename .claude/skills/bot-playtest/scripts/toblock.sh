#!/usr/bin/env bash
# Joga sozinho até ao primeiro pedido de bloqueio: fica com a mão, no meu turno
# toca em todas as cartas da mão (paga com Auto), nunca ataca, passa o resto.
export MSYS_NO_PATHCONV=1
ADB=${ADB:-~/AppData/Local/Android/Sdk/platform-tools/adb}
tap() { $ADB shell input tap $(( $1 * 128 / 100 )) $(( $2 * 128 / 100 )); }
last() { $ADB logcat -d | grep "I flutter : forge prompt t" | tail -1 | cut -c40-; }
played=""
for i in $(seq 1 ${1:-150}); do
  L=$(last)
  case "$L" in
    *bloccare*) echo ">> BLOCO: $L"; exit 0 ;;
    *Waiting*|"") sleep 2; continue ;;
    *"tenere la mano"*) tap 1920 576 ;;
    *"iniziare o pescare"*) tap 1915 610 ;;
    *attaccare*) tap 1930 613 ;;                 # OK sem atacantes
    *Paga*) tap 1770 610 ;;     # Annulla
    *scartare*) tap 520 1100; sleep 2; tap 1930 610 ;;
    *"(Ana)"*"Principale pre"*)
      t=$(echo "$L" | grep -o "prompt t[0-9]*")
      if [ "$played" != "$t" ]; then
        played=$t
        for x in 520 660 800 940 1080 1220 1360 1480; do
          tap $x 1100; sleep 2
          M=$(last)
          case "$M" in *Paga*) tap 1922 610; sleep 3; case "$(last)" in *Paga*) tap 1770 610; sleep 2 ;; esac ;; esac
          case "$M" in *bersaglio*|*Scegli*) tap 1786 610; sleep 2 ;; esac
        done
      fi
      tap 1709 610 ;;                              # Terminar o turno
    *"Pila: Vuoto"*) tap 1915 610 ;;
    *) tap 1912 654 ;;                             # resolver (pilha)
  esac
  sleep 3
done
echo ">> fim: $(last)"
