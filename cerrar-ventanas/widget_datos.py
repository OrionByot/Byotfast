"""Datos del sistema que consumen los widgets de Byotfast."""
from hashlib import sha256
import json
import os
import re
import shutil
from pathlib import Path
from tempfile import NamedTemporaryFile
from time import time
from urllib.parse import urlencode, urlsplit
from urllib.request import url2pathname, urlopen


def llamada(bus, servicio, ruta, interfaz, metodo, argumentos=None):
    from gi.repository import Gio

    return bus.call_sync(
        servicio, ruta, interfaz, metodo, argumentos, None,
        Gio.DBusCallFlags.NO_AUTO_START, 1200, None,
    ).unpack()[0]


def propiedades(bus, servicio, ruta, interfaz):
    from gi.repository import GLib

    return llamada(bus, servicio, ruta, "org.freedesktop.DBus.Properties", "GetAll",
                   GLib.Variant("(s)", (interfaz,)))


def carga_equipo(bus):
    servicio = "org.freedesktop.UPower"
    pantalla = propiedades(bus, servicio, "/org/freedesktop/UPower/devices/DisplayDevice", servicio + ".Device")
    if pantalla.get("IsPresent") and 0 <= pantalla.get("Percentage", -1) <= 100:
        return round(pantalla["Percentage"])
    return None


def baterias():
    from gi.repository import Gio, GLib

    bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
    servicio = "org.freedesktop.UPower"
    dispositivos = []
    direcciones = set()
    try:
        rutas = llamada(bus, servicio, "/org/freedesktop/UPower", servicio, "EnumerateDevices")
    except GLib.Error:
        rutas = []
    for ruta in rutas:
        try:
            datos = propiedades(bus, servicio, ruta, servicio + ".Device")
        except GLib.Error:
            continue
        tipo = datos.get("Type", 0)
        carga = datos.get("Percentage")
        if tipo in (0, 1) or not datos.get("IsPresent") or carga is None or not 0 <= carga <= 100:
            continue
        principal = bool(datos.get("PowerSupply"))
        nombre = datos.get("Model") or ("Batería del equipo" if principal else "Dispositivo")
        estado = datos.get("State", 0)
        nativa = str(datos.get("NativePath", ""))
        direccion = re.search(r"(?:[0-9a-f]{2}[:_]){5}[0-9a-f]{2}",
                              f"{datos.get('Serial', '')} {ruta} {nativa}", re.I)
        dispositivos.append({
            "direccion": direccion[0].lower().replace("_", ":") if direccion else "",
            "nombre": nombre, "carga": round(carga), "principal": principal,
            "estado": {1: "Cargando", 2: "Descargando", 4: "Carga completa"}.get(estado, ""),
            "segundos": datos.get("TimeToFull" if estado == 1 else "TimeToEmpty", 0),
            "vatios": round(datos.get("EnergyRate", 0), 1),
        })
        serial = str(datos.get("Serial", "")).lower().replace(":", "_")
        if serial:
            direcciones.add(serial)
        direcciones.update(parte[4:21].lower() for parte in ruta.split("/") if parte.startswith("dev_"))
        nativa = str(datos.get("NativePath", "")).lower().replace(":", "_")
        direcciones.update(parte[4:21] for parte in nativa.split("/") if parte.startswith("dev_"))
    try:
        bluetooth = llamada(bus, "org.bluez", "/", "org.freedesktop.DBus.ObjectManager", "GetManagedObjects")
    except GLib.Error:
        bluetooth = {}
    busquedas = {item["nombre"].casefold() for item in dispositivos if not item["principal"]}
    for interfaces in bluetooth.values():
        equipo = interfaces.get("org.bluez.Device1", {})
        carga = interfaces.get("org.bluez.Battery1", {}).get("Percentage")
        nombre = equipo.get("Alias") or equipo.get("Name") or "Dispositivo Bluetooth"
        direccion = equipo.get("Address", "").lower().replace(":", "_")
        if equipo.get("Connected") and carga is not None and 0 <= carga <= 100:
            if direccion not in direcciones and nombre.casefold() not in busquedas:
                dispositivos.append({"nombre": nombre, "carga": carga, "estado": "Bluetooth",
                                     "direccion": direccion.replace("_", ":")})
    dispositivos.sort(key=lambda item: (not item.get("principal"), item["nombre"].casefold()))
    equipo = next((d["carga"] for d in dispositivos if d.get("principal")), None)
    try:
        carga = carga_equipo(bus)
        if carga is not None:
            equipo = carga
    except GLib.Error:
        pass
    return {"dispositivos": dispositivos, "equipo": equipo}


