import json
import os
import re
import stat
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import quote

from rendimiento import mostrar_bytes

DIAS = 7
DIRECTORIOS = (Path("/tmp"), Path("/var/tmp"))
OPCIONES = ("temporales", "papelera", "vista_previa")


@dataclass(frozen=True)
class ElementoPapelera:
    url: str
    nombre: str
    identidad: tuple
    bytes: int
    incompleto: bool


@dataclass(frozen=True)
class ArchivoTemporal:
    ruta: Path
    tamanio: int
    fecha: float
    motivo: str | None
    identidad: tuple[int, int, int]


def leer_opciones(ruta):
    try:
        datos = json.loads(ruta.read_text(encoding="utf-8"))
    except FileNotFoundError:
        datos = {}
    if not isinstance(datos, dict) or any(
        type(datos[clave]) is not bool for clave in OPCIONES if clave in datos
    ):
        raise ValueError("El archivo de limpieza tiene un formato inválido.")
    mostrar = datos.get("boton_widget", datos.get("accion_widget") != "solo_atajo")
    if type(mostrar) is not bool:
        raise ValueError("La configuración del botón de limpieza no es válida.")
    return {**{clave: datos.get(clave, False) for clave in OPCIONES}, "boton_widget": mostrar}


def accion_widget(opciones):
    if not opciones["boton_widget"]:
        return "solo_atajo"
    return "revisar" if opciones["vista_previa"] else "directo"


def directorio_inseguro(modo):
    return bool(modo & (stat.S_IWGRP | stat.S_IWOTH) and not modo & stat.S_ISVTX)


def motivo_temporal(info, limite, *, subcarpeta=False, inseguro=False):
    if inseguro:
        return "Carpeta compartida sin protección"
    if subcarpeta:
        return "Está dentro de una subcarpeta"
    if info.st_nlink != 1:
        return "Tiene varios enlaces al mismo archivo"
    if max(info.st_atime, info.st_mtime) >= limite:
        return f"Acceso o modificación en los últimos {DIAS} días"
    return None


def identidad_temporal(info):
    return info.st_dev, info.st_ino, info.st_ctime_ns


