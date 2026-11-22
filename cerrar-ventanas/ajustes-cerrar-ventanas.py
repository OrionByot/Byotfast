#!/usr/bin/python3
from hashlib import sha256
import json
import os
from datetime import datetime
from pathlib import Path
import sys
import shlex
import shutil
import stat
import subprocess

import atajos
import limpieza
import perfiles
import widgets
from perfiles import guardar
from uuid import uuid4
from threading import Thread

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
gi.require_version("Graphene", "1.0")
gi.require_version("Pango", "1.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gdk, Gio, GLib, Graphene, Gtk, Pango

CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
CONFIG = CONFIG / "cerrar-ventanas" / "excepciones.json"

RUTA_COMANDO = Path(__file__).resolve().with_name("cerrar-ventanas.sh")
TITULO = "Byotfast"
ID_APP = "org.local.Byotfast"
ID_ANTERIOR = "org.local.CerrarVentanas"
APARIENCIA = CONFIG.with_name("apariencia.json")
LIMPIEZA = CONFIG.with_name("limpieza.json")
ARCHIVO_ATAJOS_KDE = CONFIG.parent.parent / "kglobalshortcutsrc"
TEMAS = {
    "Sistema": Adw.ColorScheme.DEFAULT,
    "Claro": Adw.ColorScheme.FORCE_LIGHT,
    "Oscuro": Adw.ColorScheme.FORCE_DARK,
    "Liquid Glass": Adw.ColorScheme.DEFAULT,
}
ACENTOS = {
    nombre: color or "@accent_bg_color" for nombre, color in widgets.ACENTOS.items()
}

MATRIZ_GRIS = Graphene.Matrix().init_from_float([
    0.2126, 0.2126, 0.2126, 0.0,
    0.7152, 0.7152, 0.7152, 0.0,
    0.0722, 0.0722, 0.0722, 0.0,
    0.0, 0.0, 0.0, 1.0,
])
SIN_DESPLAZAMIENTO = Graphene.Vec4().init(0, 0, 0, 0)


class IconoAplicacion(Gtk.Box):
    __gtype_name__ = "ByotfastIconoAplicacion"

    def __init__(self, icono, conservar, tamano=36):
        super().__init__(halign=Gtk.Align.CENTER)
        self.conservar = conservar
        self.imagen = Gtk.Image(gicon=icono)
        self.imagen.set_pixel_size(tamano)
        self.append(self.imagen)

    def actualizar(self, conservar):
        self.conservar = conservar
        self.queue_draw()

    def do_snapshot(self, snapshot):
        if not self.conservar:
            snapshot.push_color_matrix(MATRIZ_GRIS, SIN_DESPLAZAMIENTO)
        self.snapshot_child(self.imagen, snapshot)
        if not self.conservar:
            snapshot.pop()


def argumento_exec(ruta):
    texto = str(ruta).replace("%", "%%")
    for caracter in ('\\', '"', '`', '$'):
        texto = texto.replace(caracter, '\\' + caracter)
    return f'"{texto}"'


COHETE = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
  <path fill="#fb923c" d="M23 43C11 42 7 51 7 57c6 0 15-4 14-16z"/>
  <path fill="#ea580c" d="M17 40c-7 0-12 4-13 8l13-1z"/>
  <path fill="#2563eb" d="M30 22 16 24 7 38l17-1m18-3-2 14-14 9 1-17"/>
  <path fill="#38bdf8" d="M16 36C25 15 41 7 58 6c-1 17-9 33-30 42z"/>
  <path fill="#2563eb" d="M45 8c4-1 9-2 13-2 0 4-1 9-2 13z"/>
  <circle cx="40" cy="24" r="7" fill="#eff6ff"/>
</svg>
"""


def instalar_acceso():
    datos = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share")
    icono = datos / "icons/hicolor/scalable/apps/org.local.CerrarVentanas.svg"
    icono.parent.mkdir(parents=True, exist_ok=True)
    icono.write_text(COHETE, encoding="utf-8")

    acceso = datos / "applications" / f"{ID_APP}.desktop"
    acceso.parent.mkdir(parents=True, exist_ok=True)

    entrada = GLib.KeyFile()
    grupo = "Desktop Entry"
    entrada.set_string(grupo, "Type", "Application")
    entrada.set_string(grupo, "Name", TITULO)
    entrada.set_string(grupo, "Comment", "Elige las aplicaciones que quieres dejar abiertas")
    entrada.set_string(grupo, "Exec", f"/usr/bin/python3 {argumento_exec(Path(__file__).resolve())}")
    entrada.set_string(grupo, "Icon", str(icono))
    entrada.set_boolean(grupo, "Terminal", False)
    entrada.set_string(grupo, "StartupWMClass", ID_APP)
    entrada.set_string(grupo, "Categories", "Utility;")
    entrada.set_boolean(grupo, "NoDisplay", False)
    entrada.save_to_file(str(acceso))
    anterior = acceso.with_name("org.local.CerrarVentanas.desktop")
    if anterior.is_file():
        anterior.unlink()
    if shutil.which("kbuildsycoca6"):
        subprocess.run(["kbuildsycoca6"], check=False, capture_output=True)
    comando = datos / "kglobalaccel" / atajos.COMPONENTE
    primera_vez = not comando.exists()
    comando.parent.mkdir(parents=True, exist_ok=True)
    entrada.remove_key(grupo, "Categories")
    entrada.remove_key(grupo, "StartupWMClass")
    entrada.set_string(grupo, "Exec", argumento_exec(RUTA_COMANDO))
    entrada.set_boolean(grupo, "X-KDE-GlobalAccel-CommandShortcut", True)
    entrada.set_boolean(grupo, "StartupNotify", False)
    guardar_lanzador_atajo(entrada, comando)
    entrada.set_string(grupo, "Name", atajos.LIMPIEZA[2])
    entrada.set_string(grupo, "Comment", "Limpia las ubicaciones seleccionadas en Byotfast")
    entrada.set_string(grupo, "Exec", f"/usr/bin/python3 {argumento_exec(Path(__file__).resolve())} --limpiar")
    guardar_lanzador_atajo(entrada, comando.with_name(atajos.LIMPIEZA[0]))

    modelo = perfiles.leer()
    if not perfiles.ARCHIVO.exists():
        guardar(modelo, perfiles.ARCHIVO)
    print("Byotfast se instaló en Aplicaciones → Utilidades. Si los ajustes estaban abiertos, cierra la ventana y vuelve a abrirla desde el menú.")
    hubo_error = False
    for accion, predeterminado in atajos.PREDETERMINADOS:
        try:
            atajos.registrar(accion)
            if primera_vez and not atajos.secuencias(atajos.activos(accion)):
                atajos.asignar(predeterminado, accion)
            print(f"{accion[2]}: {atajos.nombre_activo(atajos.activos(accion))}")
        except (GLib.Error, ValueError) as error:
            print(f"No se pudo configurar el atajo de {accion[2]}. {error}", file=sys.stderr)
            hubo_error = True
    if hubo_error:
        print("Puedes configurar los atajos desde Ajustes de Byotfast.", file=sys.stderr)
    return int(hubo_error)


def lanzador_perfil(clave, nombre):
    destino = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share") / "kglobalaccel"
    destino.mkdir(parents=True, exist_ok=True)
    archivo = destino / f"org.local.Byotfast.perfil-{clave}.desktop"
    titulo = f"Byotfast · {nombre}"
    orden = [str(RUTA_COMANDO), "--perfil", clave]
    if not archivo.exists():
        entrada = GLib.KeyFile()
        grupo = "Desktop Entry"
        entrada.set_string(grupo, "Type", "Application")
        entrada.set_string(grupo, "Name", titulo)
        entrada.set_string(grupo, "Exec", argumento_exec(orden[0]) + f" --perfil {clave}")
        entrada.set_boolean(grupo, "NoDisplay", True)
        entrada.set_boolean(grupo, "X-KDE-GlobalAccel-CommandShortcut", True)
        guardar_lanzador_atajo(entrada, archivo)
    return [archivo.name, "_launch", titulo, titulo], orden


def guardar_lanzador_atajo(entrada, destino):
    entrada.save_to_file(str(destino))
    destino.chmod(destino.stat().st_mode | stat.S_IXUSR)


def leer_apariencia():
    try:
        datos = json.loads(APARIENCIA.read_text(encoding="utf-8"))
    except FileNotFoundError:
        datos = {}
    if not isinstance(datos, dict):
        raise ValueError("El archivo de apariencia tiene un formato inválido.")
    return {
        clave: datos[clave] if isinstance(datos.get(clave), str) and datos[clave] in opciones else "Sistema"
        for clave, opciones in (("tema", TEMAS), ("acento", ACENTOS))
    }


def aplicar_apariencia(preferencias, estilos):
    Adw.StyleManager.get_default().set_color_scheme(TEMAS[preferencias["tema"]])
    acento = ACENTOS[preferencias["acento"]]
    muestras = "\n".join(
        f".byotfast-muestra-{indice} {{ background-color: {color}; }}"
        for indice, color in enumerate(ACENTOS.values())
    )
    vidrio = f"""
        window.byotfast-window {{
            background-color: transparent;
            background-image: linear-gradient(145deg,
                mix(@window_bg_color, @window_fg_color, 0.10),
                @window_bg_color);
            border: 1px solid alpha(@window_fg_color, 0.26);
            box-shadow: inset 0 1px alpha(white, 0.33);
        }}
        window.byotfast-window headerbar {{
            background-color: alpha(@window_bg_color, 0.56);
        }}
        window.byotfast-window .byotfast-widget {{
            border-color: alpha(@window_fg_color, 0.16);
            box-shadow: inset 0 1px alpha(white, 0.20);
            background-image: linear-gradient(to bottom,
                alpha(@window_fg_color, 0.10), alpha(@window_fg_color, 0.04));
        }}
    """ if preferencias["tema"] == "Liquid Glass" else ""
    estilos.load_from_data((f"""
        .byotfast-muestra {{
            min-width: 14px;
            min-height: 14px;
            border-radius: 100px;
            border: 1px solid alpha(currentColor, 0.30);
        }}
        .byotfast-sidebar {{
            background-color: alpha(@window_fg_color, 0.055);
            border: 1px solid alpha(@window_fg_color, 0.11);
            border-radius: 11px;
            padding: 8px;
        }}
        .byotfast-sidebar button {{
            background-image: none;
            background-color: transparent;
            border: 1px solid transparent;
            box-shadow: none;
            border-radius: 8px;
            padding: 7px 9px;
            font-weight: normal;
        }}
        .byotfast-sidebar button:hover {{
            background-color: alpha(@window_fg_color, 0.07);
        }}
        .byotfast-sidebar button:checked {{
            background-color: alpha({acento}, 0.22);
            border-color: alpha({acento}, 0.78);
            font-weight: bold;
        }}
        button.byotfast-app {{
            background-image: none;
            background-color: alpha(@window_fg_color, 0.045);
            border: 1px solid alpha(@window_fg_color, 0.17);
            box-shadow: none;
            padding: 5px 8px;
            border-radius: 9px;
        }}
        button.byotfast-app:hover {{
            background-color: alpha(@window_fg_color, 0.08);
        }}
        button.byotfast-app:checked, button.byotfast-app.byotfast-con-atajo {{
            background-color: alpha({acento}, 0.20);
            border-color: {acento};
        }}
        button.byotfast-app:checked:hover, button.byotfast-app.byotfast-con-atajo:hover {{
            background-color: alpha({acento}, 0.28);
        }}
        .byotfast-sidebar button:focus-visible, button.byotfast-app:focus-visible {{
            outline: 2px solid @window_fg_color;
            outline-offset: -3px;
        }}
        .byotfast-casilla check:checked {{
            background-image: none;
            background-color: {acento};
            border-color: {acento};
            color: white;
        }}
        .byotfast-widget {{
            border: 1px solid alpha({acento}, 0.44);
            border-radius: 14px;
            background-color: alpha({acento}, 0.08);
            padding: 14px;
        }}
        .byotfast-nav {{
            border-radius: 9px;
            padding: 6px 10px;
        }}
        .byotfast-nav:checked {{
            background-image: none;
            background-color: alpha({acento}, 0.26);
            border-color: {acento};
        }}
        .byotfast-nav:focus-visible, .byotfast-widget button:focus-visible {{
            outline-color: {acento};
        }}
        .byotfast-preview {{
            border: 1px solid alpha(@window_fg_color, 0.23);
            border-radius: 9px;
            background-image: linear-gradient(150deg, alpha({acento}, 0.15), alpha(@window_bg_color, 0.90));
            padding: 8px;
        }}
        .byotfast-accent {{ color: {acento}; }}
        .byotfast-preview-dot {{
            min-width: 7px;
            min-height: 7px;
            border-radius: 50%;
            background-color: {acento};
        }}
        button.byotfast-preview-switch {{
            min-width: 15px;
            min-height: 16px;
            padding: 0 3px;
            color: @window_fg_color;
        }}
        .byotfast-weather-temperature {{
            font-size: 31px;
            font-weight: normal;
        }}
        .byotfast-catalogo, .byotfast-catalogo row {{
            background-color: transparent;
        }}
        .byotfast-catalogo row:hover {{
            background-color: alpha({acento}, 0.10);
            border-radius: 8px;
        }}
        .byotfast-catalogo row image, .byotfast-preview image, .byotfast-panel-demo image {{
            color: {acento};
            -gtk-icon-style: symbolic;
        }}
        .byotfast-cover {{
            min-width: 34px;
            min-height: 34px;
            border-radius: 50%;
            color: {acento};
            background-color: alpha({acento}, 0.26);
        }}
        .byotfast-preview-key {{
            background-color: alpha(@window_fg_color, 0.12);
            border-radius: 4px;
            padding: 1px 3px;
        }}
        .byotfast-panel-demo {{
            border-radius: 7px;
            background-color: alpha(@window_bg_color, 0.8);
            padding: 2px 5px;
        }}
        .byotfast-marca {{
            background-color: {acento};
            color: @window_bg_color;
            font-size: 11px;
            font-weight: 800;
            border-radius: 99px;
            padding: 1px 4px;
        }}
        .byotfast-widget-accion {{
            background-image: none;
            background-color: alpha({acento}, 0.35);
        }}
        .byotfast-tecla {{
            padding: 3px 7px;
            border: 1px solid alpha({acento}, 0.45);
            border-radius: 5px;
        }}
    """ + muestras + vidrio).encode("utf-8"))


def fabrica_acentos():
    fabrica = Gtk.SignalListItemFactory()

    def preparar(_, elemento):
        fila = Gtk.Box(spacing=8)
        muestra = Gtk.Box(valign=Gtk.Align.CENTER)
        fila.append(muestra)
        fila.append(Gtk.Label(xalign=0))
        elemento.set_child(fila)

    def enlazar(_, elemento):
        fila = elemento.get_child()
        nombre = elemento.get_item().get_string()
        indice = list(ACENTOS).index(nombre)
        fila.get_first_child().set_css_classes(["byotfast-muestra", f"byotfast-muestra-{indice}"])
        fila.get_last_child().set_text(nombre)

    fabrica.connect("setup", preparar)
    fabrica.connect("bind", enlazar)
    return fabrica


def boton_info(titulo, texto, *, seleccionar=False, enlace=None):
    boton = Gtk.MenuButton(icon_name="dialog-information-symbolic", tooltip_text=titulo)
    boton.add_css_class("flat")
    boton.update_property([Gtk.AccessibleProperty.LABEL], [titulo])
    globo = Gtk.Popover()
    detalle = Gtk.Label(
        label=texto, xalign=0, wrap=True, wrap_mode=Pango.WrapMode.WORD_CHAR,
        max_width_chars=42, selectable=seleccionar,
    )
    contenido = detalle
    if enlace:
        contenido = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        contenido.append(detalle)
        etiqueta_enlace, uri = enlace
        contenido.append(Gtk.LinkButton(uri=uri, label=etiqueta_enlace, halign=Gtk.Align.START))
    for borde in ("top", "bottom", "start", "end"):
        getattr(contenido, f"set_margin_{borde}")(10)
    globo.set_child(contenido)
    boton.set_popover(globo)
    return boton


def dialogo_interno(principal, titulo, ancho, contenido):
    if hasattr(Adw, "Dialog"):
        dialogo = Adw.Dialog(title=titulo, content_width=ancho)
        barra = Adw.HeaderBar()
        barra.set_title_widget(Adw.WindowTitle(title=titulo))
        vista = Adw.ToolbarView(content=contenido)
        vista.add_top_bar(barra)
        dialogo.set_child(vista)
        return lambda: dialogo.present(principal), dialogo.close

    dialogo = Gtk.Window(title=titulo, transient_for=principal, modal=True, destroy_with_parent=True)
    dialogo.set_default_size(ancho, -1)
    dialogo.set_child(contenido)
    return dialogo.present, dialogo.close


def configurar_ubicacion(principal, *, inicial=False):
    from widget_datos import buscar_ciudad, guardar_ubicacion, ubicacion

    caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin_top=14, margin_bottom=14,
                  margin_start=14, margin_end=14)
    presentar, cerrar = dialogo_interno(principal, "Ubicación", 470, caja)
    actual = ubicacion().get("nombre")
    caja.append(Gtk.Label(label=actual or "Elige una ciudad para Clima y los feriados del Calendario.",
                         xalign=0, wrap=True))
    fila = Gtk.Box(spacing=6)
    entrada = Gtk.SearchEntry(placeholder_text="Buscar ciudad", hexpand=True)
    buscar = Gtk.Button(label="Buscar")
    fila.append(entrada)
    fila.append(buscar)
    caja.append(fila)
    estado = Gtk.Label(xalign=0, wrap=True)
    caja.append(estado)
    lista = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
    caja.append(Gtk.ScrolledWindow(child=lista, min_content_height=130, max_content_height=225,
                                  propagate_natural_height=True, hscrollbar_policy=Gtk.PolicyType.NEVER))

    def elegir(_, ciudad):
        try:
            guardar_ubicacion(ciudad)
        except (OSError, ValueError) as error:
            estado.set_text(str(error))
        else:
            cerrar()

    def mostrar(ciudades, mensaje):
        for ciudad in ciudades:
            boton = Gtk.Button(label=ciudad["nombre"])
            boton.connect("clicked", elegir, ciudad)
            lista.append(boton)
        estado.set_text(mensaje)
        buscar.set_sensitive(True)
        return GLib.SOURCE_REMOVE

    def consultar(_):
        texto = entrada.get_text().strip()
        if not buscar.get_sensitive():
            return
        while hijo := lista.get_first_child():
            lista.remove(hijo)
        buscar.set_sensitive(False)
        estado.set_text("Buscando…")

        def tarea():
            try:
                resultado = buscar_ciudad(texto)
                ciudades = [ciudad for ciudad in resultado.get("ciudades", []) if ciudad.get("pais")]
                mensaje = resultado.get("error", "" if ciudades else "No se encontraron ciudades.")
            except (OSError, ValueError, KeyError):
                ciudades, mensaje = [], "No se pudo consultar el buscador de ciudades."
            GLib.idle_add(mostrar, ciudades, mensaje)

        Thread(target=tarea, daemon=True).start()

    buscar.connect("clicked", consultar)
    entrada.connect("activate", consultar)
    if inicial:
        omitir = Gtk.Button(label="Ahora no", halign=Gtk.Align.END)

        def recordar_omision(_):
            try:
                guardar({"omitida": True}, perfiles.CARPETA / "ubicacion.json")
            except OSError as error:
                estado.set_text(str(error))
            else:
                cerrar()

        omitir.connect("clicked", recordar_omision)
        caja.append(omitir)
    presentar()
    entrada.grab_focus()


def controles_atajo(panel, accion, orden, *, quitar=False, al_cambiar=None, preparar=None, atajo_panel=None):
    barra = Gtk.Box(spacing=8)
    campo = Gtk.Entry(hexpand=True, editable=False)
    capturar = Gtk.ToggleButton(label="Capturar teclas")
    barra.append(campo)
    barra.append(capturar)
    if orden:
        barra.append(boton_info("Comando del atajo", shlex.join(orden), seleccionar=True))
    panel.append(barra)
    estado = Gtk.Label(xalign=0, wrap=True)
    estado.connect("notify::label", lambda control, _: control.set_visible(bool(control.get_text())))
    estado.set_visible(False)
    panel.append(estado)

    def actualizar(texto=None):
        try:
            if atajo_panel is not None:
                nombre_atajo = atajo_panel(texto)
                hay_atajo = bool(nombre_atajo)
                campo.set_text(nombre_atajo)
            else:
                if preparar is None:
                    atajos.registrar(accion)
                else:
                    preparar()
                if texto is not None:
                    atajos.asignar(texto, accion)
                teclas = atajos.activos(accion)
                hay_atajo = bool(atajos.secuencias(teclas))
                campo.set_text(atajos.nombre_activo(teclas) if hay_atajo else "")
            if not hay_atajo:
                estado.set_text("Sin atajo")
            elif texto is not None:
                estado.set_text("Atajo guardado.")
            else:
                estado.set_text("")
            if texto is not None and al_cambiar:
                al_cambiar(campo.get_text())
        except (GLib.Error, ValueError, OSError) as error:
            estado.set_text(str(error))

    modificadores = {
        "Ctrl": Gdk.ModifierType.CONTROL_MASK,
        "Alt": Gdk.ModifierType.ALT_MASK,
        "Shift": Gdk.ModifierType.SHIFT_MASK,
        "Meta": Gdk.ModifierType.SUPER_MASK | Gdk.ModifierType.META_MASK,
    }

    def tecla_pulsada(_, tecla, _codigo, estado_teclas):
        if not capturar.get_active():
            return False
        nombre = Gdk.keyval_name(tecla) or ""
        if nombre == "Escape":
            capturar.set_active(False)
            actualizar()
            return True
        if nombre.startswith(("Control_", "Shift_", "Alt_", "Super_", "Meta_")):
            return True
        if nombre.startswith("KP_") and not nombre[3:].isdigit():
            estado.set_text("Activa Bloq Num y vuelve a pulsar la combinación.")
            return True
        partes = [nombre for nombre, mascara in modificadores.items() if estado_teclas & mascara]
        texto = "+".join([*partes, nombre.upper()])
        try:
            atajos.codigo(texto)
        except ValueError as error:
            estado.set_text(str(error))
        else:
            capturar.set_active(False)
            actualizar(texto)
        return True

    def activar_captura(control):
        if control.get_active():
            control.grab_focus()
            estado.set_text("Pulsa la combinación. Esc cancela la captura.")
        else:
            estado.set_text("" if campo.get_text() else "Sin atajo")

    if quitar:
        borrar = Gtk.Button(label="Quitar atajo")
        borrar.connect("clicked", lambda _: actualizar(""))
        barra.append(borrar)
    teclado = Gtk.EventControllerKey()
    teclado.connect("key-pressed", tecla_pulsada)
    capturar.add_controller(teclado)
    capturar.connect("toggled", activar_captura)

    foco = Gtk.EventControllerFocus()
    foco.connect("leave", lambda _: capturar.set_active(False))
    capturar.add_controller(foco)
    actualizar()


def aplicaciones_instaladas():
    aplicaciones = {}
    for app in sorted(Gio.AppInfo.get_all(), key=lambda a: a.get_display_name().casefold()):
        archivo = app.get_id()
        if not archivo or archivo in aplicaciones or not app.should_show() or app.get_boolean("Terminal"):
            continue
        identificador = archivo.removesuffix(".desktop")
        clase = app.get_string("StartupWMClass")
        ids = [identificador, clase] if clase else [identificador]
        icono = app.get_icon()
        if identificador == ID_APP:
            ids.append(ID_ANTERIOR)
            if icono is None:
                datos = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share")
                ruta = datos / "icons/hicolor/scalable/apps" / f"{ID_ANTERIOR}.svg"
                icono = Gio.FileIcon.new(Gio.File.new_for_path(str(ruta)))
        aplicaciones[archivo] = (app.get_display_name(), ids, icono)
    return aplicaciones


def observar_ventanas(ventana, pagina, recibir):
    interfaz = Gio.DBusNodeInfo.new_for_xml("""
        <node><interface name="org.local.Byotfast.Ventanas">
          <method name="Recibir"><arg name="ventanas" type="s" direction="in"/></method>
        </interface></node>
    """)
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    except GLib.Error:
        recibir(None)
        return

    cerrada = False
    proceso = None
    fallos_consecutivos = 0

    def informar_fallo():
        nonlocal fallos_consecutivos
        fallos_consecutivos += 1
        if fallos_consecutivos == 2:
            recibir(None)

    def respuesta(_bus, _sender, _ruta, _interfaz, _metodo, parametros, invocacion):
        nonlocal fallos_consecutivos
        try:
            datos = json.loads(parametros.unpack()[0])
            if not isinstance(datos, list) or any(
                not isinstance(fila, list) or len(fila) != 3 or any(not isinstance(v, str) for v in fila)
                for fila in datos
            ):
                raise ValueError("Respuesta inválida.")
        except ValueError:
            invocacion.return_dbus_error("org.local.Byotfast.Error", "Respuesta inválida.")
            return
        invocacion.return_value(None)
        if not cerrada:
            fallos_consecutivos = 0
            recibir(datos)

    registro = bus.register_object("/org/local/Byotfast/Ventanas", interfaz.interfaces[0], respuesta, None, None)

    def finalizado(tarea, resultado, *_):
        nonlocal proceso
        proceso = None
        try:
            tarea.wait_check_finish(resultado)
        except GLib.Error:
            if not cerrada:
                informar_fallo()

    def consultar():
        nonlocal proceso
        if proceso is None and pagina.get_mapped():
            try:
                proceso = Gio.Subprocess.new(
                    [str(RUTA_COMANDO), "--listar", bus.get_unique_name()],
                    Gio.SubprocessFlags.STDOUT_SILENCE | Gio.SubprocessFlags.STDERR_SILENCE,
                )
                proceso.wait_check_async(None, finalizado)
            except GLib.Error:
                informar_fallo()
        return GLib.SOURCE_CONTINUE

    fuente = 0

    def iniciar(*_):
        nonlocal fuente
        if not fuente and not cerrada:
            fuente = GLib.timeout_add_seconds(5, consultar)
            consultar()

    def detener(*_):
        nonlocal fuente
        if fuente:
            GLib.source_remove(fuente)
            fuente = 0

    def cerrar(_):
        nonlocal cerrada
        cerrada = True
        detener()
        bus.unregister_object(registro)
        return False

    ventana.connect("close-request", cerrar)
    pagina.connect("map", iniciar)
    pagina.connect("unmap", detener)
    if pagina.get_mapped():
        iniciar()


def abrir(app):
    if app.get_active_window():
        app.get_active_window().present()
        return
    ventana = Adw.ApplicationWindow(application=app, title=TITULO)
    ventana.add_css_class("byotfast-window")
    ventana.set_default_size(860, 650)
    try:
        preferencias = leer_apariencia()
        error_apariencia = ""
    except (OSError, ValueError) as error:
        preferencias = {"tema": "Sistema", "acento": "Sistema"}
        error_apariencia = str(error)
    estilos = Gtk.CssProvider()
    pantalla = ventana.get_display()
    Gtk.StyleContext.add_provider_for_display(pantalla, estilos, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
    ventana.connect("close-request", lambda _: Gtk.StyleContext.remove_provider_for_display(pantalla, estilos))
    aplicar_apariencia(preferencias, estilos)

    panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
    for lado in ("top", "bottom", "start", "end"):
        getattr(panel, "set_margin_" + lado)(16)
    barra_titulo = Adw.HeaderBar(
        title_widget=Adw.WindowTitle(title=TITULO),
        decoration_layout=":minimize,maximize,close",
    )
    vista_ventana = Adw.ToolbarView(content=panel)
    vista_ventana.add_top_bar(barra_titulo)
    ventana.set_content(vista_ventana)
    try:
        modelo = perfiles.leer()
    except (OSError, ValueError) as error:
        panel.append(Gtk.Label(label=str(error), wrap=True))
        ventana.present()
        return

    cuerpo = Gtk.Box(spacing=14, vexpand=True)
    panel.append(cuerpo)
    navegacion = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=5, width_request=140,
                         css_classes=["byotfast-sidebar"])
    marca = Gtk.Box(spacing=7, valign=Gtk.Align.CENTER, margin_start=5, margin_top=4, margin_bottom=7)
    datos = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share")
    ruta_cohete = datos / "icons/hicolor/scalable/apps" / f"{ID_ANTERIOR}.svg"
    cohete = (Gtk.Image(gicon=Gio.FileIcon.new(Gio.File.new_for_path(str(ruta_cohete))))
              if ruta_cohete.is_file() else Gtk.Image(icon_name="applications-utilities-symbolic"))
    cohete.set_pixel_size(19)
    marca.append(cohete)
    marca.append(Gtk.Label(label="Byotfast", css_classes=["heading"]))
    navegacion.append(marca)
    paginas = Gtk.Stack(vexpand=True, hexpand=True, hhomogeneous=False, vhomogeneous=False, transition_type=Gtk.StackTransitionType.NONE)
    botones = {}
    buscar_lanzador = buscar_widget = None
    def navegar(control, pagina):
        nonlocal buscar_lanzador, buscar_widget
        if not control.get_active():
            return
        if not paginas.get_child_by_name(pagina):
            if pagina == "ajustes":
                paginas.add_named(crear_ajustes(preferencias, estilos, error_apariencia), pagina)
            elif pagina == "lanzadores":
                lanzadores, buscar_lanzador = crear_lanzadores(ventana, instaladas)
                paginas.add_named(lanzadores, pagina)
            elif pagina == "widgets":
                catalogo, buscar_widget = crear_catalogo(ventana)
                paginas.add_named(catalogo, pagina)
        paginas.set_visible_child_name(pagina)
        if pagina == "perfiles":
            refrescar_perfiles()

    for clave, titulo in (("apps", "Kill-apps"), ("lanzadores", "Lanzadores"), ("perfiles", "Perfiles"),
                          ("widgets", "Widgets"), ("ajustes", "⚙ Ajustes")):
        if clave == "ajustes":
            navegacion.append(Gtk.Box(vexpand=True))
        boton = Gtk.ToggleButton(child=Gtk.Label(label=titulo, xalign=0))
        if botones:
            boton.set_group(next(iter(botones.values())))
        navegacion.append(boton)
        botones[clave] = boton
        boton.connect("toggled", navegar, clave)
    cuerpo.append(navegacion)
    cuerpo.append(paginas)
    panel.append(Gtk.Label(label="Desarrollado por Orinson Tuanama", xalign=0, css_classes=["caption", "dim-label"]))

    principal = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
    paginas.add_named(principal, "apps")
    cabecera = Gtk.Box(spacing=8)
    cabecera.append(Gtk.Label(label="Kill-apps", xalign=0, hexpand=True, css_classes=["title-1"]))
    selector = Gtk.DropDown()
    selector.update_property([Gtk.AccessibleProperty.LABEL], ["Perfil activo"])
    principal.append(cabecera)
    barra = Gtk.Box(spacing=8)
    buscador = Gtk.SearchEntry(placeholder_text="Buscar aplicaciones", hexpand=True)
    cambiar_vista = Gtk.ToggleButton(active=True)
    barra.append(selector)
    barra.append(buscador)
    barra.append(cambiar_vista)
    principal.append(barra)
    filtros = Gtk.Box(spacing=6)
    filtro = "todas"
    botones_filtro = {}
    for clave, titulo in (("todas", "Todas"), ("abiertas", "Abiertas"), ("protegidas", "Se conservan")):
        boton = Gtk.ToggleButton(label=titulo)
        boton.add_css_class("byotfast-nav")
        if botones_filtro:
            boton.set_group(next(iter(botones_filtro.values())))
        botones_filtro[clave] = boton
        filtros.append(boton)
    botones_filtro["todas"].set_active(True)
    filtros.append(boton_info("Cómo conservar aplicaciones",
                             "Marca una aplicación con un clic o con Espacio. El cambio se guarda en el perfil activo."))
    principal.append(filtros)

    contenido = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
    desplazamiento = Gtk.ScrolledWindow(vexpand=True, hscrollbar_policy=Gtk.PolicyType.EXTERNAL, child=contenido, propagate_natural_height=False, propagate_natural_width=False)
    principal.append(desplazamiento)
    ajuste = desplazamiento.get_vadjustment()
    estado = Gtk.Label(xalign=0, wrap=True, visible=False)
    principal.append(estado)

    instaladas = aplicaciones_instaladas()
    abiertas = {}
    lectura_realizada = False
    consulta_fallida = False
    claves = []
    actualizando_selector = False
    pendiente = False
    firma_vista = None
    refrescar_perfiles = lambda: None

    def mostrar_error(error):
        estado.set_text(str(error))
        estado.set_visible(True)

    def actualizar_selector():
        nonlocal claves, actualizando_selector
        actualizando_selector = True
        claves = list(modelo["perfiles"])
        selector.set_model(Gtk.StringList.new([modelo["perfiles"][clave]["nombre"] for clave in claves]))
        selector.set_selected(claves.index(modelo["activo"]))
        actualizando_selector = False
        refrescar_perfiles()
        programar_vista()

    def cambiar_perfil(control, _):
        if actualizando_selector or control.get_selected() >= len(claves):
            return
        clave = claves[control.get_selected()]
        try:
            perfiles.seleccionar(clave)
        except (OSError, ValueError) as error:
            actualizar_selector()
            mostrar_error(error)
        else:
            modelo["activo"] = clave
            estado.set_visible(False)
            refrescar_perfiles()
            programar_vista()

    def guardar_app(control, clave, ids, imagen, marca):
        perfil = modelo["perfiles"][modelo["activo"]]
        excepciones = perfil["excepciones"]
        conservar = control.get_active()
        if conservar == (clave in excepciones):
            return
        nuevas = excepciones.copy()
        if conservar:
            nuevas[clave] = ids
        else:
            nuevas.pop(clave, None)
        perfil["excepciones"] = nuevas
        try:
            guardar(modelo, perfiles.ARCHIVO)
        except OSError as error:
            perfil["excepciones"] = excepciones
            control.set_active(not conservar)
            mostrar_error(error)
        else:
            estado.set_visible(False)
            if imagen:
                imagen.actualizar(conservar)
                marca.set_opacity(float(conservar))
                control.estado_byotfast.set_text("Se conserva" if conservar else control.texto_abierta)
            programar_vista()

    def crear_control(nombre, icono, conservar, iconos, abierta):
        if not iconos:
            control = Gtk.CheckButton(label=nombre, active=conservar)
            control.add_css_class("byotfast-casilla")
            return control, None, None
        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        imagen = IconoAplicacion(icono or Gio.ThemedIcon.new("application-x-executable"), conservar)
        portada = Gtk.Overlay(child=caja)
        marca = Gtk.Label(label="✓", halign=Gtk.Align.END, valign=Gtk.Align.START,
                          opacity=float(conservar), css_classes=["byotfast-marca"])
        marca.set_can_target(False)
        portada.add_overlay(marca)
        caja.append(imagen)
        etiqueta = Gtk.Label(
            label=nombre, wrap=True, wrap_mode=Pango.WrapMode.WORD_CHAR,
            max_width_chars=12, lines=2, ellipsize=Pango.EllipsizeMode.END,
            justify=Gtk.Justification.CENTER,
        )
        caja.append(etiqueta)
        texto_abierta = "Abierta" if abierta else "Cerrada"
        estado_app = Gtk.Label(label="Se conserva" if conservar else texto_abierta, css_classes=["caption", "dim-label"])
        caja.append(estado_app)
        control = Gtk.ToggleButton(child=portada, active=conservar, width_request=128, css_classes=["byotfast-app"])
        control.estado_byotfast = estado_app
        control.texto_abierta = texto_abierta
        control.update_property([Gtk.AccessibleProperty.LABEL], [f"Conservar {nombre}"])
        return control, imagen, marca

    def dibujar():
        nonlocal pendiente, firma_vista
        pendiente = False
        iconos = cambiar_vista.get_active()
        excepciones = modelo["perfiles"][modelo["activo"]]["excepciones"]
        catalogo = {**abiertas, **instaladas}
        protegidas = {
            clave: catalogo.get(clave, (clave.removesuffix(".desktop"), ids, None))
            for clave, ids in excepciones.items()
        }
        todas = {**protegidas, **catalogo}
        botones_filtro["todas"].set_label(f"Todas  {len(todas)}")
        botones_filtro["abiertas"].set_label(f"Abiertas  {len(abiertas)}")
        botones_filtro["protegidas"].set_label(f"Se conservan  {len(protegidas)}")
        termino = buscador.get_text().strip().casefold()
        datos = {"todas": todas, "abiertas": abiertas, "protegidas": protegidas}[filtro]
        entradas = sorted((clave for clave, app in datos.items()
                           if termino in (app[0] + " " + clave).casefold()),
                          key=lambda clave: (datos[clave][0].casefold(), clave))
        vacio = ("Sin coincidencias." if termino else
                 "No se pudo consultar a KDE." if filtro == "abiertas" and consulta_fallida else
                 "Esperando la lista de KDE…" if filtro == "abiertas" and not lectura_realizada else
                 "Todavía no hay apps conservadas." if filtro == "protegidas" else
                 "No hay aplicaciones para mostrar.")
        firma = (iconos, modelo["activo"], [(clave, datos[clave], clave in abiertas) for clave in entradas], vacio if not entradas else "")
        if firma == firma_vista:
            return GLib.SOURCE_REMOVE
        firma_vista = firma
        posicion = ajuste.get_value()
        foco = ventana.get_focus()
        clave_foco = getattr(foco, "clave_byotfast", None)
        reemplazo = None
        while hijo := contenido.get_first_child():
            contenido.remove(hijo)
        if not entradas:
            contenido.append(Gtk.Label(label=vacio, xalign=0))
        else:
            lista = (Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, homogeneous=True,
                                min_children_per_line=1, max_children_per_line=32, row_spacing=8, column_spacing=8)
                     if iconos else Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE))
            contenido.append(lista)
            for clave in entradas:
                nombre, ids, icono = datos[clave]
                control, imagen, marca = crear_control(nombre, icono, clave in excepciones, iconos, clave in abiertas)
                control.clave_byotfast = clave
                control.set_tooltip_text(nombre)
                control.connect("toggled", guardar_app, clave, ids, imagen, marca)
                if clave == clave_foco:
                    reemplazo = control
                if iconos:
                    lista.append(Gtk.FlowBoxChild(child=control, focusable=False))
                else:
                    lista.append(Gtk.ListBoxRow(child=control, activatable=False, focusable=False))
        if clave_foco:
            (reemplazo or buscador).grab_focus()
        GLib.idle_add(lambda: (ajuste.set_value(posicion), GLib.SOURCE_REMOVE)[1])
        return GLib.SOURCE_REMOVE

    def programar_vista():
        nonlocal pendiente
        if not pendiente:
            pendiente = True
            GLib.idle_add(dibujar)

    def elegir_filtro(control, clave):
        nonlocal filtro
        if control.get_active():
            filtro = clave
            ajuste.set_value(0)
            programar_vista()

    for clave, boton in botones_filtro.items():
        boton.connect("toggled", elegir_filtro, clave)

    indice = {identificador.casefold(): clave for clave, (_, ids, _) in instaladas.items()
              for identificador in ids}

    def recibir(ventanas):
        nonlocal abiertas, lectura_realizada, consulta_fallida
        if ventanas is None:
            if not consulta_fallida:
                consulta_fallida = True
                abiertas = {}
                programar_vista()
            return
        nuevas = {}
        for escritorio, clase, titulo in ventanas:
            ids = [i for i in (escritorio, clase) if i]
            if not ids:
                continue
            claves_ventana = [i.casefold().removesuffix(".desktop") for i in ids]
            clave = next((indice[i] for i in claves_ventana if i in indice), None)
            if clave:
                nuevas[clave] = instaladas[clave]
            else:
                clave = "ventana:" + claves_ventana[0]
                datos = abiertas.get(clave) or nuevas.get(clave)
                nombre = datos[0] if datos else titulo or ids[0]
                anteriores = nuevas[clave][1] if clave in nuevas else []
                nuevas[clave] = (nombre, sorted(set(ids + anteriores)), None)
        if consulta_fallida or not lectura_realizada or nuevas != abiertas:
            abiertas = dict(sorted(nuevas.items(), key=lambda par: (par[1][0].casefold(), par[0])))
            lectura_realizada = True
            consulta_fallida = False
            programar_vista()

    def mostrar_vista(control):
        iconos = control.get_active()
        control.set_label("Vista de lista" if iconos else "Vista de iconos")
        programar_vista()

    cambiar_vista.connect("toggled", mostrar_vista)
    buscador.connect("search-changed", lambda _: programar_vista())
    selector.connect("notify::selected", cambiar_perfil)

    pagina_perfiles = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
    pagina_perfiles.append(Gtk.Label(label="Perfiles", xalign=0, css_classes=["title-1"]))
    paginas.add_named(Gtk.ScrolledWindow(child=pagina_perfiles, hscrollbar_policy=Gtk.PolicyType.NEVER), "perfiles")
    refrescar_perfiles = controles_perfiles(pagina_perfiles, modelo, actualizar_selector,
                                            lambda: paginas.get_visible_child_name() == "perfiles")

    botones["apps"].set_active(True)

    teclado = Gtk.EventControllerKey()
    def buscar_con_teclado(_, tecla, _codigo, modificadores):
        if tecla in (Gdk.KEY_f, Gdk.KEY_F) and modificadores & Gdk.ModifierType.CONTROL_MASK:
            campo = {"apps": buscador, "widgets": buscar_widget, "lanzadores": buscar_lanzador}.get(paginas.get_visible_child_name())
            if campo:
                campo.grab_focus()
                return True
        return False
    teclado.connect("key-pressed", buscar_con_teclado)
    ventana.add_controller(teclado)
    actualizar_selector()
    mostrar_vista(cambiar_vista)
    ventana.present()
    if not (perfiles.CARPETA / "ubicacion.json").exists():
        configurar_ubicacion(ventana, inicial=True)
    observar_ventanas(ventana, principal, recibir)
    try:
        monitor = Gio.File.new_for_path(str(perfiles.CARPETA)).monitor_directory(
            Gio.FileMonitorFlags.WATCH_MOVES, None,
        )
    except GLib.Error:
        return

    def perfil_externo(_monitor, origen, destino, _evento):
        if perfiles.ACTIVO.name not in {archivo.get_basename() for archivo in (origen, destino) if archivo}:
            return
        try:
            activo = perfiles.leer()["activo"]
        except (OSError, ValueError) as error:
            mostrar_error(error)
            return
        if activo != modelo["activo"]:
            modelo["activo"] = activo
            actualizar_selector()

    monitor.connect("changed", perfil_externo)
    ventana.connect("close-request", lambda _: (monitor.cancel(), False)[1])


def id_lanzador_anterior(identificador):
    clave = "inicio" if identificador == "inicio" else sha256(identificador.encode()).hexdigest()[:24]
    return f"org.local.Byotfast.lanzador-{clave}.desktop"


def atajos_lanzadores(instaladas):
    anteriores = {id_lanzador_anterior(clave): clave for clave in instaladas}
    registrados = atajos.lanzamientos_kde(ARCHIVO_ATAJOS_KDE, instaladas.keys() | anteriores.keys())
    resultado = {}
    for componente, teclas in registrados.items():
        resultado.setdefault(anteriores.get(componente, componente), []).extend(teclas)
    return {clave: tuple(dict.fromkeys(teclas)) for clave, teclas in resultado.items()}


def registrar_lanzador(identificador, nombre):
    inicio = identificador == "inicio"
    componente = id_lanzador_anterior(identificador)
    base = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share") / "kglobalaccel"
    base.mkdir(parents=True, exist_ok=True)
    ruta = base / componente
    titulo = f"Byotfast · {nombre}"
    orden = [sys.executable, str(Path(__file__).resolve()), "--inicio" if inicio else "--lanzar-app"]
    if not inicio:
        orden.append(identificador)
    if not ruta.exists():
        entrada = GLib.KeyFile()
        grupo = "Desktop Entry"
        for campo, valor in (("Type", "Application"), ("Name", titulo),
                             ("Exec", " ".join(map(argumento_exec, orden)))):
            entrada.set_string(grupo, campo, valor)
        entrada.set_boolean(grupo, "X-KDE-GlobalAccel-CommandShortcut", True)
        entrada.set_boolean(grupo, "NoDisplay", True)
        guardar_lanzador_atajo(entrada, ruta)
    return [componente, "_launch", titulo, titulo], orden


def ejecutar_lanzador(identificador):
    app = Gio.DesktopAppInfo.new(identificador)
    if not app or not app.launch([], None):
        raise ValueError("No se pudo abrir la aplicación.")


def abrir_inicio(app):
    ventana = Gtk.ApplicationWindow(application=app, title="Inicio de Byotfast")
    ventana.set_default_size(500, 460)
    ventana.add_css_class("byotfast-window")
    estilos = Gtk.CssProvider()
    pantalla = ventana.get_display()
    Gtk.StyleContext.add_provider_for_display(pantalla, estilos, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
    try:
        aplicar_apariencia(leer_apariencia(), estilos)
    except (OSError, ValueError):
        pass
    ventana.connect("close-request", lambda _: (Gtk.StyleContext.remove_provider_for_display(pantalla, estilos), False)[1])
    caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, margin_top=14, margin_bottom=14,
                  margin_start=14, margin_end=14)
    entrada = Gtk.SearchEntry(placeholder_text="Buscar aplicaciones…")
    caja.append(entrada)
    favoritas = Gtk.Box(spacing=6)
    caja.append(favoritas)
    lista = Gtk.ListBox(selection_mode=Gtk.SelectionMode.SINGLE)
    caja.append(Gtk.ScrolledWindow(child=lista, vexpand=True, hscrollbar_policy=Gtk.PolicyType.NEVER))
    estado = Gtk.Label(xalign=0, wrap=True)
    caja.append(estado)
    instaladas = aplicaciones_instaladas()

    def lanzar(clave):
        try:
            ejecutar_lanzador(clave)
        except (GLib.Error, ValueError, TypeError) as error:
            estado.set_text(str(error))
        else:
            ventana.close()

    try:
        asignadas = atajos_lanzadores(instaladas)
    except (OSError, UnicodeError):
        asignadas = {}
    for clave in [k for k in asignadas if k in instaladas][:4]:
        boton = Gtk.Button(label=instaladas[clave][0])
        boton.connect("clicked", lambda _, id_app=clave: lanzar(id_app))
        favoritas.append(boton)

    def mostrar(*_):
        termino = entrada.get_text().strip().casefold()
        favoritas.set_visible(not termino and favoritas.get_first_child() is not None)
        while fila := lista.get_first_child():
            lista.remove(fila)
        for clave, (nombre, _, icono) in instaladas.items():
            if termino not in nombre.casefold():
                continue
            linea = Gtk.Box(spacing=10, margin_start=8, margin_top=4, margin_bottom=4)
            linea.append(Gtk.Image(gicon=icono, pixel_size=24))
            linea.append(Gtk.Label(label=nombre, xalign=0))
            fila = Gtk.ListBoxRow(child=linea)
            fila.id_app = clave
            lista.append(fila)
        lista.select_row(lista.get_row_at_index(0))

    def teclado(_, tecla, _codigo, _mods):
        if tecla == Gdk.KEY_Escape:
            ventana.close()
            return True
        if tecla in (Gdk.KEY_Down, Gdk.KEY_Up):
            actual = lista.get_selected_row()
            indice = actual.get_index() if actual else -1
            siguiente = lista.get_row_at_index(max(0, indice + (1 if tecla == Gdk.KEY_Down else -1)))
            if siguiente:
                lista.select_row(siguiente)
                siguiente.grab_focus()
            return True
        return False

    controller = Gtk.EventControllerKey()
    controller.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
    controller.connect("key-pressed", teclado)
    ventana.add_controller(controller)
    lista.connect("row-activated", lambda _, fila: lanzar(fila.id_app))
    entrada.connect("activate", lambda _: lanzar(fila.id_app) if (fila := lista.get_selected_row()) else None)
    entrada.connect("search-changed", mostrar)
    ventana.set_child(caja)
    mostrar()
    ventana.present()
    entrada.grab_focus()


def crear_lanzadores(ventana, instaladas):
    panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
    cabecera = Gtk.Box(spacing=8)
    cabecera.append(Gtk.Label(label="Lanzadores", xalign=0, hexpand=True, css_classes=["title-1"]))
    probar = Gtk.Button(label="Probar menú de inicio")
    cabecera.append(probar)
    panel.append(cabecera)
    barra = Gtk.Box(spacing=6)
    buscador = Gtk.SearchEntry(placeholder_text="Buscar apps…", hexpand=True)
    vista = Gtk.ToggleButton(label="Vista de lista")
    barra.append(buscador)
    barra.append(vista)
    panel.append(barra)
    filtro = Gtk.ToggleButton(label="Con atajo", halign=Gtk.Align.START, css_classes=["byotfast-nav"])
    panel.append(filtro)
    desplazamiento = Gtk.ScrolledWindow(vexpand=True, hscrollbar_policy=Gtk.PolicyType.EXTERNAL, propagate_natural_width=False, propagate_natural_height=False)
    panel.append(desplazamiento)
    ajustes_inicio = Gtk.Expander(label="Menú de inicio")
    panel.append(ajustes_inicio)
    estado = Gtk.Label(xalign=0, wrap=True)
    panel.append(estado)
    existentes = {}
    archivo_kde = ARCHIVO_ATAJOS_KDE

    def cargar_existentes():
        try:
            return atajos_lanzadores(instaladas)
        except (OSError, UnicodeError):
            return {}

    def configurar(_, clave, nombre):
        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin_top=14, margin_bottom=14,
                      margin_start=14, margin_end=14)
        presentar, _cerrar = dialogo_interno(ventana, f"Atajo · {nombre}", 485, caja)
        accion = [clave, "_launch", nombre, "Lanzar"]
        anterior = [id_lanzador_anterior(clave), "_launch", f"Byotfast · {nombre}", f"Byotfast · {nombre}"]

        def reflejar(texto):
            if texto:
                existentes[clave] = (texto,)
            else:
                existentes.pop(clave, None)
            mostrar()

        controles_atajo(caja, accion, None, quitar=True, al_cambiar=reflejar,
                        preparar=lambda: atajos.integrar_lanzador(accion, anterior))
        presentar()

    def mostrar(*_):
        lista = vista.get_active()
        vista.set_label("Vista de iconos" if lista else "Vista de lista")
        contenido = (Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=5, valign=Gtk.Align.START) if lista else
                     Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, homogeneous=True, max_children_per_line=32,
                                 row_spacing=6, column_spacing=6, valign=Gtk.Align.START))
        desplazamiento.set_child(contenido)
        termino = buscador.get_text().strip().casefold()
        for clave, (nombre, _, icono) in instaladas.items():
            teclas = existentes.get(clave, ())
            if termino not in nombre.casefold() or (filtro.get_active() and not teclas):
                continue
            caja = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL if lista else Gtk.Orientation.VERTICAL, spacing=6)
            caja.append(IconoAplicacion(icono or Gio.ThemedIcon.new("application-x-executable"),
                                       bool(teclas), 22 if lista else 36))
            caja.append(Gtk.Label(label=nombre, xalign=0 if lista else 0.5, hexpand=lista,
                                 ellipsize=Pango.EllipsizeMode.END, max_width_chars=19))
            caja.append(Gtk.Label(label=" · ".join(teclas) or "Sin atajo", ellipsize=Pango.EllipsizeMode.END,
                                 max_width_chars=23, css_classes=["caption", "dim-label"]))
            boton = Gtk.Button(child=caja, css_classes=["byotfast-app"])
            if not lista:
                boton.set_size_request(128, -1)
            if teclas:
                boton.add_css_class("byotfast-con-atajo")
                boton.set_tooltip_text(" · ".join(teclas))
            boton.connect("clicked", configurar, clave, nombre)
            contenido.append(boton)

    def abrir_menu(_):
        try:
            Gio.Subprocess.new([sys.executable, str(Path(__file__).resolve()), "--inicio"], Gio.SubprocessFlags.NONE)
        except GLib.Error as error:
            estado.set_text(str(error))

    def preparar_inicio(control, _):
        if not control.get_expanded() or control.get_child():
            return
        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6, margin_top=6)
        control.set_child(caja)
        try:
            accion, orden = registrar_lanzador("inicio", "Menú de inicio")
            controles_atajo(caja, accion, orden, quitar=True)
            sugerido = Gtk.Button(label="Usar Super + Espacio", halign=Gtk.Align.START)
            caja.append(sugerido)

            def predeterminado(_):
                try:
                    atajos.asignar("Meta+Espacio", accion)
                except (GLib.Error, ValueError, OSError) as error:
                    estado.set_text(str(error))
                else:
                    estado.set_text("Atajo del menú guardado.")
                    control.set_child(None)
                    preparar_inicio(control, None)
            sugerido.connect("clicked", predeterminado)
        except OSError as error:
            estado.set_text(str(error))

    ajustes_inicio.connect("notify::expanded", preparar_inicio)
    probar.connect("clicked", abrir_menu)
    buscador.connect("search-changed", mostrar)
    vista.connect("toggled", mostrar)
    filtro.connect("toggled", mostrar)
    monitor = None

    def refrescar(*_):
        nuevos = cargar_existentes()
        if nuevos != existentes or desplazamiento.get_child() is None:
            existentes.clear()
            existentes.update(nuevos)
            mostrar()

    def cambio_kde(_monitor, archivo, destino, _evento):
        if any(ruta and ruta.get_basename() == archivo_kde.name for ruta in (archivo, destino)):
            refrescar()

    def al_mostrar(_):
        nonlocal monitor
        refrescar()
        try:
            monitor = Gio.File.new_for_path(str(archivo_kde.parent)).monitor_directory(Gio.FileMonitorFlags.WATCH_MOVES, None)
            monitor.connect("changed", cambio_kde)
        except GLib.Error:
            monitor = None

    def al_ocultar(_):
        nonlocal monitor
        if monitor:
            monitor.cancel()
            monitor = None

    panel.connect("map", al_mostrar)
    panel.connect("unmap", al_ocultar)
    return panel, buscador


def crear_ajustes(preferencias, estilos, error_apariencia):
    panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
    panel.append(Gtk.Label(label="Ajustes", xalign=0, css_classes=["title-1"]))

    navegacion = Gtk.Box(spacing=6)
    panel.append(navegacion)
    secciones = Gtk.Stack(vexpand=True, hhomogeneous=False, vhomogeneous=False)
    panel.append(secciones)
    grupos = {}
    for clave, nombre in (("apariencia", "Apariencia"), ("atajos", "Atajos"), ("limpieza", "Limpieza")):
        grupo = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        grupos[clave] = grupo
        secciones.add_named(grupo, clave)
        boton = Gtk.ToggleButton(label=nombre, css_classes=["byotfast-nav"])
        anterior = navegacion.get_first_child()
        if anterior:
            boton.set_group(anterior)
        else:
            boton.set_active(True)
        boton.connect("toggled", lambda control, vista=clave: secciones.set_visible_child_name(vista) if control.get_active() else None)
        navegacion.append(boton)

    ubicacion = Gtk.Button(label="Configurar ciudad", halign=Gtk.Align.START)
    ubicacion.connect("clicked", lambda control: configurar_ubicacion(control.get_root()))
    grupos["apariencia"].append(ubicacion)
    apariencia = grupos["apariencia"]
    ancho_selectores = Gtk.SizeGroup(mode=Gtk.SizeGroupMode.HORIZONTAL)
    selectores = []
    for nombre, clave, valores in (("Tema", "tema", TEMAS), ("Acento", "acento", ACENTOS)):
        fila = Gtk.Box(spacing=12)
        etiqueta = Gtk.Label(label=nombre, xalign=0, hexpand=True)
        opciones = list(valores)
        selector = Gtk.DropDown.new_from_strings(opciones)
        ancho_selectores.add_widget(selector)
        if clave == "acento":
            selector.set_factory(fabrica_acentos())
            selector.set_list_factory(fabrica_acentos())
        selector.set_selected(opciones.index(preferencias[clave]))
        selector.update_property([Gtk.AccessibleProperty.LABEL], [nombre])
        fila.append(etiqueta)
        fila.append(selector)
        apariencia.append(fila)
        selectores.append((selector, clave, opciones))
    estado = Gtk.Label(label=error_apariencia, xalign=0, wrap=True, visible=bool(error_apariencia))
    apariencia.append(estado)

    def cambiar(selector, _, clave, opciones):
        valor = opciones[selector.get_selected()]
        if valor == preferencias[clave]:
            return
        nuevas = {**preferencias, clave: valor}
        try:
            guardar(nuevas, APARIENCIA)
        except OSError as error:
            selector.set_selected(opciones.index(preferencias[clave]))
            estado.set_text(f"No se pudo guardar la apariencia. {error}")
            estado.set_visible(True)
            return
        perfiles.avisar_widgets("AparienciaCambiada", widgets.apariencia())
        preferencias.update(nuevas)
        aplicar_apariencia(preferencias, estilos)
        estado.set_visible(False)

    for selector, clave, opciones in selectores:
        selector.connect("notify::selected", cambiar, clave, opciones)
    atajos_generales = grupos["atajos"]
    encabezado_ajustes(atajos_generales, "Cerrar ventanas", "El atajo ejecuta el perfil activo.")
    controles_atajo(atajos_generales, atajos.ACCION, [str(RUTA_COMANDO)])
    encabezado_ajustes(atajos_generales, "Limpiar archivos")
    controles_atajo(atajos_generales, atajos.LIMPIEZA, [sys.executable, str(Path(__file__).resolve()), "--limpiar"])
    atajos_generales.append(controles_atajos_panel())
    controles_limpieza(grupos["limpieza"], incluir_atajo=False)
    return Gtk.ScrolledWindow(child=panel, hscrollbar_policy=Gtk.PolicyType.NEVER)


def evaluar_plasma(script):
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    respuesta, = bus.call_sync(
        "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell", "evaluateScript",
        GLib.Variant("(s)", (script,)), GLib.VariantType.new("(s)"),
        Gio.DBusCallFlags.NONE, 5000, None,
    ).unpack()
    return respuesta


def controles_atajos_panel():
    nombres = {widgets.PERFIL: "Perfil", widgets.LIMPIEZA: "Limpieza"}
    nombres.update({plugin: nombre for nombre, _, plugin, _ in widgets.UTILIDADES})
    seccion = Gtk.Expander(label="Desplegar widgets del panel")
    caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin_top=6)
    seccion.set_child(caja)

    def cargar(control, _):
        if not control.get_expanded():
            return
        while hijo := caja.get_first_child():
            caja.remove(hijo)
        try:
            instalados = json.loads(evaluar_plasma("""
                const permitidos = %s;
                print(JSON.stringify(panels().flatMap((panel, indice) =>
                    panel.widgets().filter(widget => permitidos.includes(widget.type))
                        .map(widget => [widget.id, widget.type, indice + 1]))));
            """ % json.dumps(list(nombres))))
        except (GLib.Error, ValueError):
            caja.append(Gtk.Label(label="No se pudieron consultar los paneles de Plasma.", xalign=0))
            return
        if not instalados:
            caja.append(Gtk.Label(label="Añade un widget de Byotfast al panel para asignarle un atajo.",
                                  xalign=0, wrap=True))
            return
        etiquetas = [f"{nombres[tipo]} · Panel {numero}" for _, tipo, numero in instalados]
        opciones = [etiqueta if etiquetas.count(etiqueta) == 1 else f"{etiqueta} · #{identidad}"
                    for etiqueta, (identidad, _, _) in zip(etiquetas, instalados)]
        selector = Gtk.DropDown.new_from_strings(opciones)
        selector.update_property([Gtk.AccessibleProperty.LABEL], ["Widget del panel"])
        caja.append(selector)
        editor = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        caja.append(editor)

        def editar(*_):
            while hijo := editor.get_first_child():
                editor.remove(hijo)
            identidad = instalados[selector.get_selected()][0]
            controles_atajo(editor, None, None, quitar=True,
                            atajo_panel=lambda texto: cambiar_atajo_panel(identidad, texto))

        selector.connect("notify::selected", editar)
        editar()

    seccion.connect("notify::expanded", cargar)
    return seccion


def cambiar_atajo_panel(identidad, texto):
    def consultar(nuevo=None):
        respuesta = evaluar_plasma("""
            const widget = panels().flatMap(panel => panel.widgets())
                .find(widget => widget.id === %s && widget.type.startsWith("org.local.Byotfast."));
            const nuevo = %s;
            if (widget && nuevo !== null)
                widget.globalShortcut = nuevo;
            print(JSON.stringify(widget ? widget.globalShortcut : null));
        """ % (json.dumps(identidad), json.dumps(nuevo)))
        actual = json.loads(respuesta)
        if actual is None:
            raise ValueError("El widget ya no está en el panel.")
        return actual

    actual = consultar()
    if texto is None:
        return actual
    nuevo = texto.replace("NumPad ", "Num+").replace("KP_", "Num+").replace("ESPACIO", "Space").replace("SPACE", "Space")
    if nuevo == actual:
        return actual
    if texto:
        valor = atajos.codigo(texto)
        if not atajos.pedir("globalShortcutAvailable", "((ai)s)", ([valor, 0, 0, 0],), "")[0]:
            raise ValueError("Esa combinación ya está en uso. Elige otra.")
    resultado = consultar(nuevo)
    if bool(resultado) != bool(nuevo):
        raise ValueError("Plasma no aplicó el cambio de atajo.")
    return resultado


def consultar_widgets(identificadores, cambio=None):
    if cambio and cambio[0] not in identificadores:
        raise ValueError("Widget desconocido.")
    script = """
        const destinos = [desktopForScreen(0), panels()[0]];
        const plugins = %s;
        const cambio = %s;
        if (cambio) {
            const [plugin, indice, agregar] = cambio;
            const destino = destinos[indice];
            if (!destino)
                throw new Error("El destino no está disponible en Plasma.");
            const presentes = destino.widgets(plugin);
            const posiciones = indice === 0 ? ConfigFile("byotfast-widgetsrc", "Escritorio-" + destino.id) : null;
            if (agregar && !presentes.length) {
                let anterior = null;
                if (posiciones) {
                    try {
                        anterior = JSON.parse(posiciones.readEntry(plugin));
                    } catch (_) {
                        // El primer uso no tiene una posición guardada.
                    }
                }
                const rect = anterior && anterior.rect;
                const restaurar = Array.isArray(rect) && rect.length === 4 && rect.every(Number.isFinite)
                    && rect[0] >= 0 && rect[1] >= 0 && rect[2] > 0 && rect[3] > 0;
                const widget = restaurar ? destino.addWidget(plugin, ...rect) : destino.addWidget(plugin);
                if (!widget)
                    throw new Error("No se pudo añadir el widget.");
                if (restaurar) {
                    widget.currentConfigGroup = ["General"];
                    widget.writeConfig("compacto", anterior.compacto === true);
                    widget.writeConfig("anchoUsuario", anterior.compacto ? anterior.anchoUsuario : Math.round(rect[2]));
                    widget.writeConfig("altoUsuario", anterior.compacto ? anterior.altoUsuario : Math.round(rect[3]));
                }
            } else if (!agregar) {
                if (posiciones && presentes.length) {
                    const widget = presentes[0];
                    const geometria = widget.geometry;
                    if (geometria && geometria.width > 0 && geometria.height > 0) {
                        widget.currentConfigGroup = ["General"];
                        posiciones.writeEntry(plugin, JSON.stringify({
                            rect: [geometria.x, geometria.y, geometria.width, geometria.height],
                            compacto: widget.readConfig("compacto", false),
                            anchoUsuario: widget.readConfig("anchoUsuario", 0),
                            altoUsuario: widget.readConfig("altoUsuario", 0)
                        }));
                    }
                }
                for (const widget of presentes)
                    widget.remove();
            }
        }
        print(JSON.stringify(destinos.map(destino =>
            destino ? plugins.filter(plugin => destino.widgets(plugin).length) : null)));
    """ % (json.dumps(identificadores), json.dumps(cambio))
    destinos = json.loads(evaluar_plasma(script))
    if not isinstance(destinos, list) or len(destinos) != 2:
        raise ValueError("Plasma devolvió un estado inesperado.")
    return destinos


def dibujar_anillo(area, contexto, ancho, alto, porcentaje):
    import math

    radio = min(ancho, alto) / 2 - 5
    if radio <= 0:
        return
    color = area.get_color()
    contexto.set_line_width(4)
    contexto.set_source_rgba(color.red, color.green, color.blue, 0.22)
    contexto.arc(ancho / 2, alto / 2, radio, 0, 2 * math.pi)
    contexto.stroke()
    contexto.set_source_rgba(color.red, color.green, color.blue, color.alpha)
    inicio = -math.pi / 2
    contexto.arc(ancho / 2, alto / 2, radio, inicio, inicio + 2 * math.pi * porcentaje / 100)
    contexto.stroke()


def icono_catalogo(icono):
    if icono.startswith("org.local.Byotfast."):
        icono += "-symbolic"
    elif icono == ID_APP:
        icono = "media-playback-start-symbolic"
    return Gtk.Image.new_from_icon_name(icono)


def muestra_widget(titulo, icono, tipo, compacto=False):
    caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=5, css_classes=["byotfast-preview"])
    encabezado = Gtk.Box(spacing=5)
    encabezado.append(icono_catalogo(icono))
    encabezado.append(Gtk.Label(label=titulo, xalign=0, css_classes=["heading"]))
    cambiar_vista = None
    if tipo in ("clima", "temporizador", "calculadora"):
        ayuda = {"clima": "Alternar pronóstico por hora", "temporizador": "Alternar cronómetro",
                 "calculadora": "Alternar historial"}[tipo]
        cambiar_vista = Gtk.ToggleButton(label="●", tooltip_text=ayuda,
                                         css_classes=["flat", "byotfast-preview-switch"])
        cambiar_vista.update_property([Gtk.AccessibleProperty.LABEL], [ayuda])
        encabezado.append(cambiar_vista)
    encabezado.append(Gtk.Box(hexpand=True))
    if not compacto:
        encabezado.append(Gtk.Box(valign=Gtk.Align.CENTER, css_classes=["byotfast-preview-dot"]))
    caja.append(encabezado)
    contenido = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=5, valign=Gtk.Align.CENTER, vexpand=True)
    caja.append(contenido)
    medidas = {
        "rendimiento": ((12, "CPU"), (38, "RAM")),
        "bateria": ((92, "Equipo"), (74, "Audífonos")),
        "discos": ((76, "/"), (52, "EFI")),
    }
    if tipo in medidas:
        fila = Gtk.Box(spacing=10, halign=Gtk.Align.CENTER)
        for indice, (porcentaje, nombre) in enumerate(medidas[tipo]):
            grupo = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            capa = Gtk.Overlay()
            grafico = Gtk.DrawingArea(content_width=42 if compacto else 48, content_height=42 if compacto else 48,
                                      css_classes=["byotfast-accent"])
            grafico.set_draw_func(dibujar_anillo, porcentaje)
            capa.set_child(grafico)
            capa.add_overlay(Gtk.Label(label=f"{porcentaje} %", css_classes=["caption", "heading"]))
            grupo.append(capa)
            grupo.append(Gtk.Label(label=nombre, css_classes=["caption"]))
            detalles = {"bateria": ("Carga completa", "Bluetooth"), "discos": ("150 GiB libres", "50 MiB libres")}
            if tipo in detalles:
                grupo.append(Gtk.Label(label=detalles[tipo][indice], css_classes=["caption", "dim-label"]))
            fila.append(grupo)
        contenido.append(fila)
        return caja

    def texto(valor, clase="caption", destino=contenido):
        destino.append(Gtk.Label(label=valor, wrap=True, css_classes=[clase]))

    def control(valor, destino=contenido):
        destino.append(Gtk.Label(label=valor, css_classes=["caption", "byotfast-preview-key"]))

    def datos_fila(nombre, valor):
        fila = Gtk.Box(spacing=4)
        fila.append(Gtk.Label(label=nombre, xalign=0, hexpand=True, css_classes=["caption"]))
        fila.append(Gtk.Label(label=valor, css_classes=["caption", "heading"]))
        contenido.append(fila)

    if tipo == "controles":
        fila = Gtk.Box(spacing=6, halign=Gtk.Align.CENTER)
        for simbolo in ("network-wireless-symbolic", "bluetooth-active-symbolic",
                        "audio-input-microphone-symbolic"):
            fila.append(Gtk.Image(icon_name=simbolo, pixel_size=18))
        contenido.append(fila)
        datos_fila("Volumen", "65 %")
        contenido.append(Gtk.ProgressBar(fraction=0.65))
    elif tipo == "clima":
        vistas = Gtk.Stack(transition_type=Gtk.StackTransitionType.NONE)
        actual = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        actual.append(Gtk.Label(label="Ciudad", css_classes=["heading"]))
        lectura = Gtk.Box(spacing=6, halign=Gtk.Align.CENTER)
        lectura.append(Gtk.Image(icon_name="weather-few-clouds-symbolic", pixel_size=25))
        lectura.append(Gtk.Label(label="24°", css_classes=["byotfast-weather-temperature"]))
        actual.append(lectura)
        actual.append(Gtk.Label(label="Nublado"))
        actual.append(Gtk.Label(label="Máx. 28°    Mín. 24°", css_classes=["caption"]))
        vistas.add_named(actual, "actual")
        horas = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        horas.append(Gtk.Label(label="Próximas horas", css_classes=["heading"]))
        fila = Gtk.Box(spacing=6, homogeneous=True)
        for hora, grados in (("09:00", "24°"), ("10:00", "25°"), ("11:00", "26°")):
            tramo = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3, css_classes=["byotfast-preview-key"])
            tramo.append(Gtk.Label(label=hora, css_classes=["caption"]))
            tramo.append(Gtk.Label(label=grados, css_classes=["heading"]))
            fila.append(tramo)
        horas.append(fila)
        vistas.add_named(horas, "horas")
        contenido.append(vistas)
        cambiar_vista.connect("toggled", lambda boton: vistas.set_visible_child_name("horas" if boton.get_active() else "actual"))
    elif tipo == "fotos":
        control("Añadir foto")
    elif tipo == "busquedagoogle":
        contenido.append(Gtk.Entry(placeholder_text="Buscar en Google"))
    elif tipo == "relojmoderno":
        texto("SUNDAY", "title-1")
        texto("22 NOV 2026")
        texto("– 09:15 AM –")
    elif tipo == "reloj":
        ahora = datetime.now()
        caja.cifra = Gtk.Label(label=ahora.strftime("%H:%M"), css_classes=["byotfast-weather-temperature"])
        contenido.append(caja.cifra)
        texto(GLib.DateTime.new_now_local().format("%a %d %b").capitalize())
    elif tipo == "temporizador":
        cifra = Gtk.Label(label="05:00", css_classes=["byotfast-weather-temperature"])
        contenido.append(cifra)
        duracion = Gtk.Label(label="Minutos ▾      −  5  +", css_classes=["caption", "byotfast-preview-key"])
        contenido.append(duracion)
        acciones = Gtk.Box(spacing=5, homogeneous=True)
        for etiqueta in ("Iniciar", "Reiniciar"):
            control(etiqueta, acciones)
        contenido.append(acciones)

        def cambiar_modo(boton):
            cronometro = boton.get_active()
            cifra.set_text("00:00.000" if cronometro else "05:00")
            duracion.set_visible(not cronometro)
        cambiar_vista.connect("toggled", cambiar_modo)
    elif tipo == "musica":
        pista = Gtk.Box(spacing=7, halign=Gtk.Align.CENTER)
        pista.append(Gtk.Label(label="♫", css_classes=["byotfast-cover"]))
        info = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        info.append(Gtk.Label(label="Canción", xalign=0, css_classes=["heading"]))
        info.append(Gtk.Label(label="Artista", xalign=0, css_classes=["caption"]))
        info.append(Gtk.Label(label="Álbum", xalign=0, css_classes=["caption", "dim-label"]))
        pista.append(info)
        contenido.append(pista)
        contenido.append(Gtk.ProgressBar(fraction=0.35))
        transporte = Gtk.Box(spacing=4, halign=Gtk.Align.CENTER)
        for icono_media in ("media-skip-backward-symbolic", "media-playback-start-symbolic", "media-skip-forward-symbolic"):
            transporte.append(Gtk.Image(icon_name=icono_media, pixel_size=14, css_classes=["byotfast-preview-key"]))
        contenido.append(transporte)
    elif tipo == "calendario":
        ahora = datetime.now()
        import calendar
        texto("‹   " + ahora.strftime("%B %Y").capitalize() + "   ›")
        rejilla = Gtk.Grid(column_homogeneous=True, row_spacing=1)
        for columna, inicial in enumerate("LMMJVSD"):
            rejilla.attach(Gtk.Label(label=inicial, css_classes=["caption", "dim-label"]), columna, 0, 1, 1)
        for fila, semana in enumerate(calendar.monthcalendar(ahora.year, ahora.month), 1):
            for columna, dia in enumerate(semana):
                if dia:
                    clases = ["caption", "byotfast-accent"] if dia == ahora.day else ["caption"]
                    rejilla.attach(Gtk.Label(label=str(dia), css_classes=clases), columna, fila, 1, 1)
        contenido.append(rejilla)
    elif tipo == "calculadora":
        vistas = Gtk.Stack(transition_type=Gtk.StackTransitionType.NONE)
        teclado = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
        teclado.append(Gtk.Label(label="0", xalign=1, css_classes=["heading", "byotfast-preview-key"]))
        rejilla = Gtk.Grid(column_homogeneous=True, row_spacing=2, column_spacing=2)
        for indice, tecla in enumerate(("C", "(", ")", "⌫", *"789÷456×123−0.=+")):
            rejilla.attach(Gtk.Label(label=tecla, css_classes=["caption", "byotfast-preview-key"]),
                           indice % 4, indice // 4, 1, 1)
        teclado.append(rejilla)
        vistas.add_named(teclado, "teclado")
        historial = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        texto("Historial", "heading", historial)
        control("2 × 3 = 6", historial)
        vistas.add_named(historial, "historial")
        contenido.append(vistas)
        cambiar_vista.connect("toggled", lambda boton: vistas.set_visible_child_name("historial" if boton.get_active() else "teclado"))
    elif tipo == "perfilactivo":
        control("Perfil activo   ▾")
        teclas = Gtk.Box(spacing=3, halign=Gtk.Align.CENTER)
        for tecla in ("Ctrl", "Meta", "NumPad 0"):
            control(tecla, teclas)
        contenido.append(teclas)
    elif tipo == "revisarlimpieza":
        datos_fila("Temporales", "12 MiB")
        datos_fila("Papelera", "19 MiB")
        control("Revisar limpieza")
    elif tipo == "notas":
        contenido.append(Gtk.Label(label="Ideas", xalign=0, css_classes=["heading"]))
        contenido.append(Gtk.Label(label="Preparar la próxima versión.", xalign=0, wrap=True, css_classes=["caption"]))
        datos_fila("B   𝑰   ☰", "‹  1 / 3  ›")
    elif tipo == "tareas":
        control("Nueva tarea   +")
        datos_fila("☐ Enviar propuesta", "")
        datos_fila("☑ Revisar diseño", "")
    return caja


def crear_catalogo(ventana):
    panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
    cabecera = Gtk.Box(spacing=8)
    cabecera.append(Gtk.Label(label="Widgets", xalign=0, hexpand=True, css_classes=["title-1"]))
    cabecera.append(boton_info("Añadir widgets al panel",
                             "Panel añade el widget al primer panel de Plasma. Para elegir otro, usa Añadir elementos gráficos desde ese panel."))
    panel.append(cabecera)
    buscador = Gtk.SearchEntry(placeholder_text="Buscar widgets")
    panel.append(buscador)
    cuerpo = Gtk.Box(spacing=12, vexpand=True)
    tarjetas = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE, valign=Gtk.Align.START, css_classes=["byotfast-catalogo"])
    cuerpo.append(Gtk.ScrolledWindow(child=tarjetas, vexpand=True, hexpand=True,
                                      hscrollbar_policy=Gtk.PolicyType.NEVER, overlay_scrolling=False))
    detalle = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, width_request=210,
                      css_classes=["byotfast-widget"], valign=Gtk.Align.START)
    cuerpo.append(Gtk.ScrolledWindow(child=detalle, hscrollbar_policy=Gtk.PolicyType.NEVER, min_content_width=235))
    panel.append(cuerpo)
    vista_actual = None
    reloj_vista = 0
    titulo_detalle = Gtk.Label(xalign=0, css_classes=["heading"])
    detalle.append(titulo_detalle)
    muestra_escritorio = Gtk.AspectFrame(ratio=1, obey_child=False, width_request=176, height_request=176,
                                         halign=Gtk.Align.CENTER)
    detalle.append(Gtk.Label(label="Escritorio", xalign=0, css_classes=["caption"]))
    detalle.append(muestra_escritorio)
    detalle.append(Gtk.Label(label="Panel", xalign=0, css_classes=["caption"]))
    emergente = Gtk.Revealer(reveal_child=True, transition_duration=0)
    tarjeta_panel = Gtk.AspectFrame(ratio=1, obey_child=False, width_request=164, height_request=164,
                                   halign=Gtk.Align.CENTER)
    emergente.set_child(tarjeta_panel)
    detalle.append(emergente)
    acceso = Gtk.Button(halign=Gtk.Align.CENTER, css_classes=["byotfast-panel-demo"])
    acceso.connect("clicked", lambda _: emergente.set_reveal_child(not emergente.get_reveal_child()))
    detalle.append(acceso)
    descripcion_detalle = Gtk.Label(xalign=0, wrap=True, max_width_chars=24, css_classes=["caption"])
    detalle.append(descripcion_detalle)
    revisar = Gtk.Button(label="Revisar limpieza", visible=False)
    detalle.append(revisar)
    fuente = Gtk.LinkButton(uri="https://open-meteo.com/", label="Datos de Open-Meteo", visible=False)
    detalle.append(fuente)
    sin_resultados = Gtk.Label(label="No hay widgets que coincidan.", xalign=0, visible=False)
    panel.append(sin_resultados)
    estado = Gtk.Label(xalign=0, wrap=True, visible=False)
    panel.append(estado)

    def informar(mensaje):
        estado.set_text(mensaje)
        estado.set_visible(True)

    botones_destino = {}

    def sincronizar(destinos):
        for (identificador, indice), (boton, titulo, destino) in botones_destino.items():
            presentes = destinos[indice]
            activo = identificador in (presentes or ())
            boton.set_active(activo)
            boton.set_sensitive(presentes is not None)
            accion = f"Quitar {titulo} de {destino}" if activo else f"Añadir {titulo} a {destino}"
            boton.set_tooltip_text(accion)
            boton.update_property([Gtk.AccessibleProperty.LABEL], [accion])

    def actualizar():
        try:
            sincronizar(consultar_widgets(identificadores))
        except (GLib.Error, ValueError) as error:
            informar(f"No se pudo consultar dónde están los widgets. {error}")

    def alternar(boton, identificador, indice):
        agregar = boton.get_active()
        try:
            destinos = consultar_widgets(identificadores, (identificador, indice, agregar))
        except (GLib.Error, ValueError) as error:
            boton.set_active(not agregar)
            informar(f"KDE no pudo cambiar el widget. {error}")
        else:
            sincronizar(destinos)
            presente = identificador in (destinos[indice] or ())
            if presente == agregar:
                informar("Widget añadido." if presente else "Widget quitado.")
            else:
                GLib.timeout_add(350, lambda: (actualizar(), GLib.SOURCE_REMOVE)[1])

    entradas = (
        ("Perfil", "org.local.Byotfast.Perfil", widgets.PERFIL, "Cambia el perfil activo desde el escritorio o el panel."),
        ("Limpieza", "org.local.Byotfast.Papelera", widgets.LIMPIEZA, "Consulta temporales y papelera."),
        *widgets.UTILIDADES,
    )
    identificadores = [entrada[2] for entrada in entradas]
    resumen_panel = {
        "perfilactivo": "Perfil activo", "revisarlimpieza": "19 MiB", "reloj": "00:00", "relojmoderno": "09:15", "calendario": "22",
        "controles": "", "notas": "", "rendimiento": "CPU 12 %", "temporizador": "05:00", "tareas": "1", "bateria": "92 %",
        "clima": "24°", "musica": "Canción  ·  ▶", "discos": "150 GiB", "calculadora": "", "fotos": "", "busquedagoogle": "",
    }
    cifras = []

    def previsualizar(titulo, identificador, descripcion):
        nonlocal vista_actual, reloj_vista
        if vista_actual == identificador:
            return
        vista_actual = identificador
        if reloj_vista:
            GLib.source_remove(reloj_vista)
            reloj_vista = 0
        tipo = identificador.rsplit(".", 1)[-1]
        icono = next(entrada[1] for entrada in entradas if entrada[2] == identificador)
        titulo_detalle.set_text(titulo)
        cifras.clear()
        for destino in (muestra_escritorio, tarjeta_panel):
            muestra = muestra_widget(titulo, icono, tipo, compacto=destino == tarjeta_panel)
            destino.set_child(muestra)
            if tipo == "reloj":
                cifras.append(muestra.cifra)
        barra = Gtk.Box(spacing=4)
        barra.append(icono_catalogo(icono))
        dato = Gtk.Label(label=resumen_panel[tipo], css_classes=["caption"])
        barra.append(dato)
        acceso.set_child(barra)
        if tipo == "reloj":
            cifras.append(dato)
            if panel.get_mapped():
                actualizar_reloj()
            else:
                dato.set_text(datetime.now().strftime("%H:%M"))
        acceso.update_property([Gtk.AccessibleProperty.LABEL], [f"Abrir o cerrar la vista de {titulo}"])
        emergente.set_reveal_child(True)
        descripcion_detalle.set_text(descripcion)
        revisar.set_visible(identificador == widgets.LIMPIEZA)
        fuente.set_visible(tipo == "clima")

    def abrir_limpieza(_):
        try:
            Gio.Subprocess.new([sys.executable, str(Path(__file__).resolve()), "--revisar-limpieza"], Gio.SubprocessFlags.NONE)
        except GLib.Error as error:
            informar(str(error))
    revisar.connect("clicked", abrir_limpieza)

    for titulo, icono, identificador, descripcion in entradas:
        tarjeta = Gtk.Box(spacing=5, margin_top=3, margin_bottom=3)
        nombre = Gtk.Button(hexpand=True, css_classes=["flat"])
        resumen = Gtk.Box(spacing=5)
        resumen.append(icono_catalogo(icono))
        resumen.append(Gtk.Label(label=titulo, xalign=0, ellipsize=Pango.EllipsizeMode.END, max_width_chars=17))
        nombre.set_child(resumen)
        nombre.connect("clicked", lambda _, t=titulo, k=identificador, d=descripcion: previsualizar(t, k, d))
        tarjeta.append(nombre)

        for indice, texto in enumerate(("Escritorio", "Panel")):
            boton = Gtk.ToggleButton(label=texto, sensitive=False, css_classes=["byotfast-nav"])
            botones_destino[identificador, indice] = (boton, titulo, texto.lower())
            boton.connect("clicked", alternar, identificador, indice)
            tarjeta.append(boton)
        fila = Gtk.ListBoxRow(child=tarjeta, focusable=False, activatable=False, selectable=False)
        movimiento = Gtk.EventControllerMotion()
        movimiento.connect("enter", lambda _, _x, _y, t=titulo, k=identificador, d=descripcion: previsualizar(t, k, d))
        fila.add_controller(movimiento)
        foco = Gtk.EventControllerFocus()
        foco.connect("enter", lambda _, t=titulo, k=identificador, d=descripcion: previsualizar(t, k, d))
        fila.add_controller(foco)
        fila.terminos_byotfast = f"{titulo} {descripcion}".casefold()
        tarjetas.append(fila)

    termino = ""
    tarjetas.set_filter_func(lambda fila: termino in fila.terminos_byotfast)
    def buscar(control):
        nonlocal termino
        termino = control.get_text().strip().casefold()
        tarjetas.invalidate_filter()
        sin_resultados.set_visible(not any(termino in f"{titulo} {descripcion}".casefold()
                                            for titulo, _, _, descripcion in entradas))
    buscador.connect("search-changed", buscar)
    def actualizar_reloj():
        nonlocal reloj_vista
        ahora = datetime.now()
        for cifra in cifras:
            cifra.set_text(ahora.strftime("%H:%M"))
        demora = (60 - ahora.second) * 1000 - ahora.microsecond // 1000
        reloj_vista = GLib.timeout_add(demora, actualizar_reloj)
        return GLib.SOURCE_REMOVE

    monitor = None
    fuente_actualizacion = 0
    config_plasma = "plasma-org.kde.plasma.desktop-appletsrc"

    def refrescar_colocacion():
        nonlocal fuente_actualizacion
        fuente_actualizacion = 0
        if panel.get_mapped():
            actualizar()
        return GLib.SOURCE_REMOVE

    def cambio_plasma(_monitor, archivo, destino, _evento):
        nonlocal fuente_actualizacion
        if config_plasma not in {ruta.get_basename() for ruta in (archivo, destino) if ruta}:
            return
        if fuente_actualizacion:
            GLib.source_remove(fuente_actualizacion)
        fuente_actualizacion = GLib.timeout_add(200, refrescar_colocacion)

    def mostrar_catalogo(_):
        nonlocal reloj_vista, monitor
        actualizar()
        if cifras:
            actualizar_reloj()
        try:
            directorio = Gio.File.new_for_path(str(CONFIG.parent.parent))
            monitor = directorio.monitor_directory(Gio.FileMonitorFlags.WATCH_MOVES, None)
            monitor.connect("changed", cambio_plasma)
        except GLib.Error:
            monitor = None

    def ocultar_catalogo(_):
        nonlocal reloj_vista, monitor, fuente_actualizacion
        if reloj_vista:
            GLib.source_remove(reloj_vista)
            reloj_vista = 0
        if monitor:
            monitor.cancel()
            monitor = None
        if fuente_actualizacion:
            GLib.source_remove(fuente_actualizacion)
            fuente_actualizacion = 0

    panel.connect("map", mostrar_catalogo)
    panel.connect("unmap", ocultar_catalogo)
    primera = next(item for item in entradas if item[2].endswith(".musica"))
    previsualizar(primera[0], primera[2], primera[3])
    return panel, buscador


def encabezado_ajustes(panel, titulo, ayuda=None):
    encabezado = Gtk.Label(label=titulo, xalign=0, hexpand=True)
    encabezado.add_css_class("heading")
    cabecera = Gtk.Box(spacing=6)
    cabecera.append(encabezado)
    if ayuda:
        cabecera.append(boton_info(titulo, ayuda))
    panel.append(cabecera)


def controles_perfiles(panel, modelo, al_cambiar, visible):
    barra = Gtk.Box(spacing=8)
    barra.append(Gtk.Box(hexpand=True))
    agregar = Gtk.Button(label="Nuevo perfil", css_classes=["suggested-action"])
    barra.append(agregar)
    panel.append(barra)

    cuerpo = Gtk.Box(spacing=12)
    lista = Gtk.ListBox(selection_mode=Gtk.SelectionMode.SINGLE, valign=Gtk.Align.START, width_request=145,
                        css_classes=["boxed-list"])
    cuerpo.append(lista)
    detalle = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, hexpand=True,
                      css_classes=["byotfast-widget"])
    cuerpo.append(detalle)
    panel.append(cuerpo)

    cabecera = Gtk.Box(spacing=6)
    nombre = Gtk.Label(xalign=0, hexpand=True, wrap=True, css_classes=["heading"])
    cabecera.append(nombre)
    activar = Gtk.Button(label="Activar perfil", css_classes=["suggested-action"])
    cabecera.append(activar)
    detalle.append(cabecera)
    editor = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
    detalle.append(editor)
    detalle.append(boton_info("Sobre los perfiles",
                               "Puedes editar cualquier perfil. El atajo general usa el que marques como activo."))
    estado = Gtk.Label(xalign=0, wrap=True, visible=False)
    detalle.append(estado)
    filas = {}
    editado = modelo["activo"]
    cargado = None

    def mostrar_error(error):
        estado.set_text(str(error))
        estado.set_visible(True)

    def editar(clave):
        nonlocal cargado
        if not visible() or cargado == clave:
            return
        cargado = clave
        while hijo := editor.get_first_child():
            editor.remove(hijo)
        estado.set_visible(False)
        perfil = modelo["perfiles"][clave]
        encabezado_ajustes(editor, "Atajo del perfil", "Ejecuta este perfil aunque otro esté activo.")
        try:
            accion, orden = lanzador_perfil(clave, perfil["nombre"])
            controles_atajo(editor, accion, orden)
        except (OSError, GLib.Error) as error:
            mostrar_error(error)

        fila = Gtk.Box(spacing=8)
        fila.append(Gtk.Label(label="Alcance", xalign=0, hexpand=True))
        alcance = Gtk.DropDown.new_from_strings(["Todos los escritorios", "Escritorio actual"])
        alcance.set_selected(int(perfil["actual"]))
        alcance.update_property([Gtk.AccessibleProperty.LABEL], ["Alcance"])
        fila.append(alcance)
        editor.append(fila)
        activa = Gtk.CheckButton(label="Conservar la ventana activa", active=perfil["conservar_activa"])
        activa.add_css_class("byotfast-casilla")
        editor.append(activa)

        def cambiar(opcion, valor, revertir):
            valor_anterior = perfil[opcion]
            if valor == valor_anterior:
                return
            perfil[opcion] = valor
            try:
                guardar(modelo, perfiles.ARCHIVO)
            except OSError as error:
                perfil[opcion] = valor_anterior
                revertir(valor_anterior)
                mostrar_error(error)
            else:
                estado.set_visible(False)

        alcance.connect("notify::selected", lambda control, _: cambiar(
            "actual", bool(control.get_selected()), lambda valor: control.set_selected(int(valor)),
        ))
        activa.connect("toggled", lambda control: cambiar(
            "conservar_activa", control.get_active(), control.set_active,
        ))

    def refrescar():
        for clave, perfil in modelo["perfiles"].items():
            if clave not in filas:
                etiqueta = Gtk.Label(xalign=0, wrap=True, margin_start=8, margin_end=8, margin_top=7, margin_bottom=7)
                fila = Gtk.ListBoxRow(child=etiqueta)
                fila.clave_byotfast = clave
                filas[clave] = (fila, etiqueta)
                lista.append(fila)
            filas[clave][1].set_text(perfil["nombre"] + (" · Activo" if clave == modelo["activo"] else ""))
        lista.select_row(filas[editado][0])
        nombre.set_text(modelo["perfiles"][editado]["nombre"])
        activo = editado == modelo["activo"]
        activar.set_label("Perfil activo" if activo else "Activar perfil")
        activar.set_sensitive(not activo)
        editar(editado)

    def seleccionar_fila(_lista, fila):
        nonlocal editado
        if fila is not None and fila.clave_byotfast != editado:
            editado = fila.clave_byotfast
            refrescar()

    def activar_perfil(_):
        try:
            perfiles.seleccionar(editado)
        except (OSError, ValueError) as error:
            mostrar_error(error)
        else:
            modelo["activo"] = editado
            estado.set_visible(False)
            al_cambiar()

    def abrir_nuevo(_):
        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin_top=14, margin_bottom=14,
                      margin_start=14, margin_end=14)
        presentar, cerrar = dialogo_interno(panel.get_root(), "Nuevo perfil", 380, caja)
        entrada = Gtk.Entry(placeholder_text="Nombre del perfil", max_length=40)
        caja.append(entrada)
        aviso = Gtk.Label(xalign=0, wrap=True, visible=False)
        caja.append(aviso)
        acciones = Gtk.Box(spacing=8, halign=Gtk.Align.END)
        cancelar = Gtk.Button(label="Cancelar")
        crear = Gtk.Button(label="Crear", css_classes=["suggested-action"])
        acciones.append(cancelar)
        acciones.append(crear)
        caja.append(acciones)

        def responder(_):
            nonlocal editado
            nombre = entrada.get_text().strip()
            if not nombre or any(p["nombre"].casefold() == nombre.casefold() for p in modelo["perfiles"].values()):
                aviso.set_text("Escribe un nombre de perfil nuevo.")
                aviso.set_visible(True)
                return
            clave = uuid4().hex
            try:
                nuevo_modelo = {
                    "activo": modelo["activo"],
                    "perfiles": {**modelo["perfiles"], clave: perfiles.nuevo(nombre)},
                }
                guardar(nuevo_modelo, perfiles.ARCHIVO)
            except OSError as error:
                aviso.set_text(str(error))
                aviso.set_visible(True)
                return
            modelo.update(nuevo_modelo)
            editado = clave
            al_cambiar()
            cerrar()

        cancelar.connect("clicked", lambda _: cerrar())
        crear.connect("clicked", responder)
        entrada.connect("activate", responder)
        presentar()
        entrada.grab_focus()

    lista.connect("row-selected", seleccionar_fila)
    activar.connect("clicked", activar_perfil)
    agregar.connect("clicked", abrir_nuevo)
    return refrescar


def controles_limpieza(panel, *, incluir_atajo=True):
    orden = [sys.executable, str(Path(__file__).resolve()), "--limpiar"]
    if incluir_atajo:
        controles_atajo(panel, atajos.LIMPIEZA, orden)
    estado = Gtk.Label(xalign=0, wrap=True, visible=False)
    try:
        opciones = limpieza.leer_opciones(LIMPIEZA)
    except (OSError, ValueError) as error:
        estado.set_text(str(error))
        estado.set_visible(True)
        panel.append(estado)
        return

    def cambiar(clave, valor, revertir):
        if valor == opciones[clave]:
            return
        nuevas = {**opciones, clave: valor}
        try:
            guardar(nuevas, LIMPIEZA)
        except OSError as error:
            revertir(opciones[clave])
            estado.set_text(f"No se pudo guardar la selección. {error}")
            estado.set_visible(True)
            return
        perfiles.avisar_widgets("LimpiezaCambiada", widgets.modo_limpieza())
        opciones.update(nuevas)
        estado.set_visible(False)

    for nombre, clave, ayuda in (
        ("Archivos temporales", "temporales",
         f"Elimina archivos sueltos de tu usuario en /tmp y /var/tmp sin accesos ni cambios durante {limpieza.DIAS} días."),
        ("Vaciar la papelera de forma permanente", "papelera",
         "Los elementos eliminados de la papelera dejan de estar disponibles para restaurar."),
        ("Mostrar vista previa", "vista_previa",
         "Abre el detalle para elegir qué borrar. El widget muestra Revisar limpieza si la opción está activa y Limpiar si está desactivada."),
        ("Mostrar botón de limpieza en el widget", "boton_widget",
         "Desmarca esta opción para iniciar la limpieza solo con el atajo o el comando."),
    ):
        casilla = Gtk.CheckButton(label=nombre, active=opciones[clave])
        casilla.add_css_class("byotfast-casilla")
        casilla.connect("toggled", lambda control, opcion=clave: cambiar(
            opcion, control.get_active(), control.set_active,
        ))
        fila = Gtk.Box(spacing=6)
        casilla.set_hexpand(True)
        fila.append(casilla)
        fila.append(boton_info(nombre, ayuda))
        panel.append(fila)

    panel.append(estado)


def mostrar_detalle_limpieza(principal, titulo, elementos, marcados, actualizar, *, temporales=False):
    ventana = Gtk.Window(
        title=titulo, application=principal.get_application(),
        transient_for=principal, modal=True, destroy_with_parent=True,
    )
    ventana.set_default_size(760, 540)
    ventana.add_css_class("byotfast-window")
    ventana.set_titlebar(Gtk.HeaderBar())
    lista = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE, show_separators=True)
    lista.add_css_class("boxed-list")
    lista.set_margin_top(12)
    lista.set_margin_bottom(12)
    lista.set_margin_start(16)
    lista.set_margin_end(16)

    def elegir(casilla, elemento):
        if casilla.get_active():
            marcados.add(elemento)
        else:
            marcados.discard(elemento)
        actualizar()

    for elemento in elementos:
        motivo = elemento.motivo if temporales else None
        nombre = os.fsencode(elemento.ruta).decode("utf-8", errors="replace") if temporales else elemento.nombre
        fila = Gtk.Box(spacing=10)
        for borde in ("top", "bottom", "start", "end"):
            getattr(fila, f"set_margin_{borde}")(10)
        casilla = Gtk.CheckButton(active=elemento in marcados, sensitive=motivo is None, valign=Gtk.Align.START)
        casilla.update_property([Gtk.AccessibleProperty.LABEL], [nombre])
        if motivo:
            casilla.set_tooltip_text(motivo)
        else:
            casilla.connect("toggled", elegir, elemento)
        fila.append(casilla)
        detalle = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4, hexpand=True)
        detalle.append(Gtk.Label(
            label=nombre, xalign=0, wrap=True, wrap_mode=Pango.WrapMode.CHAR, selectable=True,
        ))
        datos = limpieza.mostrar_bytes(elemento.tamanio if temporales else elemento.bytes)
        if temporales:
            fecha = datetime.fromtimestamp(elemento.fecha).strftime("%d/%m/%Y %H:%M")
            datos += f" · Último acceso o cambio {fecha}"
        meta = Gtk.Label(label=datos, xalign=0, wrap=True)
        meta.add_css_class("dim-label")
        detalle.append(meta)
        if motivo:
            aviso = Gtk.Box(spacing=6)
            aviso.append(Gtk.Image(icon_name="dialog-warning-symbolic"))
            aviso.append(Gtk.Label(label=f"Se conserva · {motivo}", xalign=0, wrap=True))
            detalle.append(aviso)
        fila.append(detalle)
        lista.append(Gtk.ListBoxRow(child=fila, activatable=False))
    ventana.set_child(Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER, child=lista))
    ventana.present()


def confirmar_limpieza(opciones):
    if not Gtk.init_check():
        raise ValueError("Abre la vista previa desde una sesión gráfica de KDE.")

    seleccion = None
    cerrada = False
    app = Adw.Application(application_id=f"{ID_APP}.Limpieza", flags=Gio.ApplicationFlags.NON_UNIQUE)
    try:
        preferencias = leer_apariencia()
    except (OSError, ValueError):
        preferencias = {"tema": "Sistema", "acento": "Sistema"}

    def abrir_vista(aplicacion):
        ventana = Adw.ApplicationWindow(application=aplicacion, title="Vista previa de limpieza")
        ventana.add_css_class("byotfast-window")
        ventana.set_default_size(520, -1)
        estilos = Gtk.CssProvider()
        pantalla = ventana.get_display()
        Gtk.StyleContext.add_provider_for_display(pantalla, estilos, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        aplicar_apariencia(preferencias, estilos)
        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        ventana.set_content(caja)
        caja.append(Adw.HeaderBar())
        contenido = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        for borde in ("top", "bottom", "start", "end"):
            getattr(contenido, f"set_margin_{borde}")(16)
        caja.append(contenido)
        estado = Gtk.Label(label="Escaneando las ubicaciones seleccionadas…", xalign=0, wrap=True)
        contenido.append(estado)
        detalles = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        contenido.append(detalles)
        acciones = Gtk.Box(spacing=8, halign=Gtk.Align.END)
        cancelar = Gtk.Button(label="Cancelar")
        limpiar = Gtk.Button(label="Limpiar", sensitive=False)
        limpiar.add_css_class("destructive-action")
        acciones.append(cancelar)
        acciones.append(limpiar)
        contenido.append(acciones)

        def cerrar(_):
            nonlocal cerrada
            cerrada = True
            Gtk.StyleContext.remove_provider_for_display(pantalla, estilos)
            return False

        ventana.connect("close-request", cerrar)
        cancelar.connect("clicked", lambda _: ventana.close())

        def mostrar(temporales, entradas, notas, error):
            if cerrada:
                return GLib.SOURCE_REMOVE
            estado.set_visible(bool(error))
            estado.set_text(error)
            temporales_marcados = {archivo for archivo in temporales or () if archivo.motivo is None}
            papelera_marcada = set(entradas or ())
            total_temporales = Gtk.Label(xalign=0, wrap=True)
            total_papelera = Gtk.Label(xalign=0, wrap=True)
            if temporales is not None:
                peso = sum(archivo.tamanio for archivo in temporales)
                detalles.append(Gtk.Label(
                    label=f"Temporales de tu usuario · {len(temporales)} archivos · {limpieza.mostrar_bytes(peso)}",
                    xalign=0, wrap=True,
                ))
                detalles.append(total_temporales)
                if temporales:
                    ver = Gtk.Button(label="Ver y elegir archivos temporales", halign=Gtk.Align.START)
                    ver.connect("clicked", lambda _: mostrar_detalle_limpieza(
                        ventana, "Archivos temporales", temporales, temporales_marcados, actualizar, temporales=True,
                    ))
                    detalles.append(ver)
            if entradas is not None:
                peso = sum(elemento.bytes for elemento in entradas)
                fila_papelera = Gtk.Box(spacing=6)
                fila_papelera.append(Gtk.Label(
                    label=f"Papelera · {len(entradas)} elementos · {limpieza.mostrar_bytes(peso)}",
                    xalign=0, wrap=True, hexpand=True,
                ))
                fila_papelera.append(boton_info(
                    "Cómo se limpia la papelera",
                    "Los elementos de la papelera que queden marcados se borrarán permanentemente.",
                ))
                detalles.append(fila_papelera)
                detalles.append(total_papelera)
                if entradas:
                    ver = Gtk.Button(label="Ver y elegir elementos de la papelera", halign=Gtk.Align.START)
                    ver.connect("clicked", lambda _: mostrar_detalle_limpieza(
                        ventana, "Papelera", entradas, papelera_marcada, actualizar,
                    ))
                    detalles.append(ver)

            for nota in notas:
                aviso = Gtk.Label(label=nota, xalign=0, wrap=True)
                aviso.add_css_class("dim-label")
                detalles.append(aviso)

            def actualizar():
                peso_temporales = sum(archivo.tamanio for archivo in temporales_marcados)
                total_temporales.set_text(
                    f"Temporales seleccionados · {len(temporales_marcados)} · {limpieza.mostrar_bytes(peso_temporales)}"
                )
                peso_papelera = sum(elemento.bytes for elemento in papelera_marcada)
                total_papelera.set_text(
                    f"Papelera seleccionada · {len(papelera_marcada)} · {limpieza.mostrar_bytes(peso_papelera)}"
                )
                limpiar.set_sensitive(bool(temporales_marcados or papelera_marcada))

            def aceptar(_):
                nonlocal seleccion
                seleccion = (
                    [elemento for elemento in entradas or () if elemento in papelera_marcada],
                    [archivo for archivo in temporales or () if archivo in temporales_marcados],
                )
                ventana.close()

            limpiar.connect("clicked", aceptar)
            actualizar()
            return GLib.SOURCE_REMOVE

        def escanear():
            temporales = entradas = None
            notas = []
            error = ""
            try:
                if opciones["temporales"]:
                    temporales, parcial = limpieza.inventario_temporales()
                    if parcial:
                        notas.append("Algunos temporales no se pudieron medir.")
                if opciones["papelera"]:
                    entradas, parcial = limpieza.listar_papelera()
                    if parcial or any(elemento.incompleto for elemento in entradas):
                        notas.append("El tamaño de la papelera puede estar incompleto. Las entradas omitidas se conservarán.")
            except (OSError, ValueError) as fallo:
                error = str(fallo)
            GLib.idle_add(mostrar, temporales, entradas, notas, error)

        ventana.present()
        Thread(target=escanear, daemon=True).start()

    app.connect("activate", abrir_vista)
    app.run([])
    return seleccion


def ejecutar_limpieza(*, revisar=False, accion_widget=None):
    if os.getuid() == 0:
        mensajes, errores = [], ["Ejecuta la limpieza desde tu cuenta de usuario."]
    else:
        try:
            opciones = limpieza.leer_opciones(LIMPIEZA)
            if accion_widget is not None:
                if accion_widget not in ("revisar", "directo") or accion_widget != limpieza.accion_widget(opciones):
                    raise ValueError("La acción del widget cambió en Ajustes. Inténtalo de nuevo.")
                revisar = accion_widget == "revisar"
            directa = accion_widget == "directo"
            seleccion = None
            if revisar and not (opciones["temporales"] or opciones["papelera"]):
                opciones.update(temporales=True, papelera=True)
            if (revisar or (opciones["vista_previa"] and not directa)) and (opciones["temporales"] or opciones["papelera"]):
                seleccion = confirmar_limpieza(opciones)
                if seleccion is None:
                    return 0
            mensajes, errores = limpieza.ejecutar(opciones, *(seleccion or (None, None)))
        except (OSError, ValueError) as error:
            mensajes, errores = [], [str(error)]
    texto = "\n".join(mensajes + errores)
    print(texto, file=sys.stderr if errores else sys.stdout)
    if shutil.which("kdialog") and not sys.stdout.isatty():
        if errores:
            subprocess.run(["kdialog", "--title", TITULO, "--error", texto], check=False)
        else:
            subprocess.run(["kdialog", "--title", TITULO, "--passivepopup", texto, "5"], check=False)
    return int(bool(errores))


if __name__ == "__main__":
    if sys.argv[1:] == ["--instalar-acceso"]:
        sys.exit(instalar_acceso())
    elif sys.argv[1:] == ["--inicio"]:
        app = Adw.Application(application_id=f"{ID_APP}.Inicio", flags=Gio.ApplicationFlags.NON_UNIQUE)
        app.connect("activate", abrir_inicio)
        sys.exit(app.run([]))
    elif len(sys.argv) == 3 and sys.argv[1] == "--lanzar-app":
        try:
            ejecutar_lanzador(sys.argv[2])
        except (GLib.Error, ValueError, TypeError) as error:
            sys.exit(str(error))
    elif sys.argv[1:] == ["--limpiar"]:
        sys.exit(ejecutar_limpieza())
    elif sys.argv[1:] == ["--revisar-limpieza"]:
        sys.exit(ejecutar_limpieza(revisar=True))
    elif len(sys.argv) == 3 and sys.argv[1] == "--limpiar-widget":
        sys.exit(ejecutar_limpieza(accion_widget=sys.argv[2]))
    else:
        app = Adw.Application(application_id=ID_APP)
        app.connect("activate", abrir)
        sys.exit(app.run())
