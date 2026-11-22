import json
import os
import re
from pathlib import Path
import sys
from tempfile import NamedTemporaryFile

CARPETA = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "cerrar-ventanas"
ARCHIVO = CARPETA / "perfiles.json"
ACTIVO = CARPETA / "perfil-activo.json"
PREDETERMINADO = "predeterminado"


def leer_excepciones(datos):
    if not isinstance(datos, dict) or any(
        not isinstance(ids, list) or not all(isinstance(i, str) for i in ids)
        for ids in datos.values()
    ):
        raise ValueError("Las excepciones tienen un formato inválido.")
    return datos


def nuevo(nombre, excepciones=None):
    return {"nombre": nombre, "excepciones": excepciones or {}, "actual": False, "conservar_activa": False}


def leer():
    try:
        datos = json.loads(ARCHIVO.read_text(encoding="utf-8"))
    except FileNotFoundError:
        try:
            anteriores = json.loads((CARPETA / "excepciones.json").read_text(encoding="utf-8"))
        except FileNotFoundError:
            anteriores = {}
        return {
            "activo": PREDETERMINADO,
            "perfiles": {PREDETERMINADO: nuevo("Personal", leer_excepciones(anteriores))},
        }

    if not isinstance(datos, dict) or not isinstance(datos.get("perfiles"), dict):
        raise ValueError("El archivo de perfiles tiene un formato inválido.")
    entradas = datos["perfiles"]
    activo = datos.get("activo")
    if PREDETERMINADO not in entradas or not isinstance(activo, str) or activo not in entradas:
        raise ValueError("El archivo de perfiles tiene un formato inválido.")
    for clave, perfil in entradas.items():
        if not re.fullmatch(r"predeterminado|[0-9a-f]{32}", clave) or not isinstance(perfil, dict):
            raise ValueError("El archivo de perfiles tiene un formato inválido.")
        if not isinstance(perfil.get("nombre"), str) or not perfil["nombre"].strip() or any(
            type(perfil.get(opcion)) is not bool for opcion in ("actual", "conservar_activa")
        ):
            raise ValueError("El archivo de perfiles tiene un formato inválido.")
        leer_excepciones(perfil.get("excepciones"))
    if entradas[PREDETERMINADO]["nombre"] == "Predeterminado":
        entradas[PREDETERMINADO]["nombre"] = "Personal"
    try:
        seleccionado = json.loads(ACTIVO.read_text(encoding="utf-8"))
    except (FileNotFoundError, ValueError):
        seleccionado = None
    if isinstance(seleccionado, str) and seleccionado in entradas:
        datos["activo"] = seleccionado
    return datos


def resumen(modelo):
    return {
        "activo": modelo["activo"],
        "perfiles": [{"id": clave, "nombre": perfil["nombre"]} for clave, perfil in modelo["perfiles"].items()],
    }


def avisar_widgets(senal, datos=None):
    from fcntl import LOCK_EX, flock
    from gi.repository import Gio, GLib

    servicio = "org.local.Byotfast.WidgetEvents"
    interfaz_bus = "org.freedesktop.DBus"
    ruta_bus = "/org/freedesktop/DBus"

    try:
        bloqueo = Path(GLib.get_user_runtime_dir()) / "byotfast-widget-events.lock"
        with bloqueo.open("a") as archivo:
            flock(archivo, LOCK_EX)
            bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
            respuesta, = bus.call_sync(
                interfaz_bus, ruta_bus, interfaz_bus, "RequestName",
                GLib.Variant("(su)", (servicio, 4)), GLib.VariantType.new("(u)"),
                Gio.DBusCallFlags.NONE, 1000, None,
            ).unpack()
            if respuesta not in (1, 4):
                return
            try:
                bus.emit_signal(None, "/org/local/Byotfast/Widgets", "org.local.Byotfast.Widgets",
                                senal, GLib.Variant("(s)", (json.dumps(datos),)))
            finally:
                bus.call_sync(
                    interfaz_bus, ruta_bus, interfaz_bus, "ReleaseName",
                    GLib.Variant("(s)", (servicio,)), GLib.VariantType.new("(u)"),
                    Gio.DBusCallFlags.NONE, 1000, None,
                )
    except (GLib.Error, OSError):
        # El estado persistido se lee al cargar Plasma.
        pass


def guardar(datos, destino):
    destino.parent.mkdir(parents=True, exist_ok=True)
    with NamedTemporaryFile(dir=destino.parent, delete=False, mode="w", encoding="utf-8") as temporal:
        ruta = Path(temporal.name)
        try:
            json.dump(datos, temporal, ensure_ascii=False, indent=2)
            temporal.close()
            ruta.replace(destino)
        finally:
            ruta.unlink(missing_ok=True)
    if destino in (ARCHIVO, ACTIVO):
        try:
            estado = resumen(leer())
        except (OSError, ValueError):
            return
        avisar_widgets("PerfilCambiado", estado)


def seleccionar(clave):
    if clave not in leer()["perfiles"]:
        raise ValueError("No se encontró ese perfil de cierre.")
    guardar(clave, ACTIVO)


def emitir_script(argumentos):
    if len(argumentos) == 2 and argumentos[0] == "--listar":
        destino = argumentos[1]
        if not re.fullmatch(r":[0-9]+\.[0-9]+", destino):
            raise ValueError("Destino D-Bus inválido.")
        print("""
function informar() {
    const ventanas = [];
    for (const ventana of workspace.windowList()) {
        if (ventana && (ventana.normalWindow || ventana.dialog)) {
            ventanas.push([ventana.desktopFileName, ventana.resourceClass, ventana.caption].map(
                valor => valor == null ? "" : String(valor)
            ));
        }
    }
    callDBus(DESTINO, "/org/local/Byotfast/Ventanas", "org.local.Byotfast.Ventanas",
             "Recibir", JSON.stringify(ventanas));
}
""".replace("DESTINO", json.dumps(destino)))
        print("informar();")
        return

    if len(argumentos) not in (0, 2) or (argumentos and argumentos[0] != "--perfil"):
        raise ValueError("Uso: cerrar-ventanas.sh [--perfil identificador]")
    datos = leer()
    clave = argumentos[1] if argumentos else datos["activo"]
    perfil = datos["perfiles"].get(clave)
    if perfil is None:
        raise ValueError("No se encontró ese perfil de cierre.")
    opciones = {
        "actual": perfil["actual"],
        "conservar_activa": perfil["conservar_activa"],
        "protegidas": sorted({identificador for ids in perfil["excepciones"].values() for identificador in ids}),
    }
    print("const perfil = " + json.dumps(opciones) + ";")
    print("""
const protegidas = new Set(perfil.protegidas.map(id => id.toLowerCase()));
const activa = workspace.activeWindow;
const escritorio = workspace.currentDesktop;
for (const ventana of workspace.windowList()) {
    if (!ventana || !ventana.closeable || !(ventana.normalWindow || ventana.dialog)) {
        continue;
    }
    if (perfil.conservar_activa && activa && String(ventana.internalId) === String(activa.internalId)) {
        continue;
    }
    if (perfil.actual && escritorio && !ventana.onAllDesktops &&
        !Array.prototype.some.call(ventana.desktops, d => d.id === escritorio.id)) {
        continue;
    }
    if ([ventana.desktopFileName, ventana.resourceClass].some(id => protegidas.has(String(id).toLowerCase()))) {
        continue;
    }
    ventana.closeWindow();
}
""")


if __name__ == "__main__":
    try:
        emitir_script(sys.argv[1:])
    except (OSError, ValueError) as error:
        sys.exit(str(error))
