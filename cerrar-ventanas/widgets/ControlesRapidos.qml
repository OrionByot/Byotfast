pragma ComponentBehavior: Bound
import QtQuick
import org.kde.plasma.workspace.dbus as DBus
import QtQuick.Controls as Controls
import QtQuick.Layouts
import QtQuick.Effects as Effects
import org.kde.kirigami as Kirigami
import org.kde.notificationmanager as NotificationManager

Item {
    id: tarjeta
    required property DatosWidgets modelo
    required property DatosWidgets musica
    required property color tinta
    required property color acento
    required property bool panel
    property bool editando: false
    property string vista: ""
    property var lista: []
    property var nivelesPendientes: ({})
    property var nivelesVisibles: ({})
    function ajustarNivel(clave, valor) {
        const numero = Math.round(valor)
        nivelesVisibles = Object.assign({}, nivelesVisibles, {[clave]:numero})
        nivelesPendientes[clave] = numero
        if (!enviarNiveles.running)
            enviarNiveles.start()
    }
    Timer {
        id: enviarNiveles
        interval: 65
        repeat: true
        onTriggered: {
            const claves = Object.keys(tarjeta.nivelesPendientes)
            if (!claves.length) { stop(); return }
            if (tarjeta.modelo.solicitud) return
            const clave = claves[0]
            const valor = tarjeta.nivelesPendientes[clave]
            delete tarjeta.nivelesPendientes[clave]
            tarjeta.operar(clave, String(valor))
        }
    }
    property var listasRecientes: ({})
    property string consultaPendiente: ""
    property string escaneoPendiente: ""
    readonly property var ajustesVista: ({redes:"red",dispositivos:"bt",silencio:"notificaciones",noche:"luz",energia:"energia",audio:"audio"})
    property string busqueda: ""
    property string confirmar: ""
    property var fijando: null
    property point puntoFijado: Qt.point(0,0)
    readonly property bool lite: !panel && (width < 230 || height < 140)
    readonly property var estado: modelo.estado
    readonly property var primarios: [
        { id: "wifi", nombre: "Wi-Fi", icono: Qt.resolvedUrl("controles-wifi.svg"), detalle: "redes", ajuste: "red" },
        { id: "bluetooth", nombre: "Bluetooth", icono: Qt.resolvedUrl("controles-bluetooth.svg"), detalle: "dispositivos", ajuste: "bt" },
        { id: "silencio", nombre: "No molestar", icono: Qt.resolvedUrl("controles-silencio.svg"), detalle: "silencio", ajuste: "notificaciones" },
        controlNocturno
    ]
    readonly property var controlNocturno: ({id:"noche", nombre:"Luz nocturna",
        icono:Qt.resolvedUrl("controles-noche.svg"), detalle:"noche", ajuste:"luz"})
    readonly property var controlMicrofono: ({id:"microfono", nombre:"Silenciar micrófono",
        icono:"microphone-sensitivity-muted", detalle:"audio", ajuste:"audio"})
    readonly property var modos: ["power-saver", "balanced", "performance"]
    readonly property var nombresModo: ["Ahorro", "Equilibrado", "Rendimiento"]
    readonly property int modo: modos.indexOf(estado.energia)
    readonly property bool silencio: ajustes.notificationsInhibitedUntil > new Date()
    readonly property var fijados: leerFijados()
    readonly property var orden: leerOrden()
    readonly property int columnas: lite ? 4 : panel || width >= 570 ? 8 : 4
    readonly property bool composicionHorizontal: panel && columnas === 8
    readonly property int filasBase: panel ? 6 : 1
    readonly property var ordenHorizontal: ["wifi","bluetooth","microfono","musica","brillo","volumen","silencio","energia"]
    readonly property var anchosHorizontales: ({wifi:2, bluetooth:2, microfono:2, musica:2, brillo:3, volumen:3,
        silencio:2, energia:2})
    readonly property var fichas: {
        const destacados = lite ? primarios : [...primarios.slice(0,3), controlMicrofono]
        const base = [...destacados, {id:"volumen",nombre:"Volumen"}, {id:"brillo",nombre:"Brillo"},
                      {id:"musica",nombre:"Música"}, {id:"energia",nombre:"Modo de energía"}]
        return base.concat(fijados).filter((ficha,index) => panel || (index < 4
            || (!lite && (index < 6 ? height >= 174 : index < 8 ? height >= 245 : height >= 314))))
    }
    readonly property var posicionesGuardadas: leerMapa("controlesPosiciones", {})
    property var posicionesEdicion: null
    property string tarjetaEditada: ""
    readonly property bool mostrarFranja: composicionHorizontal && !editando && !orden.length
        && !Object.keys(posicionesGuardadas).length && !Object.keys(anchos ?? {}).length
        && !Object.keys(altos ?? {}).length && fijados.length > 0
    readonly property var distribucion: calcularDistribucion(posicionesEdicion ?? posicionesGuardadas) ?? calcularDistribucion({}, {}, {})

    function calcularDistribucion(manuales, anchosActuales = anchos, altosActuales = altos) {
        const ocupadas = []
        const posiciones = {}
        const ids = (orden.length || !composicionHorizontal ? orden : ordenHorizontal)
            .filter(id => fichas.some(ficha => ficha.id === id))
        for (const ficha of fichas)
            if (!ids.includes(ficha.id)) ids.push(ficha.id)
        const preset = composicionHorizontal && !orden.length && !Object.keys(anchosActuales ?? {}).length
            && !Object.keys(altosActuales ?? {}).length && !Object.keys(manuales).length
        const medidas = {}
        for (const id of ids) {
            const accesoFijado = composicionHorizontal && fijados.some(ficha => ficha.id === id)
            const anchoBase = composicionHorizontal && anchosHorizontales[id]
                ? anchosHorizontales[id] : accesoFijado ? 1 : ["volumen","brillo","musica","energia"].includes(id) ? 4 : 2
            medidas[id] = {
                ancho: lite ? 1 : Math.max(1,Math.min(columnas,anchosActuales[id] || anchoBase)),
                alto: lite ? 1 : Math.max(1,Math.min(4,altosActuales[id] || (composicionHorizontal && id === "musica" ? 2 : 1)))
            }
        }
        function colocar(id, x, y) {
            const {ancho,alto} = medidas[id]
            if (x + ancho > columnas || (panel && y + alto > filasBase)) return false
            for (let fila = 0; fila < alto; fila++)
                for (let col = 0; col < ancho; col++)
                    if (ocupadas[(y + fila) * columnas + x + col]) return false
            posiciones[id] = {x,y,ancho,alto}
            for (let fila = 0; fila < alto; fila++)
                for (let col = 0; col < ancho; col++)
                    ocupadas[(y + fila) * columnas + x + col] = true
            return true
        }
        if (panel) {
            const prioridad = tarjetaEditada && ids.includes(tarjetaEditada)
                ? [tarjetaEditada, ...ids.filter(id => id !== tarjetaEditada)] : ids
            for (const id of prioridad) {
                const guardada = manuales[id]
                if (guardada && Number.isInteger(guardada.x) && Number.isInteger(guardada.y)) {
                    colocar(id, Math.max(0,Math.min(columnas - medidas[id].ancho,guardada.x)),
                        Math.max(0,Math.min(filasBase - medidas[id].alto,guardada.y)))
                }
            }
        }
        for (const id of ids) {
            if (posiciones[id]) continue
            const guardada = panel ? manuales[id] : null
            if (guardada) {
                const candidatos = []
                const limite = filasBase - medidas[id].alto
                for (let y = 0; y <= limite; y++)
                    for (let x = 0; x + medidas[id].ancho <= columnas; x++)
                        candidatos.push({x,y,distancia: Math.abs(x - guardada.x) + Math.abs(y - guardada.y)})
                candidatos.sort((a,b) => a.distancia - b.distancia)
                if (candidatos.some(p => colocar(id,p.x,p.y))) continue
            }
            const accesoFijado = preset && fijados.some(ficha => ficha.id === id)
            let i = accesoFijado ? 2 * columnas
                : preset && fijados.length && (id === "silencio" || id === "energia") ? 3 * columnas : 0
            while (!panel || i < columnas * filasBase) {
                if (colocar(id,i % columnas,Math.floor(i / columnas))) break
                i++
            }
            if (!posiciones[id]) return null
        }
        return posiciones
    }
    property var anchos: cargarAnchos()
    property var altos: leerMapa("controlesAltos", {})
    readonly property real pasoX: (cuadricula.width + 6) / columnas
    readonly property int filasOcupadas: Math.max(1, ...Object.values(distribucion ?? {}).map(celda => celda.y + celda.alto))
    readonly property int filas: panel ? (filasOcupadas > 4 ? filasBase : 4) : filasOcupadas
    readonly property real pasoY: lite ? 49 : panel ? (cuadricula.height + 6) / filas : 59
    readonly property real margenVertical: panel || lite ? Math.max(0, (cuadricula.height - filas * pasoY + 6) / 2) : 0

    NotificationManager.Settings { id: ajustes }
    function leerMapa(clave, valor) {
        try { return JSON.parse(modelo.preferencias[clave] || "null") ?? valor }
        catch (_) { return valor }
    }
    function cargarAnchos() {
        const guardados = leerMapa("controlesAnchosFinos", null)
        if (guardados)
            return guardados
        const resultado = {}
        const anteriores = leerMapa("controlesAnchos", {})
        for (const id of Object.keys(anteriores))
            resultado[id] = anteriores[id] * 2
        return resultado
    }
    function leerOrden() { return leerMapa("controlesOrden", []) }
    function integrado(id) {
        return ["c:wifi","c:bluetooth","c:silencio","c:noche","c:energia","c:microfono"].includes(id)
    }
    function leerFijados() {
        return leerMapa("controlesFijados", []).filter(ficha => !integrado(ficha.id))
    }
    function yaEsta(id) {
        return integrado(id) || fijados.some(ficha => ficha.id === id)
    }
    function operar(accion, valor = "") {
        modelo.ejecutar("controles", [accion, valor])
    }
    function abrirDetalle(modo) {
        vista = modo
        confirmar = ""
        lista = listasRecientes[modo] || []
        busqueda = ""
        escaneoPendiente = ["redes","dispositivos"].includes(modo) ? modo : ""
        consultaPendiente = ["redes","dispositivos","atajos","audio"].includes(modo) ? modo : ""
        if (consultaPendiente && !modelo.solicitud) {
            consultaPendiente = ""
            operar(modo)
        }
    }
    function activar(ficha) {
        if (ficha.id === "silencio") {
            ajustes.notificationsInhibitedUntil = silencio ? new Date(0) : new Date("2099-01-01T00:00:00")
            ajustes.save()
        } else if (ficha.id === "microfono" && estado.microfono != null) {
            operar("microfono")
        } else if (estado[ficha.id] != null) {
            operar(ficha.id, estado[ficha.id] ? "off" : "on")
        } else {
            operar("sistema", ficha.ajuste)
        }
    }
    function lanzar(ficha) {
        const id = ficha.id.slice(2)
        if (!ficha.id.startsWith("c:")) {
            operar(ficha.id.startsWith("d:") ? "accion-app" : ficha.id.startsWith("a:") ? "abrir" : "sistema", id)
            return
        }
        const interruptor = primarios.find(control => control.id === id)
        if (interruptor) activar(interruptor)
        else if (id === "energia") cicloEnergia()
        else if (id === "microfono") operar(id)
        else if (id === "audio") abrirDetalle(id)
    }
    function fijar(ficha, destino = "", punto = null) {
        if (yaEsta(ficha.id) || fijados.length >= 8) return
        if (destino) {
            const ids = (orden.length || !composicionHorizontal ? orden : ordenHorizontal)
                .filter(id => fichas.some(item => item.id === id))
            for (const item of fichas)
                if (!ids.includes(item.id)) ids.push(item.id)
            ids.splice(Math.max(0, ids.indexOf(destino)), 0, ficha.id)
            modelo.preferencias["controlesOrden"] = JSON.stringify(ids)
        }
        if (punto) {
            const x = Math.max(0,Math.min(columnas - 1,Math.floor(punto.x / pasoX)))
            const y = Math.max(0,Math.min(filas - 1,Math.floor((punto.y - margenVertical) / pasoY)))
            anchos = Object.assign({}, anchos, {[ficha.id]:1})
            modelo.preferencias["controlesAnchosFinos"] = JSON.stringify(anchos)
            modelo.preferencias["controlesPosiciones"] = JSON.stringify(
                Object.assign({}, posicionesGuardadas, distribucion, {[ficha.id]:{x,y}}))
        }
        modelo.preferencias["controlesFijados"] = JSON.stringify([...fijados, ficha])
    }
    function fichaEn(punto) {
        const col = Math.floor(punto.x / pasoX), fila = Math.floor((punto.y - margenVertical) / pasoY)
        for (const [id,c] of Object.entries(distribucion))
            if (col >= c.x && col < c.x+c.ancho && fila >= c.y && fila < c.y+c.alto)
                return id
        return ""
    }
    function restaurarDistribucion() {
        anchos = {}
        altos = {}
        modelo.preferencias["controlesAnchosFinos"] = "{}"
        modelo.preferencias["controlesAltos"] = "{}"
        modelo.preferencias["controlesOrden"] = "[]"
        modelo.preferencias["controlesPosiciones"] = "{}"
    }
    function iniciarColocacion(id) {
        posicionesEdicion = Object.assign({}, posicionesGuardadas, distribucion)
        tarjetaEditada = id
    }
    function colocarEnCelda(id, x, y) {
        const nueva = Object.assign({}, posicionesEdicion)
        nueva[id] = {x,y}
        if (calcularDistribucion(nueva))
            posicionesEdicion = nueva
    }
    function guardarColocacion() {
        modelo.preferencias["controlesPosiciones"] = JSON.stringify(
            Object.assign({}, posicionesGuardadas, distribucion))
        posicionesEdicion = null
        tarjetaEditada = ""
    }
    function cicloEnergia() {
        const disponibles = modos.filter(modo => (estado.perfiles || []).includes(modo))
        if (disponibles.length)
            operar("energia", disponibles[(disponibles.indexOf(estado.energia) + 1) % disponibles.length])
        else
            operar("sistema","energia")
    }

    Connections {
        target: tarjeta.modelo
        function onSolicitudChanged() {
            if (!tarjeta.modelo.solicitud && tarjeta.consultaPendiente) {
                Qt.callLater(() => {
                    const modo = tarjeta.consultaPendiente
                    if (modo && tarjeta.vista === modo && !tarjeta.modelo.solicitud) {
                        tarjeta.consultaPendiente = ""
                        tarjeta.operar(modo)
                    }
                })
            }
        }
        function onResultadoControles(resultado) {
            if (resultado.nivel) {
                const clave = resultado.nivel
                if (tarjeta.nivelesVisibles[clave] === resultado.solicitado
                        && tarjeta.nivelesPendientes[clave] === undefined) {
                    const visibles = Object.assign({}, tarjeta.nivelesVisibles)
                    delete visibles[clave]
                    tarjeta.nivelesVisibles = visibles
                }
            } else if (resultado.lista && resultado.vista) {
                tarjeta.listasRecientes = Object.assign({}, tarjeta.listasRecientes, {[resultado.vista]:resultado.lista})
                if (tarjeta.vista === resultado.vista) {
                    if (JSON.stringify(tarjeta.lista) !== JSON.stringify(resultado.lista))
                        tarjeta.lista = resultado.lista
                    if (tarjeta.escaneoPendiente === resultado.vista) {
                        tarjeta.escaneoPendiente = ""
                        if (!resultado.escaneada)
                            tarjeta.operar(resultado.vista, "actualizar")
                    }
                }
            } else if (["redes","dispositivos","audio"].includes(tarjeta.vista)) {
                tarjeta.operar(tarjeta.vista)
            }
        }
    }
    onVisibleChanged: if (visible) operar("estado")
    Component.onCompleted: if (visible) operar("estado")
    Timer {
        interval: 20000
        running: tarjeta.visible && !tarjeta.vista && !tarjeta.editando
        repeat: true
        onTriggered: tarjeta.operar("estado")
    }

    Timer {
        interval: 8000
        running: tarjeta.visible && tarjeta.vista === "dispositivos"
        repeat: true
        onTriggered: {
            if (!tarjeta.modelo.solicitud && !tarjeta.consultaPendiente && !tarjeta.escaneoPendiente)
                tarjeta.operar("dispositivos", "actualizar")
        }
    }

    Timer {
        id: refrescarBluetooth
        interval: 300
        onTriggered: {
            if (tarjeta.visible && tarjeta.vista === "dispositivos" && !tarjeta.modelo.solicitud)
                tarjeta.operar("dispositivos")
        }
    }
    DBus.SignalWatcher {
        enabled: tarjeta.visible && tarjeta.vista === "dispositivos"
        busType: DBus.BusType.System
        service: "org.bluez"
        iface: "org.freedesktop.DBus.Properties"
        function onReceivedSignal(mensaje) {
            if (mensaje.member !== "PropertiesChanged" || !mensaje.path.startsWith("/org/bluez/"))
                return
            const interfaz = mensaje.arguments[0]
            if (interfaz === "org.bluez.Battery1" || interfaz === "org.bluez.Adapter1"
                    || interfaz === "org.bluez.Device1" && !tarjeta.modelo.solicitud)
                refrescarBluetooth.restart()
        }
    }

    component Accion: Controls.Button {
        id: boton
        property color tono: tarjeta.tinta
        leftPadding: 12
        rightPadding: 12
        topPadding: 6
        bottomPadding: 6
        implicitHeight: Math.max(32, contentItem.implicitHeight + topPadding + bottomPadding)
        implicitWidth: Math.max(34, contentItem.implicitWidth + leftPadding + rightPadding)
        contentItem: Controls.Label {
            text: boton.text
            color: boton.tono
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 8
            color: Qt.alpha(boton.tono, boton.down || boton.hovered ? 0.18 : 0.07)
            border.color: Qt.alpha(boton.visualFocus ? tarjeta.acento : boton.tono, boton.visualFocus ? 0.9 : 0.16)
        }
    }

    Item {
        id: cuadricula
        anchors.fill: parent
        anchors.bottomMargin: tarjeta.panel ? (tarjeta.modelo.error ? 59 : 39) : 0
        visible: !tarjeta.vista || !!tarjeta.fijando
        clip: false

        Rectangle {
            visible: tarjeta.mostrarFranja
            x: 0
            y: tarjeta.margenVertical + 2 * tarjeta.pasoY
            width: parent.width
            height: tarjeta.pasoY - 6
            radius: height / 2
            color: Qt.alpha(tarjeta.acento, 0.09)
            border.color: Qt.alpha(tarjeta.tinta, 0.13)
        }

        Repeater {
            model: tarjeta.fichas
            delegate: Rectangle {
                id: ficha
                required property var modelData
                readonly property string clave: modelData.id
                readonly property var celda: tarjeta.distribucion?.[clave] || {x:0,y:0,ancho:1,alto:1}
                readonly property bool encendida: clave === "silencio" ? tarjeta.silencio : !!tarjeta.estado[clave]
                readonly property bool vertical: height > width && height > 83
                readonly property bool soloIcono: tarjeta.lite || ((!!modelData.icono || clave === "energia") && width < 95)
                x: celda.x * tarjeta.pasoX
                y: celda.y * tarjeta.pasoY + tarjeta.margenVertical
                width: gesto.active && gesto.lateral ? Math.max(42, Math.min(cuadricula.width - x, gesto.anchoInicial + gesto.activeTranslation.x))
                    : celda.ancho * tarjeta.pasoX - 6
                height: gesto.active && gesto.inferior ? Math.max(44, Math.min(cuadricula.height - y, gesto.altoInicial + gesto.activeTranslation.y))
                    : celda.alto * tarjeta.pasoY - 6
                Behavior on x { NumberAnimation { duration: 165; easing.type: Easing.OutCubic } }
                Behavior on y { NumberAnimation { duration: 165; easing.type: Easing.OutCubic } }
                Behavior on width { enabled: !gesto.active; NumberAnimation { duration: 165; easing.type: Easing.OutCubic } }
                Behavior on height { enabled: !gesto.active; NumberAnimation { duration: 165; easing.type: Easing.OutCubic } }
                scale: gesto.active ? 1.05 : 1
                z: gesto.active ? 2 : 0
                Behavior on scale { NumberAnimation { duration: 120 } }
                transform: Translate { x: gesto.active && !gesto.redimension ? gesto.desfase.x : 0; y: gesto.active && !gesto.redimension ? gesto.desfase.y : 0 }
                radius: clave === "musica" ? 18 : Math.min(height / 2, 20)
                color: encendida && !!modelData.ajuste ? Qt.alpha(tarjeta.acento, 0.19) : Qt.alpha(tarjeta.tinta, 0.055)
                gradient: clave === "musica" ? fondoMusical : null
                property Gradient fondoMusical: Gradient {
                    GradientStop { position: 0; color: Qt.alpha(tarjeta.acento, 0.29) }
                    GradientStop { position: 1; color: Qt.alpha(tarjeta.acento, 0.065) }
                }
                border.color: tarjeta.mostrarFranja && clave.includes(":") ? "transparent" : Qt.alpha(tarjeta.editando ? tarjeta.acento : tarjeta.tinta, 0.31)
                visible: tarjeta.panel || y + height <= cuadricula.height + 1
                clip: true
                HoverHandler {
                    enabled: tarjeta.editando
                    cursorShape: point.position.x >= ficha.width - 9 && point.position.y >= ficha.height - 9
                        ? Qt.SizeFDiagCursor : point.position.x >= ficha.width - 9 ? Qt.SizeHorCursor
                        : point.position.y >= ficha.height - 9 ? Qt.SizeVerCursor : Qt.OpenHandCursor
                }
                DragHandler {
                    id: gesto
                    enabled: tarjeta.editando
                    target: null
                    property int originalX: 1
                    property int originalY: 1
                    property real anchoInicial: 0
                    property real altoInicial: 0
                    property string ultimoDestino: ""
                    property point origen: Qt.point(0,0)
                    property point celdaOrigen: Qt.point(0,0)
                    property int filasIniciales: 4
                    property real pasoVertical: 0
                    property point desfase: Qt.point(0,0)
                    property bool lateral: false
                    property bool inferior: false
                    readonly property bool redimension: lateral || inferior
                    onActiveChanged: {
                        if (active) {
                            origen = Qt.point(ficha.x,ficha.y)
                            celdaOrigen = Qt.point(ficha.celda.x, ficha.celda.y)
                            filasIniciales = tarjeta.filas
                            pasoVertical = tarjeta.pasoY
                            tarjeta.iniciarColocacion(ficha.clave)
                            anchoInicial = ficha.width
                            altoInicial = ficha.height
                            ultimoDestino = ""
                            originalX = ficha.celda.ancho
                            originalY = ficha.celda.alto
                            lateral = centroid.pressPosition.x >= ficha.width - 9
                            inferior = centroid.pressPosition.y >= ficha.height - 9
                        } else {
                            desfase = Qt.point(0,0)
                            if (tarjeta.posicionesEdicion)
                                tarjeta.guardarColocacion()
                            tarjeta.modelo.preferencias["controlesAnchosFinos"] = JSON.stringify(tarjeta.anchos)
                            tarjeta.modelo.preferencias["controlesAltos"] = JSON.stringify(tarjeta.altos)
                        }
                    }
                    onActiveTranslationChanged: {
                        if (!active) return
                        if (redimension) {
                            const anchos = lateral ? Object.assign({}, tarjeta.anchos, {[ficha.clave]:
                                Math.max(1,Math.min(tarjeta.columnas - celdaOrigen.x,
                                    originalX + Math.round(activeTranslation.x / tarjeta.pasoX)))}) : tarjeta.anchos
                            const altos = inferior ? Object.assign({}, tarjeta.altos, {[ficha.clave]:
                                Math.max(1,Math.min(Math.min(4, filasIniciales - celdaOrigen.y),
                                    originalY + Math.round(activeTranslation.y / pasoVertical)))}) : tarjeta.altos
                            if (tarjeta.calcularDistribucion(tarjeta.posicionesEdicion ?? {}, anchos, altos)) {
                                tarjeta.anchos = anchos
                                tarjeta.altos = altos
                            }
                        } else {
                            const col = Math.max(0,Math.min(tarjeta.columnas - ficha.celda.ancho,
                                celdaOrigen.x + Math.round(activeTranslation.x / tarjeta.pasoX)))
                            const fila = Math.max(0,Math.min(filasIniciales - ficha.celda.alto,
                                celdaOrigen.y + Math.round(activeTranslation.y / pasoVertical)))
                            const destino = col + ":" + fila
                            if (destino !== ultimoDestino) {
                                ultimoDestino = destino
                                tarjeta.colocarEnCelda(ficha.clave,col,fila)
                            }
                            desfase = Qt.point(origen.x + activeTranslation.x - ficha.x, origen.y + activeTranslation.y - ficha.y)
                        }
                    }
                }

                Loader {
                    anchors.fill: parent
                    anchors.margins: tarjeta.lite ? 2 : ficha.clave === "volumen" || ficha.clave === "brillo" ? 4 : 6
                    enabled: !tarjeta.editando
                    sourceComponent: ficha.modelData.ajuste ? interruptor
                        : ficha.clave === "volumen" || ficha.clave === "brillo" ? nivel
                        : ficha.clave === "musica" ? reproductor : ficha.clave === "energia" ? energia : acceso
                }
                Component {
                    id: interruptor
                    Item {
                        id: control
                        readonly property bool apilado: ficha.vertical && !ficha.soloIcono
                        readonly property string conexion: !ficha.encendida ? ""
                            : ficha.clave === "wifi" ? tarjeta.estado.redWifi ?? ""
                            : ficha.clave === "bluetooth" ? tarjeta.estado.audifonosBluetooth ?? "" : ""
                        Controls.AbstractButton {
                            x: control.apilado ? 0 : 40
                            y: control.apilado ? alternar.y + alternar.height + 5 : 0
                            width: Math.max(0, parent.width - x)
                            height: Math.max(0, parent.height - y)
                            padding: 0
                            visible: !ficha.soloIcono
                            id: ajustesConexion
                            Accessible.name: ficha.modelData.nombre + " · Ajustes"
                                + (control.conexion ? " · " + control.conexion : "")
                            onClicked: tarjeta.abrirDetalle(ficha.modelData.detalle)
                            contentItem: Item {
                                Column {
                                    id: etiquetasConexion
                                    y: (parent.height - height - (control.apilado ? 5 + etiquetasConexion.implicitHeight : 0)) / 2
                                    width: parent.width
                                    Controls.Label {
                                        width: parent.width
                                        text: ficha.clave === "microfono" && ficha.encendida ? "Micrófono silenciado" : ficha.modelData.nombre
                                        color: tarjeta.tinta
                                        font.bold: true
                                        elide: Text.ElideRight
                                        horizontalAlignment: control.apilado ? Text.AlignHCenter : Text.AlignLeft
                                    }
                                    Controls.Label {
                                        width: parent.width
                                        visible: !!control.conexion && (control.apilado || ajustesConexion.height >= 30)
                                        text: control.conexion
                                        textFormat: Text.PlainText
                                        color: Qt.alpha(tarjeta.tinta, 0.8)
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                        horizontalAlignment: control.apilado ? Text.AlignHCenter : Text.AlignLeft
                                    }
                                }
                            }
                        }
                        Controls.AbstractButton {
                            id: alternar
                            width: 34
                            height: 34
                            x: ficha.soloIcono || control.apilado ? (parent.width - width) / 2 : 0
                            y: control.apilado ? 0 : (parent.height - height) / 2
                            padding: 0
                            Accessible.name: ficha.modelData.nombre
                            Accessible.checkable: true
                            Accessible.checked: ficha.encendida
                            onClicked: tarjeta.activar(ficha.modelData)
                            background: Item {
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 34
                                    height: 34
                                    radius: width / 2
                                    color: ficha.encendida ? tarjeta.acento : Qt.alpha(tarjeta.tinta, 0.12)
                                    border.width: alternar.visualFocus ? 1 : 0
                                    border.color: tarjeta.tinta
                                }
                            }
                            contentItem: Item {
                                Kirigami.Icon {
                                    anchors.centerIn: parent
                                    width: 20
                                    height: 20
                                    source: ficha.modelData.icono
                                    isMask: true
                                    color: ficha.encendida ? "#112431" : tarjeta.tinta
                                }
                            }
                        }
                    }
                }
                Component {
                    id: nivel
                    GridLayout {
                        columns: 2
                        rowSpacing: 2
                        columnSpacing: 5
                        RowLayout {
                            Layout.row: 0
                            Layout.column: 0
                            Layout.columnSpan: ficha.vertical ? 2 : 1
                            Layout.fillWidth: true
                            spacing: 3
                            Controls.AbstractButton {
                                id: nombreNivel
                                Layout.fillWidth: true
                                padding: 0
                                text: ficha.modelData.nombre
                                enabled: ficha.clave === "volumen"
                                Accessible.name: "Abrir ajustes de audio"
                                contentItem: Controls.Label {
                                    text: nombreNivel.text
                                    color: tarjeta.tinta
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                                onClicked: tarjeta.abrirDetalle("audio")
                            }
                            Controls.Label { text: tarjeta.estado[ficha.clave] == null ? "—" : Math.round(nivelRapido.value) + "%"; color: tarjeta.acento }
                        }
                        Controls.Slider {
                            id: nivelRapido
                            Layout.row: 1
                            Layout.column: 0
                            Layout.columnSpan: ficha.vertical ? 2 : 1
                            padding: 2
                            implicitHeight: 15
                            Layout.minimumHeight: 15
                            implicitWidth: 24
                            background: Rectangle {
                                x: ficha.vertical ? (nivelRapido.width - width) / 2 : nivelRapido.leftPadding
                                y: ficha.vertical ? nivelRapido.topPadding : (nivelRapido.height - height) / 2
                                width: ficha.vertical ? 5 : nivelRapido.availableWidth
                                height: ficha.vertical ? nivelRapido.availableHeight : 5
                                radius: 3
                                color: Qt.alpha(tarjeta.tinta,0.18)
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: ficha.vertical ? parent.width : parent.width * nivelRapido.position
                                    height: ficha.vertical ? parent.height * nivelRapido.position : parent.height
                                    radius: parent.radius
                                    color: tarjeta.acento
                                }
                            }
                            handle: Rectangle {
                                x: ficha.vertical ? (nivelRapido.width - width) / 2
                                    : nivelRapido.leftPadding + nivelRapido.visualPosition * (nivelRapido.availableWidth - width)
                                y: ficha.vertical ? nivelRapido.topPadding + nivelRapido.visualPosition * (nivelRapido.availableHeight - height)
                                    : (nivelRapido.height - height) / 2
                                width: 13; height: 13; radius: 7; color: tarjeta.acento
                            }
                            Layout.fillWidth: !ficha.vertical
                            Layout.fillHeight: ficha.vertical
                            Layout.alignment: Qt.AlignHCenter
                            orientation: ficha.vertical ? Qt.Vertical : Qt.Horizontal
                            from: 0; to: 100; stepSize: 1
                            enabled: tarjeta.estado[ficha.clave] != null
                            value: tarjeta.nivelesVisibles[ficha.clave] ?? tarjeta.estado[ficha.clave] ?? 0
                            Accessible.name: ficha.modelData.nombre
                            onMoved: tarjeta.ajustarNivel(ficha.clave, value)
                        }
                        Controls.AbstractButton {
                            id: accionNivel
                            readonly property bool audio: ficha.clave === "volumen"
                            readonly property bool activo: audio ? !!tarjeta.estado.salidaSilenciada : !!tarjeta.estado.noche
                            Layout.row: ficha.vertical ? 2 : 0
                            Layout.column: ficha.vertical ? 0 : 1
                            Layout.rowSpan: ficha.vertical ? 1 : 2
                            Layout.columnSpan: ficha.vertical ? 2 : 1
                            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                            Layout.preferredWidth: 34
                            Layout.preferredHeight: 34
                            padding: 0
                            Accessible.name: Controls.ToolTip.text
                            Accessible.checkable: true
                            Accessible.checked: activo
                            enabled: !audio || tarjeta.estado.salidaSilenciada != null
                            hoverEnabled: true
                            Controls.ToolTip.visible: hovered
                            Controls.ToolTip.text: audio ? (activo ? "Reactivar sonido" : "Silenciar salida de audio")
                                : activo ? "Desactivar Luz nocturna" : "Activar Luz nocturna"
                            onClicked: audio ? tarjeta.operar("silenciar-salida") : tarjeta.activar(tarjeta.controlNocturno)
                            background: Rectangle {
                                radius: 17
                                color: accionNivel.activo ? tarjeta.acento : Qt.alpha(tarjeta.tinta, 0.11)
                            }
                            contentItem: Item {
                                Kirigami.Icon {
                                    anchors.centerIn: parent
                                    width: 20
                                    height: 20
                                    source: accionNivel.audio
                                        ? Qt.resolvedUrl(accionNivel.activo ? "controles-mudo.svg" : "controles-volumen.svg")
                                        : tarjeta.controlNocturno.icono
                                    isMask: true
                                    color: accionNivel.activo ? "#112431" : tarjeta.tinta
                                }
                            }
                        }
                    }
                }
                Component {
                    id: reproductor
                    Item {
                        GridLayout {
                            id: disposicionMusical
                            anchors.centerIn: parent
                            width: Math.max(0, parent.width - (alto ? 12 : 0))
                            height: Math.min(parent.height, implicitHeight)
                            readonly property bool alto: ficha.height >= 105
                            readonly property bool apilado: alto && (width < 195 || ficha.height > ficha.width)
                            readonly property bool amplio: !alto && width >= 225
                            columnSpacing: alto ? 10 : 6
                            rowSpacing: alto ? 4 : 2
                            Item {
                                Layout.row: 0
                                Layout.column: 0
                                Layout.columnSpan: parent.apilado ? 2 : 1
                                Layout.rowSpan: parent.amplio || parent.apilado ? 1 : 2
                                Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                                Layout.preferredWidth: disposicionMusical.apilado
                                    ? Math.min(104, ficha.height * 0.45, disposicionMusical.width * 0.7)
                                    : disposicionMusical.alto ? Math.min(92, disposicionMusical.width * 0.35) : 32
                                Layout.preferredHeight: Layout.preferredWidth
                                visible: ficha.width >= 140 || parent.apilado
                                Rectangle {
                                    anchors.fill: parent
                                    radius: width / 2
                                    color: Qt.alpha(tarjeta.acento, 0.19)
                                    Kirigami.Icon {
                                        anchors.centerIn: parent
                                        width: 18
                                        height: 18
                                        source: "org.local.Byotfast.Musica"
                                        isMask: true
                                        color: tarjeta.acento
                                        visible: portada.status !== Image.Ready
                                    }
                                }
                                Image {
                                    id: portada
                                    anchors.fill: parent
                                    source: tarjeta.musica.musicaVisible.portada || ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    visible: status === Image.Ready
                                    layer.enabled: visible
                                    layer.effect: Effects.MultiEffect {
                                        maskEnabled: true
                                        maskSource: mascara
                                    }
                                }
                                Controls.AbstractButton {
                                    anchors.fill: parent
                                    enabled: !!(tarjeta.musica.estado.destino || tarjeta.musica.musicaGuardada.aplicacion)
                                    Accessible.name: "Abrir reproductor"
                                    hoverEnabled: true
                                    Controls.ToolTip.visible: hovered
                                    Controls.ToolTip.text: Accessible.name
                                    onClicked: tarjeta.musica.controlarMusica("Mostrar")
                                }
                                Rectangle {
                                    id: mascara
                                    anchors.fill: parent
                                    radius: width / 2
                                    visible: false
                                    layer.enabled: portada.visible
                                }
                            }
                            Controls.AbstractButton {
                                id: abrirPista
                                Layout.row: parent.apilado ? 1 : 0
                                Layout.column: parent.apilado ? 0 : 1
                                Layout.columnSpan: parent.apilado ? 2 : 1
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                padding: 0
                                enabled: !!(tarjeta.musica.estado.destino || tarjeta.musica.musicaGuardada.aplicacion)
                                text: tarjeta.musica.musicaVisible.titulo || "Música"
                                Accessible.name: "Abrir reproductor · " + text
                                hoverEnabled: true
                                Controls.ToolTip.visible: hovered
                                Controls.ToolTip.text: Accessible.name
                                contentItem: Controls.Label {
                                    text: abrirPista.text
                                    horizontalAlignment: disposicionMusical.alto ? Text.AlignHCenter : Text.AlignLeft
                                    verticalAlignment: Text.AlignVCenter
                                    font.bold: disposicionMusical.alto
                                    color: tarjeta.tinta
                                    elide: Text.ElideRight
                                    textFormat: Text.PlainText
                                }
                                onClicked: tarjeta.musica.controlarMusica("Mostrar")
                            }
                            RowLayout {
                                Layout.row: parent.apilado ? 2 : parent.amplio ? 0 : 1
                                Layout.column: parent.apilado ? 0 : parent.amplio ? 2 : 1
                                Layout.columnSpan: parent.apilado ? 2 : 1
                                Layout.alignment: disposicionMusical.alto ? Qt.AlignHCenter : Qt.AlignLeft
                                spacing: disposicionMusical.alto ? 5 : 3
                                Repeater {
                                    model: ["Anterior", "Reproducir", "Siguiente"]
                                    delegate: Accion {
                                        id: botonMediaRapido
                                        required property string modelData
                                        implicitWidth: disposicionMusical.alto ? 32 : 27
                                        implicitHeight: disposicionMusical.alto ? 27 : 22
                                        padding: 2
                                        Accessible.name: modelData === "Reproducir" && tarjeta.musica.estado.sonando ? "Pausar" : modelData
                                        contentItem: Item {
                                            IconoMedia {
                                                anchors.centerIn: parent
                                                width: disposicionMusical.alto ? 16 : 14
                                                height: width
                                                accion: botonMediaRapido.modelData
                                                sonando: !!tarjeta.musica.estado.sonando
                                                tinta: tarjeta.tinta
                                            }
                                        }
                                        onClicked: tarjeta.musica.controlarMusica(modelData)
                                    }
                                }
                            }
                            Rectangle {
                                id: progresoRapido
                                property real ahora: Date.now()
                                readonly property real duracion: tarjeta.musica.musicaVisible.duracion || 0
                                readonly property real posicion: tarjeta.musica.posicionMusica(ahora)
                                visible: duracion > 0
                                Layout.row: disposicionMusical.apilado ? 3 : disposicionMusical.amplio ? 1 : 2
                                Layout.column: disposicionMusical.apilado ? 0 : 1
                                Layout.columnSpan: disposicionMusical.apilado || disposicionMusical.amplio ? 2 : 1
                                Layout.fillWidth: true
                                Layout.preferredHeight: 3
                                Layout.maximumHeight: 3
                                Layout.topMargin: disposicionMusical.alto ? 5 : 0
                                radius: 1.5
                                color: Qt.alpha(tarjeta.tinta, 0.18)
                                Accessible.name: "Progreso de reproducción"
                                Rectangle {
                                    width: parent.width * Math.max(0, Math.min(1,
                                        progresoRapido.posicion / Math.max(1, progresoRapido.duracion)))
                                    height: parent.height
                                    radius: parent.radius
                                    color: tarjeta.acento
                                }
                                Timer {
                                    interval: 500
                                    running: progresoRapido.visible && !!tarjeta.musica.estado.sonando
                                    repeat: true
                                    triggeredOnStart: true
                                    onTriggered: progresoRapido.ahora = Date.now()
                                }
                            }
                        }
                    }
                }
                Component {
                    id: energia
                    GridLayout {
                        columns: ficha.vertical || ficha.soloIcono ? 1 : 2
                        Accion {
                            id: perfilEnergia
                            implicitWidth: 34
                            implicitHeight: 34
                            leftPadding: 0
                            rightPadding: 0
                            topPadding: 0
                            bottomPadding: 0
                            background: Rectangle {
                                radius: 17
                                color: Qt.alpha(perfilEnergia.tono, 0.15)
                            }
                            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                            tono: ["#72df99","#f2cd68","#fa8686"][tarjeta.modo] ?? tarjeta.tinta
                            contentItem: Item {
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 16; height: 21; radius: 3
                                    color: perfilEnergia.tono
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.top
                                        width: 7; height: 2; radius: 1
                                        color: perfilEnergia.tono
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        text: ["♧","=","ϟ"][tarjeta.modo] ?? "–"
                                        color: "#15242b"
                                        font.bold: true
                                    }
                                }
                            }
                            Accessible.name: "Cambiar modo de energía"
                            onClicked: tarjeta.cicloEnergia()
                        }
                        Controls.AbstractButton {
                            id: modoActual
                            visible: !ficha.soloIcono
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            text: tarjeta.nombresModo[tarjeta.modo] ?? "Energía"
                            Accessible.name: "Modo de energía · " + text
                            contentItem: Controls.Label {
                                text: modoActual.text
                                color: tarjeta.tinta
                                elide: Text.ElideRight
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: ficha.vertical ? Text.AlignHCenter : Text.AlignLeft
                            }
                            onClicked: tarjeta.abrirDetalle("energia")
                        }
                    }
                }
                Component {
                    id: acceso
                    Accion {
                        text: ficha.modelData.nombre
                        Accessible.name: text
                        leftPadding: 0
                        rightPadding: 0
                        topPadding: 0
                        bottomPadding: 0
                        background: Item {}
                        contentItem: Item {
                            RowLayout {
                                anchors.fill: parent
                                spacing: 6
                                Item {
                                    id: insigniaAcceso
                                    visible: !!ficha.modelData.icono
                                    Layout.preferredWidth: Math.max(0, Math.min(34, parent.width, parent.height))
                                    Layout.preferredHeight: Layout.preferredWidth
                                    Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 17
                                        color: Qt.alpha(tarjeta.tinta, 0.12)
                                    }
                                    Kirigami.Icon {
                                        anchors.centerIn: parent
                                        width: 20
                                        height: 20
                                        source: ficha.modelData.icono || ""
                                        isMask: true
                                        color: tarjeta.tinta
                                    }
                                }
                                Controls.Label {
                                    visible: !ficha.soloIcono
                                    Layout.fillWidth: true
                                    text: ficha.modelData.nombre
                                    color: tarjeta.tinta
                                    elide: Text.ElideRight
                                }
                            }
                        }
                        onClicked: tarjeta.lanzar(ficha.modelData)
                    }
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        visible: !!tarjeta.vista
        opacity: tarjeta.fijando ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 120 } }
        RowLayout {
            Layout.fillWidth: true
            Accion { text: "←"; Accessible.name: "Regresar"; onClicked: tarjeta.vista = "" }
            Controls.Label {
                Layout.fillWidth: true
                text: ({redes:"Redes Wi-Fi",dispositivos:"Bluetooth",silencio:"No molestar",noche:"Luz nocturna",energia:"Modo de energía",atajos:"Acciones rápidas",sesion:"Energía",audio:"Audio"})[tarjeta.vista] || ""
                font.bold: true
                color: tarjeta.tinta
            }
            Accion {
                visible: tarjeta.vista === "redes"
                text: "↻"
                Accessible.name: "Buscar redes de nuevo"
                enabled: !tarjeta.modelo.solicitud
                onClicked: tarjeta.operar("redes","actualizar")
            }
            Accion {
                visible: !!tarjeta.ajustesVista[tarjeta.vista]
                text: "⚙"
                Accessible.name: "Ajustes avanzados del sistema"
                onClicked: tarjeta.operar("sistema",tarjeta.ajustesVista[tarjeta.vista])
            }
        }
        Controls.TextField {
            visible: ["redes","atajos"].includes(tarjeta.vista)
            Layout.fillWidth: true
            placeholderText: "Buscar…"
            text: tarjeta.busqueda
            onTextEdited: tarjeta.busqueda = text
        }
        Accion {
            visible: tarjeta.vista === "sesion" && !!tarjeta.confirmar
            text: tarjeta.confirmar === "apagar" ? "Confirmar apagado" : "Confirmar reinicio"
            onClicked: {
                tarjeta.operar("sistema", tarjeta.confirmar)
                tarjeta.confirmar = ""
                tarjeta.vista = ""
            }
        }
        Item { visible: detalle.energiaCentrada; Layout.fillHeight: true }
        GridView {
            id: detalle
            readonly property bool energiaCentrada: tarjeta.vista === "sesion" || tarjeta.vista === "energia"
            readonly property int columnas: tarjeta.vista === "sesion"
                ? (width >= 420 ? 4 : 2) : tarjeta.vista === "energia"
                ? Math.max(1,Math.min(count,Math.floor(width / 126))) : Math.max(1, Math.floor(width / 175))
            cellWidth: Math.floor(width / columnas)
            cellHeight: energiaCentrada || tarjeta.vista === "redes" ? 82 : 66
            Layout.fillWidth: true
            Layout.fillHeight: !energiaCentrada
            Layout.preferredHeight: energiaCentrada ? Math.ceil(count / columnas) * cellHeight : 0
            Layout.alignment: Qt.AlignVCenter
            clip: true
            model: tarjeta.vista === "energia" ? tarjeta.modos.filter(m => (tarjeta.estado.perfiles || []).includes(m))
                .map(m => ({id:m,nombre:tarjeta.nombresModo[tarjeta.modos.indexOf(m)]}))
                : tarjeta.vista === "sesion" ? [{id:"bloquear",nombre:"Bloquear",icono:"system-lock-screen"},
                    {id:"suspender",nombre:"Suspender",icono:"system-suspend"},
                    {id:"reiniciar",nombre:"Reiniciar",icono:"system-reboot"},
                    {id:"apagar",nombre:"Apagar",icono:"system-shutdown"}]
                : tarjeta.lista.filter(f => (f.nombre + " " + (f.detalle || "")).toLocaleLowerCase().includes(tarjeta.busqueda.toLocaleLowerCase()))
            Controls.ScrollBar.vertical: Controls.ScrollBar {}
            delegate: RowLayout {
                id: fila
                required property var modelData
                width: Math.max(0, detalle.cellWidth - 9)
                height: detalle.cellHeight - 8
                spacing: 5
                Accion {
                    id: accionFila
                    readonly property bool conectado: ["redes","dispositivos","audio"].includes(tarjeta.vista) && !!fila.modelData.activo
                    implicitHeight: 36
                    background: Rectangle {
                        radius: 8
                        color: accionFila.conectado ? Qt.alpha(tarjeta.acento, 0.23)
                            : Qt.alpha(tarjeta.tinta, accionFila.hovered || accionFila.down ? 0.18 : 0.07)
                        border.color: accionFila.conectado || accionFila.visualFocus
                            ? tarjeta.acento : Qt.alpha(tarjeta.tinta, 0.16)
                    }
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    readonly property bool lateral: ["redes","dispositivos","audio"].includes(tarjeta.vista)
                    contentItem: GridLayout {
                        rowSpacing: 3
                        columnSpacing: 9
                        Item {
                            Layout.row: 0
                            Layout.column: 0
                            Layout.rowSpan: accionFila.lateral ? 2 : 1
                            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                            Layout.preferredWidth: accionFila.lateral ? 36 : 20
                            Layout.preferredHeight: Layout.preferredWidth
                            Rectangle {
                                anchors.fill: parent
                                visible: accionFila.lateral
                                radius: width / 2
                                color: Qt.alpha(accionFila.conectado ? tarjeta.acento : tarjeta.tinta, 0.14)
                            }
                            Kirigami.Icon {
                                anchors.centerIn: parent
                                width: accionFila.lateral ? 27 : 20
                                height: width
                                source: tarjeta.primarios.find(control => "c:" + control.id === fila.modelData.id)?.icono
                                    ?? (fila.modelData.icono || "configure")
                                color: accionFila.lateral && !accionFila.conectado ? tarjeta.tinta : tarjeta.acento
                                isMask: true
                            }
                        }
                        Controls.Label {
                            Layout.row: accionFila.lateral ? 0 : 1
                            Layout.column: accionFila.lateral ? 1 : 0
                            Layout.fillWidth: true
                            text: accionFila.text
                            textFormat: Text.PlainText
                            color: tarjeta.tinta
                            font.bold: accionFila.conectado
                            horizontalAlignment: accionFila.lateral ? Text.AlignLeft : Text.AlignHCenter
                            elide: Text.ElideRight
                        }
                        RowLayout {
                            visible: tarjeta.vista === "dispositivos" && fila.modelData.bateria != null
                            Layout.row: 1
                            Layout.column: 1
                            Layout.fillWidth: true
                            spacing: 4
                            Kirigami.Icon {
                                source: "battery"
                                isMask: true
                                color: tarjeta.acento
                                Layout.preferredWidth: 15
                                Layout.preferredHeight: 15
                            }
                            Controls.Label {
                                text: (fila.modelData.bateria ?? 0) + "%"
                                Accessible.name: "Batería " + text
                                color: tarjeta.tinta
                                font.pixelSize: 11
                            }
                        }
                        RowLayout {
                            visible: tarjeta.vista === "redes" && !!fila.modelData.detalle
                            Layout.row: 1
                            Layout.column: 1
                            Layout.fillWidth: true
                            spacing: 5
                            Rectangle {
                                id: etiquetaSenal
                                readonly property var nivel: fila.modelData.intensidad
                                readonly property string calidad: nivel >= 70 ? "Fuerte" : nivel >= 40 ? "Media" : "Débil"
                                readonly property color tono: nivel >= 70 ? "#176540" : nivel >= 40 ? "#805900" : "#983735"
                                visible: nivel != null
                                Layout.preferredWidth: textoSenal.implicitWidth + 10
                                Layout.preferredHeight: 18
                                radius: 5
                                color: tono
                                Controls.Label {
                                    id: textoSenal
                                    anchors.centerIn: parent
                                    text: etiquetaSenal.nivel + "% · " + etiquetaSenal.calidad
                                    color: "white"
                                    font.pixelSize: 10
                                    font.bold: true
                                }
                            }
                            Controls.Label {
                                Layout.fillWidth: true
                                text: fila.modelData.seguridad || ""
                                textFormat: Text.PlainText
                                color: Qt.alpha(tarjeta.tinta, 0.8)
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }
                    }
                    text: fila.modelData.nombre + (fila.modelData.activo ? " · Conectado" : "")
                    Controls.ToolTip.visible: hovered && !!fila.modelData.detalle
                    Controls.ToolTip.text: accionFila.text + (fila.modelData.detalle ? "\n" + fila.modelData.detalle : "")
                    onClicked: {
                        const id = fila.modelData.id
                        switch (tarjeta.vista) {
                        case "atajos": tarjeta.lanzar(fila.modelData); break
                        case "redes": if (!fila.modelData.activo) tarjeta.operar("conectar",id); break
                        case "dispositivos": tarjeta.operar(fila.modelData.activo ? "desconectar-bt" : "conectar-bt",id); break
                        case "energia": tarjeta.operar("energia",id); break
                        case "audio": tarjeta.operar("salida",id); break
                        case "sesion":
                            if (id === "reiniciar" || id === "apagar") tarjeta.confirmar = id
                            else { tarjeta.operar("sistema",id); tarjeta.vista = "" }
                            break
                        }
                    }
                }
                Accion {
                    visible: tarjeta.panel && tarjeta.vista === "atajos"
                    enabled: tarjeta.fijados.length < 8 && !tarjeta.yaEsta(fila.modelData.id)
                    text: tarjeta.yaEsta(fila.modelData.id) ? "✓" : "+"
                    Accessible.name: "Fijar " + fila.modelData.nombre
                    onClicked: tarjeta.fijar(fila.modelData)
                }
                DragHandler {
                    id: arrastrarAtajo
                    target: null
                    enabled: tarjeta.panel && tarjeta.vista === "atajos" && tarjeta.fijados.length < 8
                        && !tarjeta.yaEsta(fila.modelData.id)
                    grabPermissions: PointerHandler.CanTakeOverFromItems | PointerHandler.ApprovesTakeOverByAnything
                    onActiveChanged: {
                        if (active) {
                            tarjeta.fijando = fila.modelData
                            tarjeta.puntoFijado = tarjeta.mapFromItem(null, centroid.scenePosition.x, centroid.scenePosition.y)
                        } else if (tarjeta.fijando) {
                            const punto = tarjeta.puntoFijado
                            if (cuadricula.contains(punto)) {
                                tarjeta.fijar(tarjeta.fijando, tarjeta.fichaEn(punto), punto)
                                tarjeta.vista = ""
                            }
                            tarjeta.fijando = null
                        }
                    }
                    onActiveTranslationChanged: if (active)
                        tarjeta.puntoFijado = tarjeta.mapFromItem(null, centroid.scenePosition.x, centroid.scenePosition.y)
                    onCanceled: tarjeta.fijando = null
                }
            }
        }
        Item { visible: detalle.energiaCentrada; Layout.fillHeight: true }

    }
    Accion {
        visible: !!tarjeta.fijando
        z: 4
        width: 140
        height: 42
        x: tarjeta.puntoFijado.x - width / 2
        y: tarjeta.puntoFijado.y - height / 2
        scale: visible ? 1.05 : 1
        Behavior on scale { NumberAnimation { duration: 120 } }
        text: tarjeta.fijando?.nombre || ""
        background: Rectangle { radius: 8; color: Kirigami.Theme.backgroundColor; border.color: tarjeta.acento }
    }
    RowLayout {
        id: accionesPie
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 8
        visible: tarjeta.panel && !tarjeta.vista
        Accion {
            visible: tarjeta.editando
            text: "Aplicar diseño horizontal"
            onClicked: tarjeta.restaurarDistribucion()
        }
        Accion { visible: !tarjeta.editando; text: "Acciones"; onClicked: tarjeta.abrirDetalle("atajos") }
        Accion { visible: !tarjeta.editando; text: "Captura"; onClicked: tarjeta.operar("sistema","captura") }
        Accion { visible: !tarjeta.editando; text: "Energía"; onClicked: tarjeta.abrirDetalle("sesion") }
        Accion {
            visible: !tarjeta.editando
            text: "Preferencias del sistema"
            Accessible.name: text
            implicitWidth: 36
            hoverEnabled: true
            Controls.ToolTip.visible: hovered
            Controls.ToolTip.text: text
            contentItem: Item {
                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: 17
                    height: 17
                    source: "settings-configure"
                    color: tarjeta.tinta
                    isMask: true
                }
            }
            onClicked: tarjeta.operar("sistema", "ajustes")
        }
    }
    Controls.Label {
        anchors.bottom: accionesPie.visible ? accionesPie.top : parent.bottom
        anchors.bottomMargin: 4
        anchors.left: parent.left
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        visible: !!text
        text: tarjeta.modelo.error || tarjeta.musica.error
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: tarjeta.tinta
    }
}
