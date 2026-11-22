import importlib.util
import sys
from pathlib import Path
from tempfile import TemporaryDirectory

carpeta = Path(__file__).resolve().parents[1] / "cerrar-ventanas"
sys.path.insert(0, str(carpeta))
spec = importlib.util.spec_from_file_location("byotfast_prueba", carpeta / "ajustes-cerrar-ventanas.py")
app_mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(app_mod)
Gtk, Gio, GLib = app_mod.Gtk, app_mod.Gio, app_mod.GLib
assert app_mod.Gdk.Display.get_default(), "Pantalla de prueba no disponible"

def nodos(w):
    yield w
    hijo = w.get_first_child()
    while hijo:
        yield from nodos(hijo)
        hijo = hijo.get_next_sibling()

def pulsar(w, titulo):
    control = next(x for x in nodos(w) if isinstance(x, Gtk.Button) and x.get_mapped()
                   and (x.get_label() == titulo or isinstance(x.get_child(), Gtk.Label)
                        and x.get_child().get_label() == titulo))
    control.emit("clicked")

with TemporaryDirectory() as tmp:
    carpeta = Path(tmp)
    app_mod.perfiles.CARPETA = carpeta
    app_mod.perfiles.ARCHIVO = carpeta / "perfiles.json"
    app_mod.perfiles.ACTIVO = carpeta / "perfil-activo.json"
    app_mod.guardar({"activo":"predeterminado", "perfiles":{
        "predeterminado": app_mod.perfiles.nuevo("Personal"),
        "a"*32: app_mod.perfiles.nuevo("Trabajo"),
    }}, app_mod.perfiles.ARCHIVO)
    app_mod.atajos.registrar = lambda _: None
    app_mod.atajos.activos = lambda _: []
    app_mod.aplicaciones_instaladas = lambda: {"dolphin.desktop":("Dolphin",["dolphin"],None)}
    app_mod.observar_ventanas = lambda _, pagina, recibir: recibir([("dolphin","dolphin","Dolphin")])
    destinos = []
    def consultar_widgets(claves, cambio=None):
        if cambio:
            destinos.append(cambio)
        return (set(), {destinos[-1][0]} if destinos else set())
    app_mod.consultar_widgets = consultar_widgets
    (carpeta / "ubicacion.json").write_text("{}")
    app = app_mod.Adw.Application(application_id="org.local.Byotfast.Prueba", flags=Gio.ApplicationFlags.NON_UNIQUE)
    app.register(None)
    app_mod.abrir(app)
    ventana = app.get_active_window()
    def drenar():
        while GLib.MainContext.default().iteration(False):
            pass
    drenar()
    stack = next(x for x in nodos(ventana) if isinstance(x,Gtk.Stack) and x.get_child_by_name("apps"))
    assert stack.get_visible_child_name() == "apps"
    assert stack.get_child_by_name("widgets") is None
    assert stack.get_child_by_name("lanzadores") is None
    app_control = next(x for x in nodos(ventana) if getattr(x,"clave_byotfast",None)=="dolphin.desktop")
    app_control.set_active(True)
    drenar()
    assert "dolphin.desktop" in app_mod.perfiles.leer()["perfiles"]["predeterminado"]["excepciones"]
    pulsar(ventana,"Perfiles")
    drenar()
    assert stack.get_visible_child_name() == "perfiles"
    fila = next(x for x in nodos(ventana) if isinstance(x,Gtk.ListBoxRow) and getattr(x,"clave_byotfast",None)=="a"*32)
    fila.get_parent().select_row(fila)
    assert app_mod.perfiles.leer()["activo"] == "predeterminado"
    pulsar(ventana,"Activar perfil")
    assert app_mod.perfiles.leer()["activo"] == "a"*32
    pulsar(ventana,"Widgets")
    drenar()
    assert stack.get_visible_child_name() == "widgets"
    pulsar(ventana, "Lanzadores")
    assert stack.get_visible_child_name() == "lanzadores"
    pulsar(ventana, "Widgets")
    pulsar(ventana,"Panel")
    assert destinos and destinos[0][1]
    pulsar(ventana,"⚙ Ajustes")
    drenar()
    assert stack.get_visible_child_name() == "ajustes"
    ventana.close()
    drenar()
    print("Navegación, excepciones, activación independiente, catálogo y ajustes comprobados.")
