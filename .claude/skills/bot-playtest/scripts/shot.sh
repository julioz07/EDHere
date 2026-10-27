#!/usr/bin/env bash
# Modo tablet: toca (opcional, em coordenadas da captura de 2000x1250) e tira uma captura.
# Uso: shot.sh [x y] [espera] [saida.png]
export MSYS_NO_PATHCONV=1
ADB=${ADB:-~/AppData/Local/Android/Sdk/platform-tools/adb}
OUT=${4:-$PWD/shot.png}
if [ -n "$2" ]; then
  $ADB shell input tap $(( $1 * 128 / 100 )) $(( $2 * 128 / 100 ))
fi
sleep "${3:-2}"
$ADB emu screenrecord screenshot "$(cygpath -w "$OUT")" >/dev/null
$ADB logcat -d | grep -E "EDHereForge.*(E |match|act)|AndroidRuntime|E flutter" | tail -5
