pragma ComponentBehavior: Bound
import QtQuick
import QtCore
import org.kde.plasma.workspace.dbus as DBus
import org.kde.plasma.plasma5support as PlasmaSupport
import org.kde.plasma.private.mpris as Mpris
import org.kde.plasma.private.battery as Battery

QtObject {
    id: datos
    required property string tipo
    required property string instancia
    required property var preferencias
    property var estado: ({})
    signal resultadoControles(var resultado)
    property var ciudades: []
    property string error: ""
    property string solicitud: ""
    property string solicitudPortada: ""
    property string portadaSolicitada: ""
    property string solicitudControl: ""
    property string solicitudSiguiente: ""
    property string siguienteConsultada: ""
    property bool actualizarPendiente: false
    property real ultimaConsulta: 0
    property bool ubicacionConsultada: false
    property var ubicacionNotificada: null
    readonly property var musicaGuardada: leer("ultimaMusica", {})
    readonly property var musicaVisible: {
        if (!estado.destino)
            return musicaGuardada
        if (estado.portada && estado.portada === musicaGuardada.origenPortada)
            return Object.assign({}, estado, {portada: musicaGuardada.portada || estado.portada})
        if (estado.titulo || estado.portada || estado.reproductor !== musicaGuardada.reproductor)
            return estado
        return Object.assign({}, estado, musicaGuardada)
    }
    function posicionMusica(ahora) {
        const pista = musicaVisible
        if (!(pista.duracion > 0) || pista.posicion == null)
            return -1
        const avance = estado.sonando && pista.medidoEn
            ? Math.max(0, ahora - pista.medidoEn) * 1000 * (pista.velocidad || 1) : 0
        return Math.max(0, Math.min(pista.duracion, pista.posicion + avance))
    }

    readonly property string climaGuardado: preferencias["ciudadClima"] || ""
    readonly property string resumen: {
        switch (tipo) {
        case "bateria": return estado.equipo != null ? estado.equipo + "%"
            : estado.dispositivos?.length === 1 ? estado.dispositivos[0].carga + "%" : ""
        case "clima": return estado.temperatura != null ? estado.temperatura + "°C" : ""
        case "discos": return estado.unidades?.length ? estado.unidades[0].libre + " libres" : ""
        case "tareas": return pendientes ? String(pendientes) : ""
        default: return ""
        }
    }
    readonly property var tareas: leer("listaTareas", [])
    readonly property var historial: leer("historialCalculo", [])
    readonly property var ciudad: estado.ciudad || leer("ciudadClima", {})
    readonly property int pendientes: tareas.filter(tarea => !tarea.hecha).length
    property string operacion: ""
    property int secuencia: 0

    function leer(clave, defecto) {
        try {
            return JSON.parse(preferencias[clave] || "null") ?? defecto
        } catch (_) {
            return defecto
        }
    }

    function guardarTareas(nuevas) {
        preferencias["listaTareas"] = JSON.stringify(nuevas)
    }

    function nuevaTarea(texto) {
        const nombre = texto.trim()
        if (nombre)
            guardarTareas(tareas.concat([{texto: nombre, hecha: false}]))
    }

    function cambiarTarea(indice, accion) {
        const copia = tareas.slice()
        if (accion === "marcar") {
            copia[indice] = {texto: copia[indice].texto, hecha: !copia[indice].hecha}
        } else if (accion === "borrar") {
            copia.splice(indice, 1)
        } else {
            const destino = indice + (accion === "subir" ? -1 : 1)
            if (destino < 0 || destino >= copia.length)
                return
            copia.splice(destino, 0, copia.splice(indice, 1)[0])
        }
        guardarTareas(copia)
    }

    function calcular(expresion) {
        const entrada = expresion.replace(/,/g, ".").replace(/×/g, "*").replace(/÷/g, "/")
            .replace(/−/g, "-").replace(/\s/g, "")
        if (!entrada || entrada.length > 160)
            throw new Error("Escribe una operación.")
        const tokens = entrada.match(/(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?|[()+*/%\-]/gi) || []
        if (tokens.join("") !== entrada)
            throw new Error("Operación no válida.")
        let cursor = 0

        function factor() {
            const token = tokens[cursor++]
            if (token === "-" || token === "+")
                return token === "-" ? -factor() : factor()
            if (token === "(") {
                const valor = suma()
                if (tokens[cursor++] !== ")")
                    throw new Error("Falta un paréntesis.")
                return valor
            }
            if (!token || !/^[\d.]/.test(token))
                throw new Error("Falta un número.")
            return Number(token)
        }

        function producto() {
            let valor = factor()
            while (["*", "/", "%"].includes(tokens[cursor])) {
                const operador = tokens[cursor++]
                const derecho = factor()
                valor = operador === "*" ? valor * derecho : operador === "/" ? valor / derecho : valor % derecho
            }
            return valor
        }

        function suma() {
            let valor = producto()
            while (tokens[cursor] === "+" || tokens[cursor] === "-") {
                const operador = tokens[cursor++]
                const derecho = producto()
                valor = operador === "+" ? valor + derecho : valor - derecho
            }
            return valor
        }

        const resultado = suma()
        if (cursor !== tokens.length || !Number.isFinite(resultado))
            throw new Error("No se puede calcular esa operación.")
        return String(Number(resultado.toPrecision(12)))
    }

    function registrar(expresion, resultado) {
        preferencias["historialCalculo"] = JSON.stringify([{expresion: expresion, resultado: resultado}]
            .concat(historial).slice(0, 10))
    }

    function argumento(texto) {
        return "'" + String(texto).replace(/'/g, "'\"'\"'") + "'"
    }

    function orden(accion, parametros) {
        const carpeta = decodeURIComponent(StandardPaths.writableLocation(StandardPaths.GenericDataLocation)
            .toString().replace(/^file:\/\//, ""))
        return "BYOTFAST_DATOS=" + Date.now() + "-" + instancia + "-" + (++secuencia)
            + " /usr/bin/python3 " + argumento(carpeta + "/cerrar-ventanas/widgets.py")
            + " " + [accion].concat(parametros).map(argumento).join(" ")
    }

    function ejecutar(accion, parametros) {
        if (solicitud)
            return
        operacion = accion
        error = ""
        solicitud = orden(accion, parametros)
        motor.connectSource(solicitud)
    }

    function guardarPortada() {
        const url = estado.portada || ""
        if (!url || solicitudPortada || url === portadaSolicitada || url !== musicaGuardada.origenPortada
                || musicaGuardada.portada !== url)
            return
        portadaSolicitada = url
        solicitudPortada = orden("portada-musica", [url])
        motor.connectSource(solicitudPortada)
    }

    function controlarMusica(accion) {
        if (solicitudControl)
            return
        let parametros
        if (estado.destino) {
            parametros = [accion, estado.destino, estado.aplicacion || ""]
        } else if ((accion === "Reproducir" || accion === "Mostrar") && musicaGuardada.aplicacion) {
            parametros = ["Abrir", "", musicaGuardada.aplicacion]
        } else {
            return
        }
        error = ""
        solicitudControl = orden("musica", parametros)
        esperaControl.restart()
        motor.connectSource(solicitudControl)
    }

    function aplicarEstado(recibido) {
        if (tipo === "musica") {
            if (recibido.abriendo)
                return
            if (recibido.destino && (recibido.titulo || recibido.portada)) {
                const guardado = JSON.stringify({
                    aplicacion: recibido.aplicacion, reproductor: recibido.reproductor,
                    titulo: recibido.titulo, artista: recibido.artista, album: recibido.album,
                    origenPortada: recibido.portada,
                    portada: recibido.portada && recibido.portada === musicaGuardada.origenPortada
                        ? musicaGuardada.portada : recibido.portada,
                    duracion: recibido.duracion,
                    posicion: recibido.sonando && recibido.titulo === musicaGuardada.titulo
                        && recibido.reproductor === musicaGuardada.reproductor
                        ? musicaGuardada.posicion ?? recibido.posicion : recibido.posicion
                })
                if (guardado !== preferencias["ultimaMusica"])
                    preferencias["ultimaMusica"] = guardado
            } else if (!recibido.destino && estado.destino && musicaGuardada.reproductor === estado.reproductor) {
                const ultimaPosicion = posicionMusica(Date.now())
                if (ultimaPosicion >= 0)
                    preferencias["ultimaMusica"] = JSON.stringify(Object.assign({}, musicaGuardada, {posicion: ultimaPosicion}))
            }
        }
        if (tipo === "clima" && recibido.ciudad && recibido.temperatura == null
                && estado.temperatura != null && recibido.ciudad.latitud === estado.ciudad?.latitud
                && recibido.ciudad.longitud === estado.ciudad?.longitud)
            return
        if (JSON.stringify(recibido) !== JSON.stringify(estado))
            estado = recibido
        if (tipo === "musica") {
            guardarPortada()
            precargarSiguiente()
        }
    }

    function precargarSiguiente() {
        if (!estado.listaDisponible || !estado.pista || solicitudSiguiente)
            return
        const clave = estado.destino + "|" + estado.pista
        if (siguienteConsultada === clave)
            return
        siguienteConsultada = clave
        solicitudSiguiente = orden("portada-siguiente", [estado.destino, estado.pista])
        motor.connectSource(solicitudSiguiente)
    }

    function elegirCiudad(ciudad) {
        if (!solicitud)
            ejecutar("guardar-ubicacion", [JSON.stringify(ciudad)])
    }

    function aplicarUbicacion(nueva) {
        ubicacionNotificada = nueva
        if (estado.ciudad?.latitud === nueva.latitud && estado.ciudad?.longitud === nueva.longitud
                && estado.temperatura != null)
            return
        ubicacionConsultada = false
        estado = {ciudad: nueva}
        ciudades = []
        actualizar(true)
    }

    function actualizar(forzar) {
        if (solicitud || solicitudControl) {
            if (tipo === "musica" || tipo === "bateria" || (tipo === "clima" && forzar))
                actualizarPendiente = true
            return
        }
        actualizarPendiente = false
        if (tipo === "clima") {
            if (!forzar && (Date.now() - ultimaConsulta < (estado.temperatura != null ? 840000 : 60000)
                    || (ubicacionConsultada && !ciudad.nombre)))
                return
            ultimaConsulta = Date.now()
            ejecutar("clima-ubicacion", [climaGuardado])
        } else if (tipo === "bateria" || tipo === "discos" || tipo === "musica") {
            if (!forzar && tipo === "discos" && Date.now() - ultimaConsulta < 120000)
                return
            ultimaConsulta = Date.now()
            ejecutar(tipo, [])
        }
    }

    onClimaGuardadoChanged: {
        if (tipo !== "clima")
            return
        estado = ({})
        ciudades = []
        Qt.callLater(() => actualizar(true))
    }

    property PlasmaSupport.DataSource motor: PlasmaSupport.DataSource {
        engine: "executable"
        connectedSources: []
        onNewData: (fuente, respuesta) => {
            if (typeof respuesta.stdout !== "string")
                return
            if (fuente === datos.solicitudSiguiente && datos.solicitudSiguiente) {
                disconnectSource(fuente)
                datos.solicitudSiguiente = ""
                datos.precargarSiguiente()
                return
            }
            if (fuente === datos.solicitudPortada && datos.solicitudPortada) {
                disconnectSource(fuente)
                datos.solicitudPortada = ""
                try {
                    const copia = JSON.parse(respuesta.stdout).portada
                    if (copia && datos.portadaSolicitada === datos.musicaGuardada.origenPortada)
                        datos.preferencias["ultimaMusica"] = JSON.stringify(Object.assign({}, datos.musicaGuardada, {portada: copia}))
                } catch (_) {
                    // La portada original sigue disponible para la vista actual.
                }
                datos.guardarPortada()
                return
            }
            const esControl = fuente === datos.solicitudControl && !!datos.solicitudControl
            if (!esControl && fuente !== datos.solicitud)
                return
            disconnectSource(fuente)
            if (esControl) {
                esperaControl.stop()
                datos.solicitudControl = ""
            } else {
                datos.solicitud = ""
                if (datos.solicitudControl) {
                    datos.actualizarPendiente = true
                    return
                }
            }
            try {
                const recibido = JSON.parse(respuesta.stdout)
                datos.error = recibido.error || ""
                if (recibido.error)
                    return
                if (esControl && recibido.comandoAplicado) {
                    if (datos.solicitud) {
                        const consultaAnterior = datos.solicitud
                        datos.solicitud = ""
                        disconnectSource(consultaAnterior)
                    }
                    datos.actualizar(true)
                    return
                }
                if (datos.operacion === "controles") {
                    if (recibido.nivel)
                        datos.estado = Object.assign({}, datos.estado, {[recibido.nivel]: recibido.medida})
                    else if (!recibido.lista && !recibido.hecho)
                        datos.aplicarEstado(recibido)
                    datos.resultadoControles(recibido)
                } else if (!esControl && datos.operacion === "guardar-ubicacion") {
                    datos.estado = {ciudad: recibido}
                    datos.ciudades = []
                    datos.actualizar(true)
                } else if (!esControl && datos.operacion === "clima-ubicacion") {
                    if (datos.ubicacionNotificada && (recibido.ciudad?.latitud !== datos.ubicacionNotificada.latitud
                            || recibido.ciudad?.longitud !== datos.ubicacionNotificada.longitud))
                        return
                    datos.ubicacionConsultada = true
                    datos.aplicarEstado(recibido)
                } else if (!esControl && datos.operacion === "buscar-ciudad")
                    datos.ciudades = recibido.ciudades || []
                else
                    datos.aplicarEstado(recibido)
            } catch (_) {
                datos.error = "Datos no disponibles."
            } finally {
                if (datos.actualizarPendiente)
                    refrescarPorEvento.restart()
            }
        }
    }

    property Timer reloj: Timer {
        running: datos.tipo === "bateria" || datos.tipo === "discos"
            || datos.tipo === "clima" && (!datos.ubicacionConsultada || !!datos.ciudad.nombre)
        repeat: true
        triggeredOnStart: true
        interval: datos.tipo === "clima" ? (datos.estado.temperatura != null ? 900000 : 300000) : 120000
        onTriggered: datos.actualizar(false)
    }
    property Timer esperaControl: Timer {
        id: esperaControl
        interval: 5000
        onTriggered: {
            const fuente = datos.solicitudControl
            datos.solicitudControl = ""
            motor.disconnectSource(fuente)
            datos.error = "El reproductor no respondió. Vuelve a pulsar el control."
            if (datos.actualizarPendiente)
                refrescarPorEvento.restart()
        }
    }

    property Timer refrescarPorEvento: Timer {
        id: refrescarPorEvento
        interval: 65
        onTriggered: datos.actualizar(true)
    }

    property Loader eventosMusica: Loader {
        active: datos.tipo === "musica"
        onLoaded: refrescarPorEvento.restart()
        sourceComponent: Item {
            Mpris.Mpris2Model {
                id: reproductores
                onCurrentPlayerChanged: refrescarPorEvento.restart()
                onRowsInserted: refrescarPorEvento.restart()
                onRowsRemoved: refrescarPorEvento.restart()
            }

            DBus.SignalWatcher {
                path: "/org/mpris/MediaPlayer2"
                iface: "org.mpris.MediaPlayer2.Player"
                function onReceivedSignal(mensaje) {
                    if (mensaje.member === "Seeked")
                        refrescarPorEvento.restart()
                }
            }

            Connections {
                target: reproductores.currentPlayer
                function onMetadataChanged() { refrescarPorEvento.restart() }
                function onPlaybackStatusChanged() { refrescarPorEvento.restart() }
                function onRateChanged() { refrescarPorEvento.restart() }
                function onCanGoNextChanged() { refrescarPorEvento.restart() }
                function onCanGoPreviousChanged() { refrescarPorEvento.restart() }
                function onCanPlayChanged() { refrescarPorEvento.restart() }
                function onCanPauseChanged() { refrescarPorEvento.restart() }
                function onCanControlChanged() { refrescarPorEvento.restart() }
                function onHasTrackListChanged() { refrescarPorEvento.restart() }
            }
        }
    }

    property Loader eventosBateria: Loader {
        active: datos.tipo === "bateria"
        sourceComponent: Item {
            Battery.BatteryControlModel {
                onPercentChanged: refrescarPorEvento.restart()
                onPluggedInChanged: refrescarPorEvento.restart()
                onRowsInserted: refrescarPorEvento.restart()
                onRowsRemoved: refrescarPorEvento.restart()
                onDataChanged: refrescarPorEvento.restart()
            }
        }
    }
}
