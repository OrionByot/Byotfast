#!/bin/bash
set -euo pipefail

modo=${1:-}
script=$(mktemp --suffix=.js)
script_name=${script##*/}
cleanup() {
    if [[ -n ${script_id:-} ]]; then
        qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript "$script_name" >/dev/null 2>&1 || true
    fi
    rm -f -- "$script"
}
trap cleanup EXIT

fallo() {
    printf '%s\n' "$1" >&2
    if [[ $modo != --listar && ! -t 2 ]] && command -v kdialog >/dev/null; then
        kdialog --title 'Byotfast' --error "$1" || true
    fi
    exit 1
}

origen=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if ! error=$(/usr/bin/python3 "$origen/perfiles.py" "$@" 2>&1 > "$script"); then
    fallo "$error"
fi

if ! script_id=$(qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$script" "$script_name" 2>&1); then
    fallo "No se pudo cargar el script en KWin: $script_id"
fi
if [[ ! $script_id =~ ^[0-9]+$ ]]; then
    fallo "KWin no pudo cargar el script: $script_id"
fi
if ! resultado=$(qdbus6 org.kde.KWin "/Scripting/Script$script_id" org.kde.kwin.Script.run 2>&1); then
    fallo "KWin no pudo ejecutar el cierre: $resultado"
fi