def portada_guardada(url):
    if not isinstance(url, str) or not url or len(url) > 8192:
        return ""
    try:
        partes = urlsplit(url)
    except ValueError:
        return ""
    if partes.scheme not in ("file", "https", "http") or (partes.scheme == "file" and partes.netloc not in ("", "localhost")):
        return ""
    carpeta = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "byotfast" / "portadas"
    clave = sha256(url.encode()).hexdigest()
    limite = 2 * 1024 * 1024
    try:
        existentes = list(carpeta.glob(clave + ".*"))
        if existentes:
            return existentes[0].as_uri()
        if partes.scheme == "file":
            ruta = Path(url2pathname(partes.path))
            if not ruta.is_file():
                return ""
            with ruta.open("rb") as origen:
                datos = origen.read(limite + 1)
        else:
            with urlopen(url, timeout=2) as origen:
                datos = origen.read(limite + 1)
        formatos = ((b"\x89PNG\r\n\x1a\n", ".png"), (b"\xff\xd8\xff", ".jpg"),
                    (b"GIF8", ".gif"))
        extension = next((ext for marca, ext in formatos if datos.startswith(marca)), "")
        if datos.startswith(b"RIFF") and datos[8:12] == b"WEBP":
            extension = ".webp"
        if not extension or len(datos) > limite:
            return ""
        carpeta.mkdir(parents=True, exist_ok=True)
        archivo = carpeta / (clave + extension)
        with NamedTemporaryFile(dir=carpeta, delete=False) as temporal:
            try:
                temporal.write(datos)
                temporal.close()
                os.replace(temporal.name, archivo)
            finally:
                Path(temporal.name).unlink(missing_ok=True)
        extensiones = {".png", ".jpg", ".gif", ".webp"}
        viejas = sorted((item for item in carpeta.iterdir() if item.suffix in extensiones and item != archivo),
                        key=lambda item: item.stat().st_mtime, reverse=True)
        for vieja in viejas[23:]:
            vieja.unlink(missing_ok=True)
        return archivo.as_uri()
    except (OSError, ValueError):
        return ""


def id_escritorio(nombre):
    if not isinstance(nombre, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,199}", nombre):
        return ""
    return nombre if nombre.endswith(".desktop") else nombre + ".desktop"


def lanzador_escritorio(identificador):
    try:
        from gi.repository import GioUnix
        desktop_app = GioUnix.DesktopAppInfo
    except (ImportError, ValueError, AttributeError):
        from gi.repository import Gio
        desktop_app = Gio.DesktopAppInfo
    try:
        return desktop_app.new(identificador)
    except TypeError:
        # PyGObject convierte un lanzador inexistente (NULL) en TypeError.
        return None


def abrir_reproductor(aplicacion):
    if not id_escritorio(aplicacion):
        return {"error": "No se identificó el lanzador del reproductor."}
    lanzador = lanzador_escritorio(id_escritorio(aplicacion))
    if not lanzador:
        return {"error": "No se encontró el reproductor instalado."}
    return {"abriendo": True} if lanzador.launch([], None) else {"error": "No se pudo abrir el reproductor."}


