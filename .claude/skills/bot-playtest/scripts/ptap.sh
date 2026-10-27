#!/usr/bin/env bash
# Como shot.sh, mas com o emulador em modo telemóvel (720x1280 no meio da
# captura de 2000x1250): converte as coordenadas da captura para o ecrã.
# Uso: ptap.sh [x y] [espera] [saida.png]
export MSYS_NO_PATHCONV=1
ADB=${ADB:-~/AppData/Local/Android/Sdk/platform-tools/adb}
OUT=${4:-$PWD/shot.png}
if [ -n "$2" ]; then
  $ADB shell input tap $(( ($1 - 648) * 1023 / 1000 )) $(( $2 * 1024 / 1000 ))
fi
sleep "${3:-2}"
$ADB emu screenrecord screenshot "$(cygpath -w "$OUT")" >/dev/null
$ADB logcat -d | grep -E "overflowed|EXCEPTION" | tail -3
