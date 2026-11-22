#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
temporal=$(mktemp -d ./.empaquetar.XXXXXXXX)
trap 'rm -rf -- "$temporal"' EXIT
cp -R -- cerrar-ventanas "$temporal/"
chmod +x "$temporal/cerrar-ventanas/"{instalar,cerrar-ventanas.sh,ajustes-cerrar-ventanas.py}
tar --exclude='__pycache__' --exclude='*.py[co]' -czf "$temporal/paquete.tar.gz" -C "$temporal" cerrar-ventanas
{
    cat herramientas/instalador-cabecera
    base64 "$temporal/paquete.tar.gz"
    cat herramientas/instalador-pie
} > "$temporal/instalar-byotfast.run"
bash -n "$temporal/instalar-byotfast.run"
chmod 755 "$temporal/instalar-byotfast.run"
mv -f -- "$temporal/instalar-byotfast.run" instalar-byotfast.run