def revisar_temporales(directorios, *, borrar, seleccion=None):
    limite = time.time() - DIAS * 86400
    usuario = os.getuid()
    cantidad = 0
    bytes_totales = 0
    errores = []
    for directorio in directorios:
        try:
            descriptor = os.open(directorio, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        except FileNotFoundError:
            continue
        except OSError as error:
            errores.append(str(error))
            continue
        try:
            # En ubicaciones compartidas, otros usuarios no deben poder sustituir archivos ajenos.
            modo = os.fstat(descriptor).st_mode
            if directorio_inseguro(modo):
                errores.append(f"Se omitió la ubicación compartida sin sticky bit: {directorio}")
                continue
            for nombre in os.listdir(descriptor):
                ruta = directorio / nombre
                if seleccion is not None and ruta not in seleccion:
                    continue
                try:
                    info = os.stat(nombre, dir_fd=descriptor, follow_symlinks=False)
                    if seleccion is not None and identidad_temporal(info) != seleccion[ruta]:
                        errores.append(f"El archivo cambió desde la vista previa: {ruta}")
                        continue
                    if (
                        stat.S_ISREG(info.st_mode) and info.st_uid == usuario
                        and motivo_temporal(info, limite) is None
                    ):
                        if borrar:
                            os.unlink(nombre, dir_fd=descriptor)
                        cantidad += 1
                        bytes_totales += info.st_size
                except FileNotFoundError:
                    continue
                except OSError as error:
                    errores.append(f"{directorio / nombre}: {error.strerror}")
        except OSError as error:
            errores.append(f"{directorio}: {error.strerror}")
        finally:
            os.close(descriptor)
    return cantidad, bytes_totales, errores


def medir(ruta):
    cantidad = total = 0
    incompleto = False
    pendientes = [ruta]
    try:
        dispositivo = ruta.lstat().st_dev
    except OSError:
        return 0, 0, True
    while pendientes:
        carpeta_o_archivo = pendientes.pop()
        try:
            info = carpeta_o_archivo.lstat()
            if info.st_dev != dispositivo:
                continue
            if stat.S_ISDIR(info.st_mode):
                with os.scandir(carpeta_o_archivo) as entradas:
                    pendientes.extend(Path(entrada.path) for entrada in entradas)
            elif stat.S_ISREG(info.st_mode):
                cantidad += 1
                total += info.st_size
        except OSError:
            incompleto = True
    return cantidad, total, incompleto


def inventario_temporales():
    archivos = []
    errores = []
    usuario = os.getuid()
    limite = time.time() - DIAS * 86400
    for raiz in DIRECTORIOS:
        try:
            info_raiz = raiz.lstat()
        except FileNotFoundError:
            continue
        except OSError as error:
            errores.append(str(error))
            continue
        if not stat.S_ISDIR(info_raiz.st_mode):
            continue
        inseguro = directorio_inseguro(info_raiz.st_mode)
        for carpeta, subcarpetas, nombres, descriptor in os.fwalk(raiz, onerror=errores.append):
            ruta = Path(carpeta)
            for nombre in subcarpetas[:]:
                try:
                    info = os.stat(nombre, dir_fd=descriptor, follow_symlinks=False)
                    if not stat.S_ISDIR(info.st_mode) or info.st_uid != usuario or info.st_dev != info_raiz.st_dev:
                        subcarpetas.remove(nombre)
                except OSError as error:
                    subcarpetas.remove(nombre)
                    errores.append(error)
            for nombre in nombres:
                try:
                    info = os.stat(nombre, dir_fd=descriptor, follow_symlinks=False)
                    if stat.S_ISREG(info.st_mode) and info.st_uid == usuario and info.st_dev == info_raiz.st_dev:
                        motivo = motivo_temporal(info, limite, subcarpeta=ruta != raiz, inseguro=inseguro)
                        archivos.append(ArchivoTemporal(
                            ruta / nombre, info.st_size, max(info.st_atime, info.st_mtime),
                            motivo, identidad_temporal(info),
                        ))
                except OSError as error:
                    errores.append(error)
    archivos.sort(key=lambda archivo: (archivo.motivo is not None, -archivo.tamanio, str(archivo.ruta)))
    return archivos, bool(errores)


def kio(*argumentos):
    try:
        proceso = subprocess.run(
            ["kioclient", "--noninteractive", "--platform", "offscreen", *argumentos],
            capture_output=True, text=True, timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise ValueError(f"No se pudo consultar la papelera de KDE. {error}") from error
    if proceso.returncode:
        raise ValueError(proceso.stderr.strip() or "KDE no pudo completar la operación en la papelera.")
    return proceso.stdout


def localizar(url, clave):
    salida = kio("stat", url)
    campos = {}
    for linea in salida.split("\n"):
        nombre = linea[:20].strip()
        if nombre in ("NAME", "LOCAL_PATH"):
            if nombre in campos or linea[20:22] != "  ":
                raise ValueError("KDE devolvió una entrada de papelera ambigua.")
            campos[nombre] = linea[22:]
    ruta = Path(campos.get("LOCAL_PATH", ""))
    if (campos.get("NAME") != clave or not ruta.is_absolute()
            or ruta.parent.name != "files" or ruta.name != clave.split("-", 1)[1]):
        raise ValueError("No se pudo verificar una entrada de la papelera.")
    info = ruta.lstat()
    identidad = (ruta, info.st_dev, info.st_ino, info.st_ctime_ns)
    return ruta, identidad


def listar_papelera():
    entradas = []
    incompleto = False
    for clave in dict.fromkeys(kio("ls", "trash:/").split("\n")):
        if clave in ("", ".", ".."):
            continue
        if not re.fullmatch(r"[0-9]+-[^/\x00-\x1f]+", clave) or clave.split("-", 1)[1] in (".", ".."):
            incompleto = True
            continue
        url = "trash:/" + quote(clave, safe="")
        try:
            ruta, identidad = localizar(url, clave)
            _, bytes_totales, parcial = medir(ruta)
        except (OSError, ValueError):
            incompleto = True
            continue
        entradas.append(ElementoPapelera(url, ruta.name, (clave, *identidad), bytes_totales, parcial))
    entradas.sort(key=lambda elemento: elemento.nombre.casefold())
    return entradas, incompleto


def borrar_seleccion_papelera(seleccion):
    cantidad = 0
    errores = []
    for elemento in seleccion:
        clave, *esperada = elemento.identidad
        try:
            _, identidad = localizar(elemento.url, clave)
            if identidad != tuple(esperada):
                raise ValueError("El elemento cambió desde la vista previa.")
            kio("remove", elemento.url)
            cantidad += 1
        except (OSError, ValueError) as error:
            errores.append(f"{elemento.nombre}: {error}")
    return cantidad, errores


def ejecutar(opciones, seleccion=None, temporales=None):
    mensajes = []
    errores = []
    if opciones["temporales"]:
        rutas = None if temporales is None else {
            archivo.ruta: archivo.identidad for archivo in temporales if archivo.motivo is None
        }
        cantidad, _, fallos = revisar_temporales(DIRECTORIOS, borrar=True, seleccion=rutas)
        mensajes.append(f"Archivos temporales eliminados: {cantidad}.")
        errores.extend(fallos)
    if opciones["papelera"] and seleccion is not None:
        cantidad, fallos = borrar_seleccion_papelera(seleccion)
        mensajes.append(f"Elementos eliminados de la papelera: {cantidad}.")
        errores.extend(fallos)
    elif opciones["papelera"]:
        try:
            proceso = subprocess.run(["ktrash6", "--empty"], capture_output=True, text=True)
            if proceso.returncode:
                detalle = proceso.stderr.strip()
                errores.append("KDE no pudo vaciar la papelera. " + detalle if detalle else "KDE no pudo vaciar la papelera.")
            else:
                mensajes.append("Papelera vaciada.")
        except OSError as error:
            errores.append(f"No se pudo vaciar la papelera. {error}")
    if not mensajes and not errores:
        mensajes.append("Marca al menos una opción de limpieza en Ajustes de Byotfast.")
    return mensajes, errores
