import re

from gi.repository import Gio, GLib

SERVICIO = "org.kde.kglobalaccel"
COMPONENTE = "org.local.CerrarVentanas.accion.desktop"
NOMBRE = "Byotfast"
ACCION = [COMPONENTE, "_launch", NOMBRE, NOMBRE]
LIMPIEZA = ["org.local.Byotfast.limpieza.desktop", "_launch", "Byotfast · Limpiar archivos", "Limpiar archivos"]
MODIFICADORES = {"Ctrl": 0x04000000, "Alt": 0x08000000,
                 "Shift": 0x02000000, "Meta": 0x10000000}
PREDETERMINADOS = (
    (ACCION, "Ctrl+Meta+NumPad 0"),
    (LIMPIEZA, "Ctrl+Meta+NumPad 1"),
)
TECLADO_NUMERICO = 0x20000000


def pedir(metodo, firma, *args):
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    return bus.call_sync(
        SERVICIO, "/kglobalaccel", "org.kde.KGlobalAccel", metodo,
        GLib.Variant(firma, args), None, Gio.DBusCallFlags.NONE, 3000, None
    ).unpack()


def registrar(accion=ACCION):
    componente, _, nombre, _ = accion
    pedir("doRegister", "(as)", [componente, "", nombre, ""])
    pedir("unregister", "(ss)", componente, "")


def codigo(texto):
    partes = [parte.strip() for parte in texto.split("+")]
    mods = {"meta" if parte.lower() == "super" else parte.lower() for parte in partes[:-1]}
    mapa = {nombre.lower(): valor for nombre, valor in MODIFICADORES.items()}
    if not mods or not mods <= mapa.keys() or len(mods) != len(partes) - 1:
        raise ValueError("Añade Ctrl, Alt, Shift o Super a la combinación.")
    tecla = partes[-1].upper()
    numero = re.fullmatch(r"(?:NUMPAD\s*|KP_)([0-9])", tecla)
    if numero:
        valor = TECLADO_NUMERICO | ord(numero[1])
    elif tecla in ("SPACE", "ESPACIO"):
        valor = 32
    elif re.fullmatch(r"[A-Z0-9]", tecla):
        valor = ord(tecla)
    elif re.fullmatch(r"F(?:[1-9]|[12][0-9]|3[0-5])", tecla):
        valor = 0x0100002F + int(tecla[1:])
    else:
        raise ValueError("Usa una letra, un número, NumPad 0–9 o F1–F35.")
    return valor | sum(mapa[mod] for mod in mods)


def activos(accion=ACCION):
    return pedir("shortcutKeys", "(as)", accion)[0]


def nombre_activo(teclas):
    if not teclas:
        return "Sin atajo"
    nombres = []
    for (secuencia,) in teclas:
        for combo in secuencia:
            if not combo:
                continue
            mods = [nombre for nombre, bit in MODIFICADORES.items() if combo & bit]
            tecla = combo & 0x01FFFFFF
            if 0x01000030 <= tecla <= 0x01000052:
                mods.append(f"F{tecla - 0x0100002F}")
            elif tecla == 32:
                mods.append("Espacio")
            elif 33 <= tecla <= 126:
                mods.append(("NumPad " if combo & TECLADO_NUMERICO else "") + chr(tecla))
            else:
                mods.append("Otra tecla")
            nombres.append("+".join(mods))
    return ", ".join(nombres)


def asignar(texto, accion=ACCION):
    teclas = []
    if texto.strip():
        valor = codigo(texto)
        if secuencias(activos(accion)) == [(valor,)]:
            return
        tecla = ([valor, 0, 0, 0],)
        if not pedir("globalShortcutAvailable", "((ai)s)", tecla, accion[0])[0]:
            raise ValueError("Esa combinación ya está en uso. Elige otra.")
        teclas.append(tecla)
    establecer(accion, teclas)


def establecer(accion, teclas):
    pedir("setForeignShortcutKeys", "(asa(ai))", accion, teclas)
    if set(secuencias(activos(accion))) != set(secuencias(teclas)):
        raise ValueError("KDE no aplicó el cambio de atajo.")
    if accion[:2] == ACCION[:2]:
        from perfiles import avisar_widgets
        avisar_widgets("AtajoPerfilCambiado", nombre_activo(teclas) if secuencias(teclas) else "")



def integrar_lanzador(accion, anterior):
    """Transfiere al identificador de la aplicación las combinaciones ya activas."""
    registrar(accion)
    antiguas = activos(anterior)
    if not secuencias(antiguas):
        return
    actuales = activos(accion)
    nuevas = actuales + [tecla for tecla in antiguas if tecla not in actuales]
    establecer(anterior, [])
    try:
        establecer(accion, nuevas)
    except (GLib.Error, ValueError):
        try:
            establecer(accion, actuales)
        finally:
            establecer(anterior, antiguas)
        raise


def secuencias(teclas):
    return [tuple(k for k in seq if k) for (seq,) in teclas if any(seq)]


def lanzamientos_kde(ruta, identificadores):
    """Lee los atajos de lanzamiento activos por identificador de archivo desktop."""
    permitidos = set(identificadores)
    resultado = {}
    componente = None
    try:
        lineas = ruta.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        return resultado
    for linea in lineas:
        if linea.startswith("["):
            seccion = re.fullmatch(r"\[(services)\]\[([^\[\]]+)\]", linea)
            anterior = re.fullmatch(r"\[([^\[\]]+\.desktop)\]", linea)
            componente = seccion[2] if seccion else anterior[1] if anterior else None
            es_servicio = seccion is not None
        elif componente in permitidos and linea.startswith("_launch="):
            valor = linea.partition("=")[2]
            if not es_servicio:
                valor = valor.split(",", 1)[0]
            teclas = [tecla.strip() for tecla in valor.split(r"\t") if tecla.strip().casefold() not in ("", "none")]
            if teclas:
                resultado.setdefault(componente, []).extend(teclas)
    return {clave: tuple(dict.fromkeys(teclas)) for clave, teclas in resultado.items()}
