from fcntl import flock, LOCK_EX
from hashlib import sha256
import json
import os
import sys
from pathlib import Path
from time import monotonic

import perfiles

ACENTOS = {
    "Sistema": "",
    "Azul": "#3584e4",
    "Verde": "#26a269",
    "Turquesa": "#1994a5",
    "Violeta": "#9141ac",
    "Rosa": "#c74678",
    "Naranja": "#c65c24",
}
PERFIL = "org.local.Byotfast.perfilactivo"
LIMPIEZA = "org.local.Byotfast.revisarlimpieza"
UTILIDADES = (
    ("Controles rápidos", "org.local.Byotfast.Controles", "org.local.Byotfast.controles", "Conectividad, sonido, pantalla y energía"),
    ("Reloj", "org.local.Byotfast.Reloj", "org.local.Byotfast.reloj", "Hora y fecha locales"),
    ("Reloj moderno", "org.local.Byotfast.Reloj", "org.local.Byotfast.relojmoderno", "Día, fecha y hora con tipografía decorativa"),
    ("Calendario", "org.local.Byotfast.Calendario", "org.local.Byotfast.calendario", "Calendario mensual y notificaciones de Plasma"),
    ("Notas", "org.local.Byotfast.Notas", "org.local.Byotfast.notas", "Nota editable guardada en el escritorio"),
    ("Rendimiento", "org.local.Byotfast.Rendimiento", "org.local.Byotfast.rendimiento", "Uso de CPU y memoria"),
    ("Temporizador", "org.local.Byotfast.Temporizador", "org.local.Byotfast.temporizador", "Cuenta regresiva con pausa y aviso"),
    ("Tareas", "org.local.Byotfast.Tareas", "org.local.Byotfast.tareas", "Lista de tareas con casillas y orden editable"),
    ("Batería", "org.local.Byotfast.Bateria", "org.local.Byotfast.bateria", "Carga del equipo y de periféricos compatibles"),
    ("Clima", "org.local.Byotfast.Clima", "org.local.Byotfast.clima", "Temperatura y pronóstico de la ciudad elegida"),
    ("Música", "org.local.Byotfast.Musica", "org.local.Byotfast.musica", "Control del reproductor multimedia"),
    ("Espacio en disco", "org.local.Byotfast.Discos", "org.local.Byotfast.discos", "Espacio libre de las unidades montadas"),
    ("Calculadora", "org.local.Byotfast.Calculadora", "org.local.Byotfast.calculadora", "Operaciones básicas con historial"),
    ("Fotos", "org.local.Byotfast.Fotos", "org.local.Byotfast.fotos", "Foto local con encuadre ajustable"),
    ("Búsqueda de Google", "org.local.Byotfast.Busquedagoogle", "org.local.Byotfast.busquedagoogle", "Busca en Google con sugerencias al escribir"),
)


def apariencia():
    try:
        datos = json.loads((perfiles.CARPETA / "apariencia.json").read_text(encoding="utf-8"))
        if isinstance(datos, dict):
            tema = datos.get("tema")
            acento = datos.get("acento")
            return {
                "tema": tema if tema in ("Claro", "Oscuro", "Liquid Glass") else "Sistema",
                "acento": ACENTOS.get(acento, "") if isinstance(acento, str) else "",
            }
    except (OSError, ValueError):
        pass
    return {"tema": "Sistema", "acento": ""}


def estado_perfil():
    import atajos
    from gi.repository import GLib

    modelo = perfiles.leer()
    try:
        teclas = atajos.activos()
        atajo = atajos.nombre_activo(teclas) if atajos.secuencias(teclas) else ""
    except GLib.Error:
        atajo = ""
    return {
        **perfiles.resumen(modelo),
        "atajo": atajo,
    }


def modo_limpieza():
    import limpieza

    try:
        opciones = limpieza.leer_opciones(perfiles.CARPETA / "limpieza.json")
        return limpieza.accion_widget(opciones)
    except (OSError, ValueError):
        return "solo_atajo"


