"""Controles de sesión para el widget de Plasma."""
import json
import os
import re
import shutil
import subprocess
from time import sleep


def ejecutar(*orden):
    return subprocess.run(orden, check=True, text=True, capture_output=True, timeout=12,
                          env={**os.environ, "LC_ALL": "C"}).stdout.strip()


def leer(*orden):
    try:
        return ejecutar(*orden)
    except (OSError, subprocess.SubprocessError):
        return ""


def brillo():
    valores = leer("brightnessctl", "-m", "-c", "backlight", "info").split(",")
    if len(valores) >= 4 and valores[3].endswith("%"):
        return int(valores[3][:-1])
    servicio = "org.kde.Solid.PowerManagement"
    ruta = "/org/kde/Solid/PowerManagement/Actions/BrightnessControl"
    interfaz = servicio + ".Actions.BrightnessControl"
    actual = leer("qdbus6", servicio, ruta, interfaz + ".brightness")
    maximo = leer("qdbus6", servicio, ruta, interfaz + ".brightnessMax")
    if actual.isdecimal() and maximo.isdecimal() and int(maximo):
        return round(100 * int(actual) / int(maximo))
    return None


def luz_nocturna():
    from gi.repository import Gio, GLib
    from widget_datos import llamada

    try:
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        return llamada(bus, "org.kde.KWin.NightLight", "/org/kde/KWin/NightLight",
                       "org.freedesktop.DBus.Properties", "Get",
                       GLib.Variant("(ss)", ("org.kde.KWin.NightLight", "enabled")))
    except GLib.Error:
        return None


def cambiar_luz_nocturna(activar):
    ejecutar("kwriteconfig6", "--notify", "--file", "kwinrc", "--group", "NightColor",
             "--key", "Active", "--type", "bool", "true" if activar else "false")
    for _ in range(5):
        if luz_nocturna() is activar:
            return
        sleep(0.12)
    raise ValueError("KWin no confirmó el cambio de Luz nocturna. Revisa sus ajustes.")


def estado():
    from gi.repository import Gio, GLib
    from widget_datos import baterias, carga_equipo
    wifi = leer("nmcli", "radio", "wifi")
    bt = re.search(r"^\s*Powered: (yes|no)$", leer("bluetoothctl", "show"), re.M)
    audio = leer("wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@")
    volumen = re.search(r"Volume: (\d+(?:\.\d+)?)", audio)
    microfono = leer("wpctl", "get-volume", "@DEFAULT_AUDIO_SOURCE@")
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        try:
            bateria = carga_equipo(bus)
        except GLib.Error:
            bateria = None
        if bateria is None:
            bateria = baterias().get("equipo")
    except (GLib.Error, OSError):
        bateria = None
    perfiles = re.findall(r"^\s*(\*?)\s*(power-saver|balanced|performance):",
                          leer("powerprofilesctl", "list"), re.M)
    activo = next((nombre for marca, nombre in perfiles if marca), "")
    return {"wifi": wifi == "enabled" if wifi in ("enabled", "disabled") else None,
            "bluetooth": bt[1] == "yes" if bt else None,
            "redWifi": red_wifi_activa() if wifi == "enabled" else "",
            "audifonosBluetooth": audifonos_bluetooth() if bt and bt[1] == "yes" else "",
            "noche": luz_nocturna(),
            "volumen": round(float(volumen[1]) * 100) if volumen else None,
            "salidaSilenciada": "[MUTED]" in audio if volumen else None,
            "microfono": "[MUTED]" in microfono if microfono else None,
            "brillo": brillo(), "energia": activo or leer("powerprofilesctl", "get"),
            "perfiles": [nombre for _, nombre in perfiles],
            "bateria": bateria}