def musica(accion=None, destino=None, aplicacion=None):
    from gi.repository import Gio, GLib

    if accion == "Abrir":
        return abrir_reproductor(aplicacion)

    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    nombres = llamada(bus, "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "ListNames")
    ruta = "/org/mpris/MediaPlayer2"
    interfaz = "org.mpris.MediaPlayer2.Player"
    if accion == "Mostrar":
        if destino and destino.startswith("org.mpris.MediaPlayer2.") and destino in nombres:
            try:
                bus.call_sync(destino, ruta, "org.mpris.MediaPlayer2", "Raise", None, None,
                              Gio.DBusCallFlags.NO_AUTO_START, 1200, None)
                return {"comandoAplicado": True}
            except GLib.Error:
                pass
        return abrir_reproductor(aplicacion)
    if accion:
        permitidas = {"Anterior": "Previous", "Reproducir": "PlayPause", "Siguiente": "Next"}
        if accion not in permitidas or not destino or not destino.startswith("org.mpris.MediaPlayer2."):
            return {}
        if destino not in nombres:
            return abrir_reproductor(aplicacion) if accion == "Reproducir" else {}
        bus.call_sync(destino, ruta, interfaz, permitidas[accion], None, None,
                      Gio.DBusCallFlags.NO_AUTO_START, 1200, None)
        return {"comandoAplicado": True}
    jugadores = []
    for nombre in nombres:
        if not nombre.startswith("org.mpris.MediaPlayer2."):
            continue
        try:
            datos = propiedades(bus, nombre, ruta, interfaz)
            reproductor = propiedades(bus, nombre, ruta, "org.mpris.MediaPlayer2")
        except GLib.Error:
            continue
        tema = datos.get("Metadata", {})
        portada = tema.get("mpris:artUrl") or ""
        nombre_bus = nombre.split(".")[3]
        candidatos = [reproductor.get("DesktopEntry", ""), nombre_bus, nombre_bus + "-launcher"]
        if nombre_bus == "spotify":
            candidatos.append("com.spotify.Client")
        lanzador = next((identificador for candidato in candidatos
                         if (identificador := id_escritorio(candidato)) and lanzador_escritorio(identificador)), "")
        jugadores.append({
            "destino": nombre, "aplicacion": lanzador, "reproductor": reproductor.get("Identity") or nombre_bus,
            "titulo": tema.get("xesam:title") or "",
            "artista": " · ".join(tema.get("xesam:artist") or []),
            "album": tema.get("xesam:album", ""),
            "pista": tema.get("mpris:trackid"),
            "listaDisponible": bool(reproductor.get("HasTrackList")),
            "duracion": tema.get("mpris:length"),
            "posicion": datos.get("Position"),
            "velocidad": datos.get("Rate", 1),
            "medidoEn": round(time() * 1000),
            "portada": portada if portada.startswith(("file://", "https://", "http://")) else "",
            "sonando": datos.get("PlaybackStatus") == "Playing",
            "puedeReproducir": bool(datos.get("CanPlay") or datos.get("CanPause")),
            "puedeAnterior": bool(datos.get("CanGoPrevious")), "puedeSiguiente": bool(datos.get("CanGoNext")),
        })
    elegido = next((j for j in jugadores if j["sonando"]), next(iter(jugadores), {}))
    if elegido.get("duracion") and elegido["posicion"] is None:
        try:
            elegido["posicion"] = llamada(
                bus, elegido["destino"], ruta, "org.freedesktop.DBus.Properties", "Get",
                GLib.Variant("(ss)", (interfaz, "Position")),
            )
            elegido["medidoEn"] = round(time() * 1000)
        except GLib.Error:
            pass
    return elegido


def portada_siguiente(destino, pista):
    from gi.repository import Gio, GLib

    if not destino.startswith("org.mpris.MediaPlayer2."):
        return {}
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    ruta = "/org/mpris/MediaPlayer2"
    interfaz = "org.mpris.MediaPlayer2.TrackList"
    pistas = llamada(bus, destino, ruta, "org.freedesktop.DBus.Properties", "Get",
                    GLib.Variant("(ss)", (interfaz, "Tracks")))
    if pista not in pistas:
        return {}
    siguientes = pistas[pistas.index(pista) + 1:][:1]
    if siguientes:
        temas = llamada(bus, destino, ruta, interfaz, "GetTracksMetadata",
                        GLib.Variant("(ao)", (siguientes,)))
        if temas and temas[0].get("mpris:artUrl"):
            portada_guardada(temas[0]["mpris:artUrl"])
    return {}


def discos():
    from limpieza import mostrar_bytes

    montajes = {}
    tipos = {"ext2", "ext3", "ext4", "btrfs", "xfs", "f2fs", "zfs", "ntfs", "ntfs3",
             "exfat", "vfat", "fuseblk", "bcachefs", "bfs", "udf", "iso9660"}
    for linea in Path("/proc/self/mountinfo").read_text().splitlines():
        origen, _, sistema = linea.partition(" - ")
        columnas = origen.split()
        if len(columnas) < 5 or sistema.split()[0] not in tipos:
            continue
        ruta = (columnas[4].replace(r"\040", " ").replace(r"\011", "\t")
                .replace(r"\012", "\n").replace(r"\134", "\\"))
        montajes[ruta] = columnas[2]
    montajes.setdefault("/", "")
    unidades = []
    vistos = set()
    for ruta in sorted(montajes, key=lambda r: (r != "/", r != "/home", not r.startswith(("/mnt/", "/media/", "/run/media/")), r)):
        clave = montajes[ruta]
        if clave and clave in vistos:
            continue
        try:
            uso = shutil.disk_usage(ruta)
        except OSError:
            continue
        vistos.add(clave)
        unidades.append({"ruta": ruta, "url": Path(ruta).as_uri(), "libre": mostrar_bytes(uso.free),
                        "total": mostrar_bytes(uso.total), "uso": round(100 * uso.used / max(1, uso.total))})
    return {"unidades": unidades}


def api_json(url, parametros):
    with urlopen(url + ("?" + urlencode(parametros) if parametros else ""), timeout=7) as respuesta:
        return json.load(respuesta)


def buscar_ciudad(nombre):
    if not 2 <= len(nombre.strip()) <= 100:
        return {"error": "Escribe el nombre de una ciudad."}
    datos = api_json("https://geocoding-api.open-meteo.com/v1/search",
                     {"name": nombre.strip(), "count": 8, "language": "es"})
    return {"ciudades": [{
        "nombre": ", ".join(dict.fromkeys(filter(None, (item.get("name"), item.get("admin1"), item.get("country"))))),
        "latitud": item["latitude"], "longitud": item["longitude"],
        "pais": item.get("country_code", ""),
    } for item in datos.get("results", [])]}


def clima(latitud, longitud):
    latitud, longitud = float(latitud), float(longitud)
    if not (-90 <= latitud <= 90 and -180 <= longitud <= 180):
        raise ValueError("Coordenadas no válidas.")
    datos = api_json("https://api.open-meteo.com/v1/forecast", {
        "latitude": latitud, "longitude": longitud, "timezone": "auto", "forecast_days": 2,
        "current": "temperature_2m,weather_code", "hourly": "temperature_2m,precipitation_probability",
        "daily": "temperature_2m_max,temperature_2m_min",
    })
    actual, horas, diario = datos["current"], datos["hourly"], datos["daily"]
    codigo = actual["weather_code"]
    estado = ("Despejado" if codigo == 0 else "Nublado" if codigo < 4 else "Niebla" if codigo < 50
              else "Lluvia" if codigo < 70 or 80 <= codigo < 85 else "Nieve" if codigo < 95 else "Tormenta")
    icono = {"Despejado": "weather-clear", "Nublado": "weather-clouds", "Niebla": "weather-fog",
             "Lluvia": "weather-showers", "Nieve": "weather-snow", "Tormenta": "weather-storm"}[estado]
    return {"temperatura": round(actual["temperature_2m"]), "estado": estado, "icono": icono + "-symbolic",
            "maxima": round(diario["temperature_2m_max"][0]), "minima": round(diario["temperature_2m_min"][0]),
            "horas": [{"hora": hora[-5:], "temperatura": round(temperatura), "lluvia": lluvia}
                      for hora, temperatura, lluvia in zip(horas["time"], horas["temperature_2m"], horas["precipitation_probability"])
                      if hora >= actual["time"] and temperatura is not None][:8]}

def ubicacion():
    from perfiles import CARPETA
    try:
        return json.loads((CARPETA / "ubicacion.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def guardar_ubicacion(ciudad):
    from perfiles import CARPETA, avisar_widgets, guardar
    if not re.fullmatch(r"[A-Z]{2}", ciudad.get("pais", "")):
        raise ValueError("Selecciona una ciudad de los resultados.")
    guardar(ciudad, CARPETA / "ubicacion.json")
    avisar_widgets("UbicacionCambiada", ciudad)
    return ciudad


def clima_ubicacion(anterior=""):
    from widgets import muestra_compartida
    ciudad = ubicacion()
    if not ciudad and anterior:
        ciudad = json.loads(anterior)
        if not ciudad.get("pais") and ciudad.get("nombre"):
            try:
                opciones = buscar_ciudad(ciudad["nombre"].split(",", 1)[0]).get("ciudades", [])
            except (OSError, ValueError, KeyError):
                opciones = []
            ciudad = next((opcion for opcion in opciones
                           if abs(opcion["latitud"] - ciudad["latitud"]) < 0.02
                           and abs(opcion["longitud"] - ciudad["longitud"]) < 0.02), ciudad)
        if ciudad.get("pais"):
            guardar_ubicacion(ciudad)
    if "latitud" not in ciudad:
        return {}
    latitud, longitud = ciudad["latitud"], ciudad["longitud"]
    try:
        pronostico = muestra_compartida(["clima", latitud, longitud], 840, lambda: clima(latitud, longitud))
    except (OSError, ValueError, KeyError):
        pronostico = {}
    return {"ciudad": ciudad, **pronostico}


def feriados(anio):
    from perfiles import guardar
    ciudad = ubicacion()
    pais = ciudad.get("pais", "")
    if not re.fullmatch(r"[A-Z]{2}", pais) or not re.fullmatch(r"[0-9]{4}", anio):
        return {}
    cache = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "byotfast" / f"feriados-{pais}-{anio}.json"
    guardados = None
    try:
        guardados = json.loads(cache.read_text(encoding="utf-8"))
        if time() - cache.stat().st_mtime < 86400 * 7:
            return guardados
    except (OSError, ValueError):
        pass
    try:
        respuesta = api_json(f"https://date.nager.at/api/v3/PublicHolidays/{anio}/{pais}", {})
        fechas = {}
        for aviso in respuesta:
            if aviso.get("global") and "Public" in aviso.get("types", []):
                fechas.setdefault(aviso["date"], []).append(aviso["localName"])
        resultado = {"fechas": fechas, "pais": pais, "anio": int(anio)}
    except (OSError, ValueError, KeyError, TypeError):
        return guardados or {"noDisponibles": True, "pais": pais}
    guardar(resultado, cache)
    return resultado