def estado_limpieza():
    import limpieza

    datos = {"accion": modo_limpieza()}
    try:
        archivos, parcial = limpieza.inventario_temporales()
        datos["temporales"] = limpieza.mostrar_bytes(sum(archivo.tamanio for archivo in archivos))
        if parcial:
            datos["temporales"] += " aprox."
    except (OSError, ValueError):
        datos["temporales"] = "Sin datos"
    try:
        elementos, parcial = limpieza.listar_papelera()
        datos["papelera"] = limpieza.mostrar_bytes(sum(elemento.bytes for elemento in elementos))
        if parcial or any(elemento.incompleto for elemento in elementos):
            datos["papelera"] += " aprox."
    except (OSError, ValueError):
        datos["papelera"] = "Sin datos"
    return datos


def muestra_compartida(consulta, segundos, obtener):
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime:
        return obtener()
    carpeta = Path(runtime) / "byotfast"
    carpeta.mkdir(mode=0o700, exist_ok=True)
    clave = sha256(json.dumps(consulta).encode()).hexdigest()
    with (carpeta / clave).open("a+", encoding="utf-8") as archivo:
        flock(archivo, LOCK_EX)
        archivo.seek(0)
        try:
            fecha, datos = json.load(archivo)
            if 0 <= monotonic() - fecha < segundos:
                return datos
        except (ValueError, TypeError):
            pass
        datos = obtener()
        archivo.seek(0)
        archivo.truncate()
        json.dump((monotonic(), datos), archivo)
        return datos


def main(argumentos):
    if argumentos == ["perfil"]:
        datos = estado_perfil()
    elif argumentos == ["limpieza"]:
        datos = estado_limpieza()
    elif argumentos == ["apariencia"]:
        datos = apariencia()
    elif argumentos == ["preferencias"]:
        datos = {**apariencia(), "accion": modo_limpieza()}
    elif argumentos and argumentos[0] == "controles":
        from controles_rapidos import operar

        datos = operar(*argumentos[1:])
    elif argumentos == ["rendimiento"]:
        from rendimiento import rendimiento

        datos = muestra_compartida(argumentos, 3, rendimiento)
    elif len(argumentos) == 2 and argumentos[0] == "seleccionar":
        perfiles.seleccionar(argumentos[1])
        datos = estado_perfil()
    elif len(argumentos) == 2 and argumentos[0] == "portada-musica":
        from widget_datos import portada_guardada

        datos = muestra_compartida(argumentos, 2, lambda: {"portada": portada_guardada(argumentos[1])})
    elif argumentos and argumentos[0] in ("bateria", "discos", "musica", "buscar-ciudad", "clima", "portada-siguiente", "clima-ubicacion", "feriados", "guardar-ubicacion"):
        from gi.repository import GLib
        import widget_datos

        consultas = {
            "bateria": widget_datos.baterias, "discos": widget_datos.discos, "musica": widget_datos.musica,
            "buscar-ciudad": widget_datos.buscar_ciudad, "clima": widget_datos.clima,
            "portada-siguiente": widget_datos.portada_siguiente,
            "clima-ubicacion": widget_datos.clima_ubicacion, "feriados": widget_datos.feriados,
            "guardar-ubicacion": lambda texto: widget_datos.guardar_ubicacion(json.loads(texto)),
        }
        try:
            operacion, *parametros = argumentos
            obtener = lambda: consultas[operacion](*parametros)
            vigencia = {"bateria": 0.15, "discos": 10, "clima": 840, "clima-ubicacion": 20, "feriados": 20}.get(operacion)
            if operacion == "musica" and not parametros:
                vigencia = 0.04
            datos = muestra_compartida(argumentos, vigencia, obtener) if vigencia else obtener()
        except (OSError, ValueError, GLib.Error, KeyError):
            datos = {"error": "No se pudieron obtener los datos."}
    else:
        raise ValueError("Acción de widget inválida.")
    print(json.dumps(datos, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except (OSError, ValueError) as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False))
        sys.exit(1)