def redes(actualizar=False):
    salida = ejecutar("nmcli", "-t", "--escape", "yes", "-f", "IN-USE,BSSID,SSID,SIGNAL,SECURITY",
                      "device", "wifi", "list", "--rescan", "yes" if actualizar else "no")
    lista = []
    for linea in salida.splitlines():
        campos = [re.sub(r"\\(.)", r"\1", campo) for campo in re.split(r"(?<!\\)(?:\\\\)*:", linea)]
        if len(campos) == 5 and campos[2]:
            intensidad = int(campos[3]) if campos[3].isdecimal() else None
            nivel = min(100, ((intensidad + 19) // 20) * 20) if intensidad is not None else 0
            lista.append({"id": campos[1], "nombre": campos[2],
                          "detalle": (f"{intensidad}% · " if intensidad is not None else "") + (campos[4] or "Abierta"),
                          "intensidad": intensidad, "seguridad": campos[4] or "Abierta", "icono": f"network-wireless-connected-{nivel:02}",
                          "activo": campos[0] == "*"})
    return sorted(lista, key=lambda red: (not red["activo"], -(red["intensidad"] or 0)))


def red_wifi_activa():
    try:
        return next((red["nombre"] for red in redes() if red["activo"]), "")
    except (OSError, subprocess.SubprocessError):
        return ""


ICONOS_BLUETOOTH = {
    "audio-headphones": "audio-headphones", "audio-headset": "audio-headset",
    "audio-card": "audio-speakers", "audio-speakers": "audio-speakers",
    "input-mouse": "input-mouse", "input-keyboard": "input-keyboard",
    "input-gaming": "input-gaming", "phone": "phone", "computer": "computer",
    "camera-photo": "camera-photo", "printer": "printer", "video-display": "video-display",
}


def icono_bluetooth(info, nombre=""):
    encontrado = re.search(r"^\s*Icon: ([\w-]+)$", info, re.M)
    tipo = encontrado[1] if encontrado else ""
    if tipo in ICONOS_BLUETOOTH and tipo != "audio-card":
        return ICONOS_BLUETOOTH[tipo]
    if re.search(r"\bjbl\s+tune\b|headphones?|headset|earbuds?|auriculares|aud[ií]fonos", nombre, re.I):
        return "audio-headphones"
    return ICONOS_BLUETOOTH.get(tipo, "bluetooth-active")


def audifonos_bluetooth():
    for linea in leer("bluetoothctl", "devices", "Connected").splitlines():
        partes = linea.split(maxsplit=2)
        if len(partes) == 3 and partes[0] == "Device":
            info = leer("bluetoothctl", "info", partes[1])
            if icono_bluetooth(info, partes[2]) in ("audio-headphones", "audio-headset"):
                return partes[2]
    return ""


def seleccionar_salida_bluetooth(direccion):
    info = leer("bluetoothctl", "info", direccion)
    if not re.search(r"0000(?:1108|110b|111e)-0000-1000-8000-00805f9b34fb", info, re.I):
        return
    prefijo = "bluez_output." + direccion.upper().replace(":", "_")
    for intento in range(8):
        for linea in leer("pactl", "list", "short", "sinks").splitlines():
            campos = linea.split("\t")
            if len(campos) > 1 and (campos[1] == prefijo or campos[1].startswith(prefijo + ".")):
                ejecutar("pactl", "set-default-sink", campos[1])
                return
        if intento < 7:
            sleep(0.25)


def bluetooth():
    from gi.repository import GLib
    from widget_datos import baterias

    try:
        cargas = {item["direccion"]: item["carga"] for item in baterias()["dispositivos"]
                  if item.get("direccion") and not item.get("principal")}
    except (GLib.Error, OSError):
        cargas = {}
    lista = []
    for linea in ejecutar("bluetoothctl", "devices").splitlines():
        partes = linea.split(maxsplit=2)
        if len(partes) == 3 and partes[0] == "Device":
            info = leer("bluetoothctl", "info", partes[1])
            activo = bool(re.search(r"^\s*Connected: yes$", info, re.M))
            carga = cargas.get(partes[1].lower()) if activo else None
            medida = re.search(r"^\s*Battery Percentage: (0x[0-9a-f]+|[0-9]+)(?:\s+\(([0-9]+)\))?", info, re.I | re.M)
            if activo and carga is None and medida:
                valor = medida[2] or medida[1]
                porcentaje = int(valor, 16 if valor.lower().startswith("0x") else 10)
                carga = porcentaje if 0 <= porcentaje <= 100 else None
            lista.append({"id": partes[1], "nombre": partes[2], "activo": activo,
                          "icono": icono_bluetooth(info, partes[2]), "bateria": carga})
    return lista


ACCIONES_UTILES = (
    (re.compile(r"record|grabaci[oó]n|grabar"), "media-record"),
    (re.compile(r"screenshot|captura"), "camera-photo"),
    (re.compile(r"scan|escane"), "scanner"),
    (re.compile(r"new[-_ ]?note|nueva nota|create[-_ ]?note"), "document-new"),
    (re.compile(r"private|incognito|privad[ao]|inc[oó]gnito"), "view-private"),
)


def descubrir_acciones():
    from gi.repository import Gio

    lista = []
    for app in Gio.AppInfo.get_all():
        identificador = app.get_id()
        if not identificador or not app.should_show() or not hasattr(app, "list_actions"):
            continue
        for accion in app.list_actions():
            if identificador == "org.kde.spectacle.desktop" and accion == "RecordRegion":
                continue
            nombre = app.get_action_name(accion)
            if not nombre:
                continue
            etiqueta = (accion + " " + nombre).casefold()
            icono = next((icono for patron, icono in ACCIONES_UTILES if patron.search(etiqueta)), None)
            if icono:
                lista.append({"id": f"d:{identificador}:{accion}", "nombre": nombre,
                              "detalle": app.get_display_name(), "icono": icono})
    return sorted(lista, key=lambda fila: (fila["detalle"].casefold(), fila["nombre"].casefold()))


def accesos_directos():
    from widget_datos import lanzador_escritorio

    acciones = [
        ("c:wifi", "Wi-Fi", "Activar o desactivar", "network-wireless", "nmcli"),
        ("c:bluetooth", "Bluetooth", "Activar o desactivar", "bluetooth-active", "bluetoothctl"),
        ("c:silencio", "No molestar", "Activar o desactivar", "notifications-disabled", None),
        ("c:noche", "Luz nocturna", "Activar o desactivar", "redshift-status-on", "kwriteconfig6"),
        ("c:microfono", "Silenciar micrófono", "Audio", "microphone-sensitivity-muted", "wpctl"),
        ("c:audio", "Cambiar salida de audio", "Audio", "audio-speakers", "pactl"),
        ("c:energia", "Cambiar modo de energía", "Energía", "battery", "powerprofilesctl"),
        ("s:captura", "Capturar pantalla", "Spectacle", "spectacle", "spectacle"),
        ("s:lens", "Buscar por imagen", "Google Lens", "image-x-generic", "xdg-open"),
        ("s:bloquear", "Bloquear pantalla", "Sesión", "system-lock-screen", "loginctl"),
    ]
    lista = [{"id": clave, "nombre": nombre, "detalle": detalle, "icono": icono}
             for clave, nombre, detalle, icono, comando in acciones if comando is None or shutil.which(comando)]
    spectacle = lanzador_escritorio("org.kde.spectacle.desktop")
    if spectacle is not None and "RecordRegion" in spectacle.list_actions():
        lista.insert(8, {"id": "s:grabar", "nombre": "Grabar región de pantalla",
                         "detalle": "Spectacle", "icono": "media-record"})
    return lista + descubrir_acciones()


SISTEMA = {
    "ajustes": ("Preferencias del sistema", ["systemsettings"]),
    "red": ("Redes", ["kcmshell6", "kcm_networkmanagement"]),
    "bt": ("Bluetooth", ["kcmshell6", "kcm_bluetooth"]),
    "audio": ("Audio", ["kcmshell6", "kcm_pulseaudio"]),
    "luz": ("Luz nocturna", ["kcmshell6", "kcm_nightlight"]),
    "energia": ("Energía", ["kcmshell6", "kcm_powerdevilprofilesconfig"]),
    "notificaciones": ("Notificaciones", ["kcmshell6", "kcm_notifications"]),
    "lens": ("Google Lens", ["xdg-open", "https://www.google.com/imghp"]),
    "captura": ("Captura de pantalla", ["spectacle"]),
    "bloquear": ("Bloquear pantalla", ["loginctl", "lock-session"]),
    "suspender": ("Suspender", ["systemctl", "suspend"]),
    "reiniciar": ("Reiniciar", ["systemctl", "reboot"]),
    "apagar": ("Apagar", ["systemctl", "poweroff"]),
}


def operar(accion="estado", valor=""):
    from gi.repository import GLib
    from widget_datos import lanzador_escritorio
    try:
        if accion == "estado":
            return estado()
        if accion == "redes":
            return {"lista": redes(valor == "actualizar"), "vista": accion, "escaneada": valor == "actualizar"}
        if accion == "dispositivos":
            if valor == "actualizar":
                leer("bluetoothctl", "--timeout", "4", "scan", "on")
            return {"lista": bluetooth(), "vista": accion, "escaneada": valor == "actualizar"}
        if accion == "audio":
            salida = ejecutar("pactl", "get-default-sink")
            dispositivos = json.loads(ejecutar("pactl", "--format=json", "list", "sinks"))
            return {"lista": [{"id": str(item["index"]), "nombre": item["description"],
                               "activo": item["name"] == salida} for item in dispositivos], "vista": accion}
        if accion == "atajos":
            return {"lista": accesos_directos(), "vista": accion}
        if accion in ("wifi", "bluetooth", "noche") and valor in ("on", "off"):
            if accion == "wifi":
                ejecutar("nmcli", "radio", "wifi", valor)
            elif accion == "bluetooth":
                ejecutar("bluetoothctl", "power", valor)
            else:
                cambiar_luz_nocturna(valor == "on")
        elif accion in ("volumen", "brillo") and valor.isdecimal() and 0 <= int(valor) <= 100:
            if accion == "volumen":
                ejecutar("wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", valor + "%")
            elif shutil.which("brightnessctl"):
                ejecutar("brightnessctl", "-q", "-c", "backlight", "set", str(max(1, int(valor))) + "%")
            else:
                servicio = "org.kde.Solid.PowerManagement"
                ruta = "/org/kde/Solid/PowerManagement/Actions/BrightnessControl"
                interfaz = servicio + ".Actions.BrightnessControl"
                maximo = int(ejecutar("qdbus6", servicio, ruta, interfaz + ".brightnessMax"))
                ejecutar("qdbus6", servicio, ruta, interfaz + ".setBrightness", str(max(1, round(maximo * int(valor) / 100))))
            return {"nivel": accion, "solicitado": int(valor),
                    "medida": max(1, int(valor)) if accion == "brillo" else int(valor)}
        elif accion == "silenciar-salida":
            ejecutar("wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle")
        elif accion == "microfono":
            ejecutar("wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle")
        elif accion == "salida" and valor.isdecimal():
            ejecutar("pactl", "set-default-sink", valor)
        elif accion == "energia" and valor in ("power-saver", "balanced", "performance"):
            ejecutar("powerprofilesctl", "set", valor)
        elif accion in ("conectar", "conectar-bt", "desconectar-bt") and re.fullmatch(r"(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}", valor):
            if accion == "conectar":
                ejecutar("nmcli", "--wait", "9", "device", "wifi", "connect", valor)
            else:
                ejecutar("bluetoothctl", "connect" if accion == "conectar-bt" else "disconnect", valor)
                if accion == "conectar-bt":
                    seleccionar_salida_bluetooth(valor)
        elif accion == "sistema" and valor == "grabar":
            app = lanzador_escritorio("org.kde.spectacle.desktop")
            if app is None or "RecordRegion" not in app.list_actions():
                raise ValueError("La grabación de pantalla no está disponible en Spectacle.")
            app.launch_action("RecordRegion", None)
            return {"hecho": True}
        elif accion == "sistema" and valor in SISTEMA:
            subprocess.Popen(SISTEMA[valor][1], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
            return {"hecho": True}
        elif accion == "accion-app":
            identificador, separador, nombre = valor.partition(":")
            app = lanzador_escritorio(identificador) if re.fullmatch(r"[\w.-]+\.desktop", identificador) else None
            if not separador or app is None or nombre not in app.list_actions():
                raise ValueError("La aplicación ya no ofrece esta acción.")
            app.launch_action(nombre, None)
            return {"hecho": True}
        elif accion == "abrir" and re.fullmatch(r"[\w.-]+\.desktop", valor):
            app = lanzador_escritorio(valor)
            if not app or not app.launch([], None):
                raise ValueError("No se pudo abrir la aplicación.")
            return {"hecho": True}
        else:
            raise ValueError("Acción no disponible.")
        return estado()
    except (OSError, ValueError, subprocess.SubprocessError, GLib.Error) as error:
        detalle = getattr(error, "stderr", None)
        return {"error": (detalle.strip() if detalle else str(error))[:250]}
