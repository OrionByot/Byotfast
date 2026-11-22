pragma ComponentBehavior: Bound
import QtQuick
import org.kde.plasma.workspace.dbus as DBus
import QtQuick.Window
import QtQuick.Controls as Controls
import QtQuick.Layouts
import QtCore
import org.kde.kirigami as Kirigami
import org.kde.notificationmanager as NotificationManager
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as PlasmaSupport
import org.kde.plasma.private.containmentlayoutmanager as DesktopLayout

PlasmoidItem {
    id: raiz
    property int filasControlesPanel: 4
    property real altoSugerenciasBusqueda: 0
    readonly property bool controlesRapidos: tipo === "controles"
    readonly property bool esFoto: tipo === "fotos"
    readonly property bool esBusqueda: tipo === "busquedagoogle"
    readonly property bool relojModerno: tipo === "relojmoderno"
    readonly property bool reloj: Plasmoid.metaData.pluginId === "org.local.Byotfast.reloj"
    readonly property bool calendario: Plasmoid.metaData.pluginId === "org.local.Byotfast.calendario"
    readonly property var modeloAvisos: (avisos.item as ModeloAvisos)?.modelo ?? null
    readonly property bool avisosDisponibles: (modeloAvisos?.count ?? 0) > 0
    readonly property bool rendimiento: Plasmoid.metaData.pluginId === "org.local.Byotfast.rendimiento"
    readonly property bool temporizador: Plasmoid.metaData.pluginId === "org.local.Byotfast.temporizador"
    readonly property bool esNotas: Plasmoid.metaData.pluginId === "org.local.Byotfast.notas"
    readonly property string tipo: Plasmoid.metaData.pluginId.split(".").pop()
    readonly property var iconosExtra: ({
        tareas: "org.local.Byotfast.Tareas", bateria: "org.local.Byotfast.Bateria", clima: "org.local.Byotfast.Clima",
        controles: "org.local.Byotfast.Controles", musica: "org.local.Byotfast.Musica", discos: "org.local.Byotfast.Discos", calculadora: "org.local.Byotfast.Calculadora"
    })
    readonly property bool tieneSegundaVista: tipo === "clima" || tipo === "calculadora" || (calendario && !enPanel)
    readonly property bool utilidadExtra: !!iconosExtra[tipo]
    readonly property string iconoPanel: tipo === "musica" && datosExtra.estado.sonando
        ? "org.local.Byotfast.Musicapausa" : icono
    Loader {
        id: avisos
        active: raiz.calendario
        sourceComponent: ModeloAvisos {}
    }

    component ModeloAvisos: Item {
        property alias modelo: historialPlasma
        NotificationManager.Notifications {
            id: historialPlasma
            showExpired: true
            showDismissed: true
            showJobs: false
            groupMode: NotificationManager.Notifications.GroupDisabled
            sortMode: NotificationManager.Notifications.SortByDate
            sortOrder: Qt.DescendingOrder
        }
    }
    DatosWidgets {
        id: datosExtra
        onSolicitudChanged: if (raiz.calendario && !solicitud && raiz.anioConsultado !== raiz.anioFeriados)
            Qt.callLater(raiz.consultarFeriados)
        instancia: String(Plasmoid.id)
        tipo: raiz.utilidadExtra ? raiz.tipo : ""
        preferencias: raiz.preferencias
    }
    Loader {
        id: musicaRapida
        active: raiz.controlesRapidos
        sourceComponent: DatosWidgets {
            instancia: String(Plasmoid.id) + "-controles"
            tipo: (raiz.enPanel ? raiz.expanded : !raiz.mini) ? "musica" : ""
            preferencias: raiz.preferencias
        }
    }
    property var muestraAnterior: null
    property int cpu: -1
    property string aviso: ""
    property bool modoCronometro: false
    readonly property Temporizador controlTiempo: modoCronometro ? cronometro : cuenta
    Temporizador {
        id: cronometro
        ascendente: true
    }
    Temporizador {
        id: cuenta
        onCompleto: {
            raiz.aviso = "Tiempo cumplido"
            notificaciones.connectSource("notify-send --app-name=Byotfast 'Temporizador' 'Tiempo cumplido'")
        }
    }
    PlasmaSupport.DataSource {
        id: notificaciones
        engine: "executable"
        connectedSources: []
        onNewData: (fuente, datos) => {
            if (typeof datos.stdout === "string")
                disconnectSource(fuente)
        }
    }
    Timer {
        running: cuenta.activo
        repeat: true
        interval: 200
        onTriggered: cuenta.actualizar()
    }
    property bool accionesMiniVisibles: false
    Timer {
        running: cronometro.activo
        repeat: true
        interval: raiz.modoCronometro && (!raiz.enPanel && (!raiz.mini || raiz.accionesMiniVisibles) || raiz.expanded) ? 16 : 1000
        onTriggered: cronometro.actualizar()
    }
    readonly property bool enPanel: Plasmoid.formFactor === PlasmaCore.Types.Horizontal
        || Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property bool mini: !enPanel && !!preferencias["compacto"]
    readonly property int anchoMini: 164
    readonly property int altoMini: 38
    readonly property var preferencias: Plasmoid.configuration
    readonly property var notas: {
        try {
            const guardadas = JSON.parse(preferencias["notas"] || "null")
            if (Array.isArray(guardadas) && guardadas.length
                    && guardadas.every(nota => typeof nota === "string" || (nota
                        && typeof nota.titulo === "string" && typeof nota.cuerpo === "string")))
                return guardadas.map(nota => typeof nota === "string" ? {titulo: "", cuerpo: nota} : nota)
        } catch (error) {
            // Las notas de las versiones anteriores se guardaban por separado.
        }
        return [{titulo: "", cuerpo: preferencias["nota"] || ""}]
    }
    readonly property int notaActiva: Math.max(0, Math.min(notas.length - 1, preferencias["notaActiva"] || 0))

    function inicialMayuscula(texto) {
        return texto.charAt(0).toLocaleUpperCase() + texto.slice(1)
    }

    function guardarNota(nota) {
        const copia = notas.slice()
        copia[notaActiva] = nota
        preferencias["notas"] = JSON.stringify(copia)
    }

    property var apariencia: ({})
    property bool temaRecibido: false
    property date ahora: new Date()
    property date mes: new Date(ahora.getFullYear(), ahora.getMonth(), 1)
    readonly property int anioFeriados: mes.getFullYear()
    property int anioConsultado: 0
    property real ultimaConsultaFeriados: 0
    property string paisFeriados: ""
    onAnioFeriadosChanged: if (calendario && (!enPanel || expanded)) Qt.callLater(consultarFeriados)
    function consultarFeriados() {
        if (calendario && (!enPanel || expanded) && !datosExtra.solicitud
                && (anioConsultado !== anioFeriados || Date.now() - ultimaConsultaFeriados >= 3600000)) {
            anioConsultado = anioFeriados
            ultimaConsultaFeriados = Date.now()
            datosExtra.ejecutar("feriados", [anioFeriados])
        }
    }
    function feriado(fecha) {
        if (!datosExtra.estado.fechas || datosExtra.estado.anio !== fecha.getFullYear()
                || (paisFeriados && datosExtra.estado.pais !== paisFeriados))
            return ""
        const clave = Qt.formatDate(fecha, "yyyy-MM-dd")
        return (datosExtra.estado.fechas[clave] || []).join(" · ")
    }
    Timer {
        running: raiz.calendario && (!raiz.enPanel || raiz.expanded)
        interval: 3600000
        repeat: true
        triggeredOnStart: true
        onTriggered: raiz.consultarFeriados()
    }
    property string consulta: ""
    readonly property bool vidrio: apariencia.tema === "Liquid Glass"
    readonly property color acento: apariencia.acento || Kirigami.Theme.highlightColor
    readonly property bool oscuro: apariencia.tema === "Oscuro" || (apariencia.tema !== "Claro"
        && Kirigami.Theme.backgroundColor.r + Kirigami.Theme.backgroundColor.g + Kirigami.Theme.backgroundColor.b < 1.5)
    readonly property color texto: enPanel ? Kirigami.Theme.textColor : oscuro ? "#f2f5fa" : "#192537"
    readonly property color borde: vidrio ? (oscuro ? "#85c8c8c8" : "#eaffffff") : (oscuro ? "#65778c" : "#b8c7db")
    readonly property string icono: esFoto ? "org.local.Byotfast.Fotos" : esBusqueda ? "org.local.Byotfast.Busquedagoogle"
        : utilidadExtra ? iconosExtra[tipo] : reloj || relojModerno ? "org.local.Byotfast.Reloj" : calendario ? "org.local.Byotfast.Calendario" : rendimiento ? "org.local.Byotfast.Rendimiento" : temporizador ? "org.local.Byotfast.Temporizador" : "org.local.Byotfast.Notas"
    readonly property string detallesRendimiento: "CPU total: "
        + (cpu < 0 ? "…" : cpu + "%") + "\nRAM en uso: "
        + (apariencia.usoRam || "…") + " de " + (apariencia.totalRam || "…")
    readonly property int ancho: esFoto ? 288 : esBusqueda ? 320 : relojModerno ? 440 : controlesRapidos ? 352 : rendimiento ? medidaCompacta : utilidadExtra ? 270 : 248
    readonly property real escalaControlesPanel: enPanel && controlesRapidos ? 1.25 : 1
    readonly property size tamanoPanel: ({
        controles: Qt.size(Math.round(660 * escalaControlesPanel),
            Math.round((filasControlesPanel > 4 ? 405 : 301) * escalaControlesPanel)), reloj: Qt.size(180,130), relojmoderno: Qt.size(320,166), fotos: Qt.size(280,230), busquedagoogle: Qt.size(306,100 + altoSugerenciasBusqueda), calendario: Qt.size(avisosDisponibles ? 820 : 440, 420), notas: Qt.size(252,165),
        rendimiento: Qt.size(214,145), temporizador: Qt.size(244,182), tareas: Qt.size(252,162),
        bateria: Qt.size(222,148), clima: Qt.size(244,170), musica: Qt.size(280,196),
        discos: Qt.size(240,150), calculadora: Qt.size(232,212)
    })[tipo] ?? Qt.size(244,182)
    readonly property int medidaCompacta: 172
    readonly property int anchoMinimo: controlesRapidos ? 220 : rendimiento || utilidadExtra ? medidaCompacta : 210
    readonly property int alto: esFoto ? 224 : esBusqueda ? 98 : relojModerno ? 168 : controlesRapidos ? 285 : utilidadExtra ? (tipo === "calculadora" ? 266 : tipo === "clima" ? 216 : tipo === "musica" ? 164 : 204) : reloj ? 132 : calendario ? 246 : rendimiento ? medidaCompacta : temporizador ? 170 : 200
    readonly property int altoMinimo: esFoto ? 128 : esBusqueda ? 90 : relojModerno ? 112 : controlesRapidos ? 106 : tipo === "musica" ? 144 : utilidadExtra ? medidaCompacta : alto
    readonly property DesktopLayout.ItemContainer soporte: {
        let item = parent
        while (item) {
            const contenedor = item as DesktopLayout.ItemContainer
            if (contenedor)
                return contenedor
            item = item.parent
        }
        return null
    }
    readonly property Item fondo: (soporte?.layout?.containmentItem as ContainmentItem)?.wallpaper ?? null
    readonly property bool esmerilado: vidrio && !!fondo && GraphicsInfo.api !== GraphicsInfo.Software
    readonly property color superficieSuperior: esmerilado
        ? (oscuro ? "#b3343434" : "#c4ffffff") : vidrio ? (oscuro ? "#343434" : "#ffffff") : (oscuro ? "#252c36" : "#f9fbff")
    readonly property color superficieInferior: esmerilado
        ? (oscuro ? "#cf1b1b1b" : "#cfe5e5e5") : vidrio ? (oscuro ? "#1b1b1b" : "#e5e5e5") : (oscuro ? "#1c222b" : "#edf2fa")

    toolTipMainText: calendario && enPanel ? formatearFechaPanel(ahora, 2) : Plasmoid.title
    toolTipSubText: calendario && enPanel
        ? zonaUtc(ahora) + " · " + Qt.formatTime(ahora, preferencias["formatoHoraPanel"] === 1 ? "h:mm:ss AP" : "HH:mm:ss")
        : Plasmoid.metaData.description

    switchWidth: -1
    switchHeight: -1
    preferredRepresentation: enPanel ? compactRepresentation : fullRepresentation
    Layout.minimumWidth: enPanel ? 0 : mini ? anchoMini : anchoMinimo
    Layout.preferredWidth: enPanel ? -1 : mini ? anchoMini : ancho
    Layout.minimumHeight: enPanel ? 0 : mini ? altoMini : altoMinimo
    Layout.preferredHeight: enPanel ? -1 : mini ? altoMini : alto
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    function archivoAuxiliar(nombre) {
        const directorio = decodeURIComponent(StandardPaths.writableLocation(
            StandardPaths.GenericDataLocation).toString().replace(/^file:\/\//, ""))
        return "'" + (directorio + "/cerrar-ventanas/" + nombre).replace(/'/g, "'\"'\"'") + "'"
    }

    function consultar(operacion) {
        if (consulta)
            return
        consulta = "BYOTFAST_WIDGET_REQUEST=" + Date.now() + "-" + Plasmoid.id
            + " /usr/bin/python3 " + archivoAuxiliar("widgets.py") + " " + operacion
        datos.connectSource(consulta)
    }

    DBus.SignalWatcher {
        service: "org.local.Byotfast.WidgetEvents"
        path: "/org/local/Byotfast/Widgets"
        iface: "org.local.Byotfast.Widgets"
        function dbusAparienciaCambiada(carga) {
            const nueva = JSON.parse(carga)
            if (nueva && typeof nueva.tema === "string") {
                raiz.temaRecibido = true
                raiz.apariencia = Object.assign({}, raiz.apariencia, nueva)
            }
        }

        function dbusUbicacionCambiada(carga) {
            const ciudad = JSON.parse(carga)
            if (raiz.calendario && ciudad.pais !== raiz.paisFeriados) {
                raiz.paisFeriados = ciudad.pais
                raiz.anioConsultado = 0
                raiz.consultarFeriados()
            } else if (raiz.tipo === "clima") {
                datosExtra.aplicarUbicacion(ciudad)
            }
        }
    }

    PlasmaSupport.DataSource {
        id: datos
        readonly property string fuenteRendimiento: raiz.rendimiento
            ? "/usr/bin/python3 -S " + raiz.archivoAuxiliar("rendimiento.py") : ""
        engine: "executable"
        interval: raiz.rendimiento ? 3500 : 0
        connectedSources: raiz.rendimiento ? [fuenteRendimiento] : []
        onNewData: (fuente, respuesta) => {
            if (typeof respuesta.stdout !== "string")
                return
            if (fuente === raiz.consulta) {
                disconnectSource(fuente)
                raiz.consulta = ""
            } else if (fuente !== fuenteRendimiento) {
                return
            }
            try {
                const nueva = JSON.parse(respuesta.stdout)
                if (raiz.rendimiento && typeof nueva.ticks === "number") {
                    const anterior = raiz.muestraAnterior
                    if (anterior && nueva.ticks > anterior.ticks) {
                        const carga = 1 - (nueva.inactivos - anterior.inactivos) / (nueva.ticks - anterior.ticks)
                        raiz.cpu = Math.round(100 * Math.max(0, Math.min(1, carga)))
                    }
                    raiz.muestraAnterior = nueva
                    raiz.apariencia = Object.assign({}, raiz.apariencia, nueva)
                }
                if (!raiz.temaRecibido && nueva.tema)
                    raiz.apariencia = Object.assign({}, raiz.apariencia, nueva)
            } catch (_) {
                // Conserva el último tema válido.
            }
        }
    }

    function ajustarTamano() {
        const item = soporte
        if (enPanel || !item?.layout)
            return
        const layout = item.layout
        const colocado = layout.itemIsManaged(item)
        if (colocado)
            layout.releaseSpace(item)
        item.width = mini ? anchoMini : Math.max(anchoMinimo, preferencias["anchoUsuario"] || ancho)
        item.height = mini ? altoMini : Math.max(altoMinimo, preferencias["altoUsuario"] || alto)
        if (colocado) {
            layout.positionItem(item)
            layout.save()
        }
    }

    function alternarTamano() {
        preferencias["compacto"] = !mini
        Qt.callLater(ajustarTamano)
    }

    function prepararSoporte() {
        if (enPanel || !soporte)
            return
        soporte.editModeCondition = DesktopLayout.ItemContainer.Manual
        if (mini || rendimiento || preferencias["anchoUsuario"])
            Qt.callLater(ajustarTamano)
    }

    onSoporteChanged: prepararSoporte()
    onEnPanelChanged: prepararSoporte()
    Component.onCompleted: {
        prepararSoporte()
        consultar("apariencia")
    }
    Timer {
        running: raiz.reloj || raiz.relojModerno || raiz.calendario
        repeat: true
        interval: raiz.calendario && raiz.enPanel ? 1000
            : 60000 - (raiz.ahora.getSeconds() * 1000 + raiz.ahora.getMilliseconds())
        onTriggered: raiz.ahora = new Date()
    }

    onExpandedChanged: if (enPanel && expanded) {
        consultarFeriados()
        datosExtra.actualizar(false)
    }

    function zonaUtc(fecha) {
        const minutos = -fecha.getTimezoneOffset()
        const absoluto = Math.abs(minutos)
        return "UTC" + (minutos < 0 ? "-" : "+")
            + String(Math.floor(absoluto / 60)).padStart(2, "0") + ":"
            + String(absoluto % 60).padStart(2, "0")
    }

    function formatearHoraPanel(fecha, formato) {
        return Qt.formatTime(fecha, formato === 1 ? "h:mm AP" : "HH:mm")
    }

    function formatearFechaPanel(fecha, formato) {
        const regional = Qt.locale()
        if (formato === 1)
            return fecha.toLocaleDateString(regional, "d") + " "
                + inicialMayuscula(fecha.toLocaleDateString(regional, "MMM"))
        if (formato === 2) {
            const dia = fecha.toLocaleDateString(regional, "dddd")
            const mes = fecha.toLocaleDateString(regional, "MMMM")
            return fecha.toLocaleDateString(regional, Locale.LongFormat)
                .replace(dia, inicialMayuscula(dia))
                .replace(mes, inicialMayuscula(mes))
        }
        return Qt.formatDate(fecha, formato === 3 ? "yyyy-MM-dd" : "dd/MM/yyyy")
    }

    readonly property string horaPanel: formatearHoraPanel(ahora, preferencias["formatoHoraPanel"])
    readonly property string fechaPanel: formatearFechaPanel(ahora, preferencias["formatoFechaPanel"])

    compactRepresentation: Loader {
        Layout.minimumWidth: implicitWidth
        Layout.minimumHeight: raiz.tipo === "musica" && Plasmoid.formFactor === PlasmaCore.Types.Horizontal
            ? 0 : implicitHeight
        sourceComponent: raiz.tipo === "musica" ? musicaPanel : accesoPanel
    }

    Component {
        id: musicaPanel
        MusicaPanel {
            grosorPanel: Math.max(1, vertical ? raiz.width : raiz.height)
            modelo: datosExtra
            acento: raiz.acento
            vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
            abierto: raiz.expanded
            onAlternar: raiz.expanded = !raiz.expanded
        }
    }
    Component {
        id: accesoPanel
        AccesoPanel {
            acento: raiz.acento
            titulo: raiz.temporizador && raiz.modoCronometro ? "Cronómetro" : Plasmoid.title
            icon.name: raiz.iconoPanel
            vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
            abierto: raiz.expanded
            mostrarAyuda: !raiz.calendario
            resaltarAbierto: !raiz.calendario
            anchoTexto: raiz.calendario ? 330 : 114
            textoVertical: raiz.calendario ? raiz.horaPanel.replace(" ", "\n")
                + "\n" + Qt.formatDate(raiz.ahora, "dd/MM") : ""
            text: {
                if (raiz.reloj || raiz.relojModerno)
                    return Qt.formatTime(raiz.ahora, "HH:mm")
                if (raiz.calendario)
                    return raiz.horaPanel + " · " + raiz.fechaPanel
                if (raiz.rendimiento)
                    return raiz.cpu < 0 ? "CPU …" : "CPU " + raiz.cpu + "%"
                if (raiz.temporizador)
                    return raiz.controlTiempo.texto.split(".")[0]
                return raiz.utilidadExtra ? datosExtra.resumen : ""
            }
            onClicked: raiz.expanded = !raiz.expanded
        }
    }

    component BandejaCalendario: ColumnLayout {
        id: bandeja
        spacing: 5
        readonly property int altoAviso: 58
        readonly property real pasoAviso: altoAviso + listaAvisos.spacing

        Controls.Label {
            id: tituloAvisos
            visible: raiz.enPanel
            text: "Notificaciones"
            font.bold: true
            color: raiz.texto
        }
        Controls.Label {
            visible: !raiz.avisosDisponibles
            Layout.fillHeight: true
            Layout.fillWidth: true
            text: "No hay notificaciones"
            color: Qt.alpha(raiz.texto, 0.78)
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        ListView {
            id: listaAvisos
            visible: raiz.avisosDisponibles
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: raiz.modeloAvisos
            clip: true
            interactive: !raiz.enPanel
            boundsBehavior: Flickable.StopAtBounds
            spacing: 4

            delegate: Rectangle {
                id: aviso
                required property string applicationName
                required property string summary
                required property string body
                required property int index
                required property bool hasDefaultAction
                required property bool closable
                readonly property string detalle: body.replace(/<br\s*\/?\s*>/gi, " ")
                    .replace(/<[^>]*>/g, "").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&")
                width: listaAvisos.width
                height: bandeja.altoAviso
                HoverHandler { id: cursorAviso }
                Controls.ToolTip.visible: cursorAviso.hovered && !!aviso.detalle
                Controls.ToolTip.delay: 700
                Controls.ToolTip.text: aviso.detalle.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
                radius: 6
                color: Qt.alpha(raiz.texto, 0.07)

                Controls.AbstractButton {
                    anchors.fill: parent
                    anchors.rightMargin: descartar.visible ? descartar.width + 5 : 0
                    enabled: aviso.hasDefaultAction
                    Accessible.name: "Abrir " + (aviso.summary || aviso.applicationName)
                    onClicked: raiz.modeloAvisos.invokeDefaultAction(raiz.modeloAvisos.index(aviso.index, 0))
                }
                BotonNota {
                    id: descartar
                    visible: aviso.closable
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Descartar notificación"
                    icon.name: "window-close-symbolic"
                    onClicked: raiz.modeloAvisos.close(raiz.modeloAvisos.index(aviso.index, 0))
                }
                Column {
                    id: textoAviso
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 5
                    anchors.rightMargin: descartar.visible ? descartar.width + 8 : 5
                    spacing: 0
                    Repeater {
                        model: [aviso.applicationName, aviso.summary, aviso.detalle]
                        delegate: Controls.Label {
                            required property string modelData
                            required property int index
                            visible: !!modelData
                            width: textoAviso.width
                            text: modelData
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            color: index === 1 ? raiz.texto : Qt.alpha(raiz.texto, 0.79)
                            font.bold: index === 1
                            font.pixelSize: index === 1 ? 12 : 10
                        }
                    }
                }
            }
        }
        RowLayout {
            visible: raiz.enPanel && listaAvisos.count * bandeja.pasoAviso - listaAvisos.spacing > bandeja.height - tituloAvisos.height - bandeja.spacing
            Layout.alignment: Qt.AlignHCenter
            BotonMes {
                anterior: true
                enabled: !listaAvisos.atYBeginning
                Accessible.name: "Ver notificaciones anteriores"
                onClicked: listaAvisos.contentY = Math.max(listaAvisos.originY,
                    listaAvisos.contentY - bandeja.pasoAviso * Math.max(1, Math.floor(listaAvisos.height / bandeja.pasoAviso)))
            }
            BotonMes {
                anterior: false
                enabled: !listaAvisos.atYEnd
                Accessible.name: "Ver más notificaciones"
                onClicked: listaAvisos.contentY = Math.min(listaAvisos.originY + listaAvisos.contentHeight - listaAvisos.height,
                    listaAvisos.contentY + bandeja.pasoAviso * Math.max(1, Math.floor(listaAvisos.height / bandeja.pasoAviso)))
            }
        }
    }

    component CalendarioPanel: ColumnLayout {
        id: panelMes
        property int vista: 0
        property date elegido: raiz.ahora
        readonly property int inicioDecada: Math.floor(raiz.mes.getFullYear() / 10) * 10
        readonly property date primerDia: new Date(raiz.mes.getFullYear(), raiz.mes.getMonth(),
            1 - (raiz.mes.getDay() + 6) % 7)

        function avanzar(direccion) {
            const desplazamiento = vista === 0 ? direccion : vista === 1 ? direccion * 12 : direccion * 120
            raiz.mes = new Date(raiz.mes.getFullYear(), raiz.mes.getMonth() + desplazamiento, 1)
        }

        function semana(fecha) {
            const jueves = new Date(Date.UTC(fecha.getFullYear(), fecha.getMonth(), fecha.getDate()))
            jueves.setUTCDate(jueves.getUTCDate() + 3 - (jueves.getUTCDay() + 6) % 7)
            return Math.ceil(((jueves - Date.UTC(jueves.getUTCFullYear(), 0, 1)) / 86400000 + 1) / 7)
        }

        RowLayout {
            Layout.fillWidth: true
            Controls.Label {
                Layout.fillWidth: true
                elide: Text.ElideRight
                color: raiz.texto
                font.pixelSize: 19
                font.bold: true
                text: panelMes.vista === 0
                    ? raiz.inicialMayuscula(raiz.mes.toLocaleDateString(Qt.locale(), "MMMM yyyy"))
                    : panelMes.vista === 1 ? String(raiz.mes.getFullYear())
                    : panelMes.inicioDecada + " – " + (panelMes.inicioDecada + 9)
            }
            BotonMes {
                anterior: true
                Accessible.name: "Periodo anterior"
                onClicked: panelMes.avanzar(-1)
            }
            Controls.Button {
                id: hoyPanel
                text: "Hoy"
                contentItem: Text {
                    text: hoyPanel.text
                    color: raiz.texto
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    radius: 7
                    color: Qt.alpha(raiz.texto, hoyPanel.down ? 0.20 : hoyPanel.hovered ? 0.13 : 0.07)
                    border.width: hoyPanel.visualFocus ? 1 : 0
                    border.color: raiz.texto
                }
                onClicked: {
                    panelMes.elegido = raiz.ahora
                    raiz.mes = new Date(raiz.ahora.getFullYear(), raiz.ahora.getMonth(), 1)
                    panelMes.vista = 0
                }
            }
            BotonMes {
                anterior: false
                Accessible.name: "Periodo siguiente"
                onClicked: panelMes.avanzar(1)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Repeater {
                model: ["Días", "Meses", "Años"]
                delegate: BotonTemporizador {
                    required property string modelData
                    required property int index
                    principal: panelMes.vista === index
                    text: modelData
                    onClicked: panelMes.vista = index
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: panelMes.vista === 0 ? 8 : 4
            uniformCellWidths: true
            columnSpacing: 3
            rowSpacing: 3
            Repeater {
                model: panelMes.vista === 0 ? 56 : 12
                delegate: Controls.AbstractButton {
                    id: casillaPanel
                    required property int index
                    readonly property bool dias: panelMes.vista === 0
                    readonly property bool rotulo: dias && (index < 8 || index % 8 === 0)
                    readonly property date fecha: new Date(panelMes.primerDia.getFullYear(), panelMes.primerDia.getMonth(),
                        panelMes.primerDia.getDate() + (Math.floor(index / 8) - 1) * 7 + Math.max(0, index % 8 - 1))
                    readonly property int anio: panelMes.inicioDecada + index - 1
                    readonly property string feriado: dias && !rotulo ? raiz.feriado(fecha) : ""
                    hoverEnabled: true
                    Controls.ToolTip.visible: hovered && !!feriado
                    Controls.ToolTip.text: feriado
                    Controls.ToolTip.delay: 400
                    readonly property bool seleccionado: dias ? !rotulo && fecha.toDateString() === panelMes.elegido.toDateString()
                        : panelMes.vista === 1 ? index === raiz.mes.getMonth() : anio === raiz.mes.getFullYear()
                    readonly property bool atenuado: rotulo || (dias ? fecha.getMonth() !== raiz.mes.getMonth()
                        : panelMes.vista === 2 && (index === 0 || index === 11))
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 1
                    padding: 0
                    enabled: !rotulo
                    Accessible.name: dias && !rotulo ? fecha.toLocaleDateString(Qt.locale(), "dddd d MMMM yyyy") + (feriado ? ", " + feriado : "") : text
                    text: {
                        if (!dias)
                            return panelMes.vista === 1 ? raiz.inicialMayuscula(new Date(2000, index, 1)
                                .toLocaleDateString(Qt.locale(), "MMM")) : String(anio)
                        if (index < 8)
                            return index === 0 ? "" : new Date(2024, 0, index)
                                .toLocaleDateString(Qt.locale(), "ddd").charAt(0).toLocaleUpperCase()
                        return rotulo ? String(panelMes.semana(fecha)) : String(fecha.getDate())
                    }
                    contentItem: Text {
                        text: casillaPanel.text
                        color: casillaPanel.atenuado ? Qt.alpha(raiz.texto, 0.64) : raiz.texto
                        font.pixelSize: casillaPanel.rotulo ? 11 : 14
                        font.bold: casillaPanel.seleccionado
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: 7
                        color: casillaPanel.seleccionado ? Qt.alpha(raiz.acento, 0.32)
                            : casillaPanel.hovered && !casillaPanel.rotulo ? Qt.alpha(raiz.texto, 0.08) : "transparent"
                        border.width: casillaPanel.visualFocus || casillaPanel.seleccionado ? 1 : 0
                        border.color: raiz.acento
                    }
                    Rectangle {
                        visible: !!casillaPanel.feriado
                        width: Math.min(14, parent.width - 4)
                        height: 2
                        radius: 1
                        color: raiz.acento
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 2
                    }
                    onClicked: {
                        if (dias) {
                            panelMes.elegido = fecha
                            raiz.mes = new Date(fecha.getFullYear(), fecha.getMonth(), 1)
                        } else if (panelMes.vista === 1) {
                            raiz.mes = new Date(raiz.mes.getFullYear(), index, 1)
                            panelMes.vista = 0
                        } else {
                            raiz.mes = new Date(anio, raiz.mes.getMonth(), 1)
                            panelMes.vista = 1
                        }
                    }
                }
            }
        }
    }

    component BotonMes: Controls.ToolButton {
        id: botonMes
        required property bool anterior
        contentItem: Item {
            implicitWidth: 16
            implicitHeight: 16
            Flecha {
                anchors.centerIn: parent
                rotation: botonMes.anterior ? 180 : 0
                colorTrazo: raiz.texto
            }
        }
    }

    component BotonNota: Controls.ToolButton {
        id: botonNota
        implicitWidth: 28
        implicitHeight: 26
        hoverEnabled: true
        Accessible.name: text
        property bool mostrarAyuda: true
        Controls.ToolTip.visible: mostrarAyuda && hovered
        Controls.ToolTip.delay: 500
        Controls.ToolTip.text: text
        background: Rectangle {
            radius: 6
            color: botonNota.down || botonNota.visualFocus || botonNota.checked ? Qt.alpha(raiz.acento, 0.2) : "transparent"
        }
        contentItem: Item {
            Kirigami.Icon {
                anchors.centerIn: parent
                width: 15
                height: 15
                source: botonNota.icon.name
                isMask: true
                color: raiz.texto
                opacity: botonNota.enabled ? 0.85 : 0.3
            }
        }
    }

    component BotonTemporizador: Controls.Button {
        id: boton
        property bool principal: false
        Layout.fillWidth: true
        Layout.preferredHeight: 32
        Accessible.name: text
        contentItem: Text {
            text: boton.text
            color: boton.principal ? "white" : raiz.texto
            font: boton.font
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        font.bold: principal
        background: Rectangle {
            radius: 7
            border.color: Qt.alpha(raiz.acento, boton.visualFocus ? 1 : 0.65)
            color: boton.principal
                ? Qt.darker(raiz.acento, boton.down ? 2.1 : boton.hovered ? 1.6 : 1.8)
                : Qt.alpha(raiz.acento, boton.down ? 0.32 : boton.hovered ? 0.23 : 0.14)
        }
    }

    component PasoMinutos: Rectangle {
        property string signo
        implicitWidth: 32
        radius: 7
        color: Qt.alpha(raiz.acento, enabled ? 0.24 : 0.08)
        Text {
            anchors.centerIn: parent
            text: parent.signo
            color: raiz.texto
            opacity: parent.enabled ? 1 : 0.45
            font.pixelSize: 16
        }
    }

    component Superficie: Rectangle {
        id: superficie
        property bool enMovimiento: false
        color: "transparent"
        border.width: raiz.enPanel || raiz.relojModerno || raiz.esBusqueda ? 0 : 1
        border.color: raiz.borde
        gradient: raiz.enPanel || raiz.relojModerno || raiz.esBusqueda ? null : degradado
        property Gradient degradado: Gradient {
            GradientStop { position: 0; color: raiz.superficieSuperior }
            GradientStop { position: 1; color: raiz.superficieInferior }
        }
        FondoDifuso { active: !raiz.enPanel && !raiz.relojModerno && !raiz.esBusqueda && raiz.esmerilado && !superficie.enMovimiento; fondo: raiz.fondo; radio: superficie.radius }
    }

    fullRepresentation: Superficie {
        id: tarjeta
        enMovimiento: !!mover.contenedor
        readonly property var ventanaTarjeta: Window.window
        Layout.maximumWidth: raiz.enPanel ? raiz.tamanoPanel.width : Infinity
        Layout.maximumHeight: raiz.enPanel ? raiz.tamanoPanel.height : Infinity
        clip: raiz.enPanel
        Layout.minimumWidth: raiz.enPanel ? raiz.tamanoPanel.width : raiz.mini ? raiz.anchoMini : raiz.anchoMinimo
        Layout.preferredWidth: raiz.enPanel ? raiz.tamanoPanel.width : raiz.mini ? raiz.anchoMini : raiz.ancho
        Layout.minimumHeight: raiz.enPanel ? raiz.tamanoPanel.height : raiz.mini ? raiz.altoMini : raiz.altoMinimo
        Layout.preferredHeight: raiz.enPanel ? raiz.tamanoPanel.height : raiz.mini ? raiz.altoMini : raiz.alto
        radius: raiz.mini ? 9 : 14

        readonly property bool mostrarMarcoReloj: !!raiz.preferencias["marcoRelojModerno"]
            || mover.active || cursorEdicionReloj.hovered

        HoverHandler {
            id: cursorEdicionReloj
            enabled: (raiz.relojModerno || raiz.esFoto || raiz.esBusqueda) && !raiz.enPanel && !raiz.mini
            acceptedModifiers: Qt.ControlModifier
        }

        Loader {
            active: raiz.esFoto && !raiz.enPanel
            function confirmar() {
                (item as Controls.Dialog)?.open()
            }
            id: confirmacionFoto
            sourceComponent: Controls.Dialog {
                title: "¿Eliminar este widget?"
                parent: tarjeta
                popupType: Controls.Popup.Item
                anchors.centerIn: parent
                margins: 8
                modal: true
                width: 300
                contentItem: Controls.Label {
                    text: "Se quitará este marco del escritorio. El archivo de imagen se conservará."
                    wrapMode: Text.WordWrap
                }
                footer: Controls.DialogButtonBox {
                    Controls.Button {
                        text: "Cancelar"
                        Controls.DialogButtonBox.buttonRole: Controls.DialogButtonBox.RejectRole
                    }
                    Controls.Button {
                        text: "Eliminar widget"
                        Controls.DialogButtonBox.buttonRole: Controls.DialogButtonBox.AcceptRole
                    }
                }
                onAccepted: Plasmoid.internalAction("remove")?.trigger()
            }
        }

        Rectangle {
            anchors.fill: parent
            z: 1
            visible: !raiz.enPanel && !raiz.mini
                && (raiz.relojModerno && tarjeta.mostrarMarcoReloj
                    || raiz.esFoto || raiz.esBusqueda && (cursorEdicionReloj.hovered || mover.active))
            radius: tarjeta.radius
            color: "transparent"
            border.width: 1
            border.color: raiz.esFoto && !cursorEdicionReloj.hovered && !mover.active
                ? "#99ffffff" : "#e8ffffff"
        }
        HoverHandler {
            id: cursorRendimiento
            enabled: raiz.rendimiento && !raiz.mini
        }
        Controls.ToolTip.visible: cursorRendimiento.hovered && !mover.active
        Controls.ToolTip.delay: 500
        Controls.ToolTip.text: raiz.detallesRendimiento

        transform: Translate {
            x: mover.contenedor ? mover.destino.x - mover.contenedor.x : 0
            y: mover.contenedor ? mover.destino.y - mover.contenedor.y : 0
        }
        Loader {
            id: fotoEscritorio
            anchors.fill: parent
            active: raiz.esFoto && !raiz.enPanel && !raiz.mini
            visible: active
            sourceComponent: MarcoFoto {
                preferencias: raiz.preferencias
                tinta: raiz.texto
                editable: !mover.active
                radio: tarjeta.radius
            }
        }
        MouseArea {
            id: filtroMenu
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            onPressed: evento => {
                const titulo = raiz.mini ? tituloMini : interior.tituloMenu
                const punto = titulo.mapFromItem(filtroMenu, evento.x, evento.y)
                if (fotoEscritorio.active && !(cursorEdicionReloj.hovered
                        && titulo.contains(punto) && punto.x <= titulo.contentWidth)) {
                    evento.accepted = false
                    return
                }
                evento.accepted = !titulo.visible || !titulo.contains(punto)
                    || punto.x > titulo.leftPadding + titulo.contentWidth
            }
        }
        Arrastre {
            id: mover
            superficieCursor: filtroMenu
            tarjeta: parent
            encabezado: raiz.mini ? parent : interior.encabezado
            permiteRedimensionar: !raiz.mini
            bloquearInicio: (fotoEscritorio.item as MarcoFoto)?.encuadrando ?? false
            onTamanoElegido: (ancho, alto) => {
                raiz.preferencias["anchoUsuario"] = ancho
                raiz.preferencias["altoUsuario"] = alto
            }
            soporte: !raiz.enPanel && !Plasmoid.immutable ? raiz.soporte : null
        }
        RowLayout {
            visible: raiz.mini
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 5
            Controls.AbstractButton {
                id: abrirAcciones
                Layout.fillWidth: true
                Layout.fillHeight: true
                padding: 0
                text: raiz.reloj || raiz.relojModerno ? Qt.formatTime(raiz.ahora, "HH:mm") : raiz.temporizador ? raiz.controlTiempo.texto : Plasmoid.title.replace("Byotfast · ", "")
                Accessible.name: text
                contentItem: RowLayout {
                    spacing: 5
                    Kirigami.Icon {
                        source: raiz.icono
                        isMask: true
                        color: raiz.acento
                        Layout.preferredWidth: 18
                        Layout.preferredHeight: 18
                    }
                    Controls.Label {
                        id: tituloMini
                        text: abrirAcciones.text
                        color: raiz.texto
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                    }
                }
                onClicked: {
                    if (acciones.visible)
                        acciones.close()
                    else
                        acciones.open()
                }
            }
            BotonTamano {
                acento: raiz.acento
                restaurar: true
                onClicked: raiz.alternarTamano()
            }
        }
        Controls.Popup {
            id: acciones
            onVisibleChanged: raiz.accionesMiniVisibles = visible
            parent: tarjeta
            width: raiz.ancho
            height: raiz.alto
            padding: 12
            margins: 8
            focus: true
            closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutsideParent
            onAboutToShow: {
                const ventana = tarjeta.ventanaTarjeta
                const debajo = tarjeta.mapToItem(null, 0, tarjeta.height + 5).y
                y = ventana && debajo + height + 8 > ventana.height
                    ? -height - 5 : tarjeta.height + 5
            }
            background: Superficie { radius: 12 }
            contentItem: Loader {
                active: acciones.visible
                sourceComponent: Contenido {}
            }
        }
        Connections {
            target: raiz
            function onMiniChanged() {
                if (!raiz.mini)
                    acciones.close()
            }
        }
        Contenido {
            id: interior
            visible: !raiz.mini
            x: 12 * raiz.escalaControlesPanel
            y: (raiz.tipo === "musica" && !raiz.enPanel ? 9 : 12) * raiz.escalaControlesPanel
            width: (tarjeta.width - 2 * x) / scale
            height: (tarjeta.height - 2 * y) / scale
            transformOrigin: Item.TopLeft
            scale: raiz.esNotas || raiz.esFoto || raiz.esBusqueda || raiz.relojModerno || raiz.enPanel || raiz.controlesRapidos ? raiz.escalaControlesPanel : Math.max(1, Math.min((tarjeta.width - 24) / (raiz.reloj ? 126 : raiz.utilidadExtra ? 186 : raiz.anchoMinimo - 24),
                (tarjeta.height - 2 * y) / (raiz.alto - 2 * y)))
            mostrarBoton: !raiz.enPanel
        }

        component Contenido: ColumnLayout {
            id: controles
            property bool segundaVista: false
            property alias tituloMenu: tituloMenu
            property alias encabezado: filaEncabezado
            property bool mostrarBoton: false
            spacing: raiz.relojModerno && !raiz.enPanel ? 0 : raiz.tipo === "musica" ? 4 : 6
            Item {
                id: marcoEncabezado
                Layout.fillWidth: true
                readonly property real escalaCompensada: controles.scale / raiz.escalaControlesPanel
                z: 1
                Layout.preferredHeight: raiz.relojModerno && !raiz.enPanel ? 0 : (filaEncabezado.implicitHeight + (nombreReproductor.visible && raiz.enPanel ? nombreReproductor.implicitHeight : 0)) / escalaCompensada
                visible: (!raiz.reloj || controles.mostrarBoton || raiz.enPanel)
                    && (!raiz.esBusqueda || raiz.enPanel || cursorEdicionReloj.hovered || mover.active)
                opacity: raiz.esFoto && !raiz.enPanel ? (cursorEdicionReloj.hovered || mover.active || menuMarcoFoto.visible ? 1 : 0)
                    : raiz.relojModerno && !raiz.enPanel && !tarjeta.mostrarMarcoReloj ? 0 : 1
                enabled: !raiz.esFoto || raiz.enPanel || opacity > 0
                RowLayout {
                    id: filaEncabezado
                    readonly property bool centrado: raiz.enPanel
                    width: centrado ? implicitWidth : marcoEncabezado.width * marcoEncabezado.escalaCompensada
                    x: centrado ? (marcoEncabezado.width - width / marcoEncabezado.escalaCompensada) / 2 : 0
                    scale: 1 / marcoEncabezado.escalaCompensada
                    transformOrigin: Item.TopLeft
                    Kirigami.Icon {
                        source: raiz.icono
                        color: raiz.acento
                        isMask: true
                        Layout.preferredWidth: 22
                        Layout.preferredHeight: 22
                    }
                    Controls.Label {
                        id: tituloMenu
                        readonly property string nombreCompleto: raiz.temporizador && raiz.modoCronometro
                            ? "Cronómetro" : raiz.calendario && controles.segundaVista
                                ? "Notificaciones" : Plasmoid.title.replace("Byotfast · ", "")
                        text: !raiz.enPanel && medidaTitulo.advanceWidth > tituloMenu.width
                            ? nombreCompleto.trim().split(/\s+/)[0] : nombreCompleto
                        Accessible.name: nombreCompleto
                        TextMetrics {
                            id: medidaTitulo
                            font: tituloMenu.font
                            text: tituloMenu.nombreCompleto
                        }
                        color: raiz.texto
                        font.bold: true
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: raiz.relojModerno ? Math.ceil(medidaTitulo.advanceWidth) : implicitWidth
                        elide: Text.ElideRight
                        Layout.fillWidth: !filaEncabezado.centrado && !raiz.temporizador && !raiz.tieneSegundaVista && !raiz.relojModerno && !(raiz.esFoto && !raiz.enPanel)
                    }
                    BotonTamano {
                        id: opcionesMarcoFoto
                        visible: raiz.esFoto && !raiz.enPanel && (cursorEdicionReloj.hovered || menuMarcoFoto.visible)
                        acento: "#ffffff"
                        restaurar: false
                        simbolo: "open-menu-symbolic"
                        text: "Opciones de Fotos"
                        onClicked: menuMarcoFoto.open()

                        Controls.Menu {
                            id: menuMarcoFoto
                            y: opcionesMarcoFoto.height
                            Controls.MenuItem {
                                text: "Cambiar imagen…"
                                icon.name: "document-open-symbolic"
                                onTriggered: (fotoEscritorio.item as MarcoFoto)?.elegirFoto()
                            }
                            Controls.MenuItem {
                                text: "Añadir nuevo marco"
                                icon.name: "list-add-symbolic"
                                onTriggered: {
                                    const origen = Number(Plasmoid.id)
                                    const script = "const origen = " + origen + ";"
                                        + "const escritorio = desktops().find(d => d.widgets().some(w => Number(w.id) === origen));"
                                        + "if (escritorio) escritorio.addWidget('org.local.Byotfast.fotos');"
                                    DBus.SessionBus.asyncCall({
                                        service: "org.kde.plasmashell",
                                        path: "/PlasmaShell",
                                        iface: "org.kde.PlasmaShell",
                                        member: "evaluateScript",
                                        arguments: [script]
                                    })
                                }
                            }
                        }
                    }
                    BotonTamano {
                        visible: raiz.relojModerno && controles.mostrarBoton
                            && tarjeta.mostrarMarcoReloj
                        acento: "#ffffff"
                        restaurar: false
                        simbolo: "view-fullscreen-symbolic"
                        checkable: true
                        checked: !!raiz.preferencias["marcoRelojModerno"]
                        text: checked ? "Ocultar borde y título" : "Mostrar borde y título"
                        onClicked: raiz.preferencias["marcoRelojModerno"] = checked
                    }
                    BotonTamano {
                        visible: raiz.temporizador
                        acento: raiz.texto
                        restaurar: false
                        mostrarSimbolo: false
                        text: raiz.modoCronometro ? "Cambiar a temporizador" : "Cambiar a cronómetro"
                        onClicked: raiz.modoCronometro = !raiz.modoCronometro
                    }
                    BotonTamano {
                        visible: raiz.tieneSegundaVista
                        acento: raiz.texto
                        restaurar: false
                        mostrarSimbolo: false
                        text: raiz.calendario ? (controles.segundaVista ? "Ver calendario" : "Ver notificaciones")
                            : raiz.tipo === "clima"
                            ? (controles.segundaVista ? "Ver clima actual" : "Ver pronóstico por hora")
                            : (controles.segundaVista ? "Volver a la calculadora" : "Ver historial")
                        onClicked: controles.segundaVista = !controles.segundaVista
                    }
                    Item {
                        visible: raiz.temporizador || raiz.tieneSegundaVista || ((raiz.relojModerno || raiz.esFoto) && !raiz.enPanel)
                        Layout.fillWidth: true
                    }
                    BotonTamano {
                        id: botonAccionMarco
                        visible: controles.mostrarBoton
                        acento: raiz.esFoto && botonAccionMarco.resaltado ? "#e35b65" : raiz.acento
                        restaurar: false
                        simbolo: raiz.esFoto ? "edit-delete-symbolic" : "window-minimize"
                        text: raiz.esFoto ? "Eliminar widget" : "Minimizar widget"
                        onClicked: {
                            if (raiz.esFoto)
                                confirmacionFoto.confirmar()
                            else
                                raiz.alternarTamano()
                        }
                    }
                }
                BotonNota {
                    visible: raiz.controlesRapidos && raiz.enPanel
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Editar distribución"
                    icon.name: "document-edit-symbolic"
                    checkable: true
                    checked: (controlesWidget.item as ControlesRapidos)?.editando ?? false
                    onClicked: {
                        const card = controlesWidget.item as ControlesRapidos
                        if (card) {
                            card.vista = ""
                            card.editando = checked
                        }
                    }
                }
                BotonNota {
                    id: formatoPanel
                    mostrarAyuda: false
                    visible: raiz.calendario && raiz.enPanel
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Formato de hora y fecha"
                    icon.name: "configure"
                    onClicked: {
                        if (raiz.expanded)
                            opcionesFormato.open()
                    }
                    Connections {
                        target: raiz
                        function onExpandedChanged() {
                            if (!raiz.expanded)
                                opcionesFormato.close()
                        }
                    }
                    Controls.Menu {
                        id: opcionesFormato
                        y: formatoPanel.height
                        title: formatoPanel.text
                        Controls.MenuItem { text: "Hora"; enabled: false }
                        Controls.ButtonGroup { id: formatosHora }
                        Instantiator {
                            onObjectAdded: (indice, opcion) => opcionesFormato.insertItem(1 + indice, opcion)
                            onObjectRemoved: (indice, opcion) => opcionesFormato.removeItem(opcion)
                            model: ["24 horas", "12 horas"]
                            delegate: Controls.MenuItem {
                                required property string modelData
                                required property int index
                                text: modelData + "  ·  " + raiz.formatearHoraPanel(raiz.ahora, index)
                                checkable: true
                                Controls.ButtonGroup.group: formatosHora
                                checked: raiz.preferencias["formatoHoraPanel"] === index
                                onTriggered: raiz.preferencias["formatoHoraPanel"] = index
                            }
                        }
                        Controls.MenuSeparator {}
                        Controls.MenuItem { text: "Fecha"; enabled: false }
                        Controls.ButtonGroup { id: formatosFecha }
                        Instantiator {
                            onObjectAdded: (indice, opcion) => opcionesFormato.insertItem(5 + indice, opcion)
                            onObjectRemoved: (indice, opcion) => opcionesFormato.removeItem(opcion)
                            model: ["Numérica", "Corta", "Completa", "ISO"]
                            delegate: Controls.MenuItem {
                                required property string modelData
                                required property int index
                                text: modelData + "  ·  " + raiz.formatearFechaPanel(raiz.ahora, index)
                                checkable: true
                                Controls.ButtonGroup.group: formatosFecha
                                checked: raiz.preferencias["formatoFechaPanel"] === index
                                onTriggered: raiz.preferencias["formatoFechaPanel"] = index
                            }
                        }
                    }
                }
                Controls.Label {
                    id: nombreReproductor
                    visible: raiz.tipo === "musica" && !!text
                    text: raiz.tipo === "musica" ? datosExtra.musicaVisible.reproductor || "" : ""
                    textFormat: Text.PlainText
                    color: Qt.alpha(raiz.texto, 0.78)
                    font.pixelSize: 11
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    readonly property real margenLateral: raiz.enPanel ? 0 : 22 + 2 * filaEncabezado.spacing + tituloMenu.implicitWidth
                    width: Math.min(implicitWidth, Math.max(0, marcoEncabezado.width * controles.scale - 2 * margenLateral))
                    x: (marcoEncabezado.width - width / controles.scale) / 2
                    y: (raiz.enPanel ? filaEncabezado.implicitHeight
                        : (filaEncabezado.implicitHeight - height) / 2) / controles.scale
                    scale: 1 / controles.scale
                    transformOrigin: Item.TopLeft
                }
            }
            Loader {
                active: raiz.relojModerno
                visible: active
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 0
                Layout.preferredHeight: 0
                sourceComponent: Item {
                    id: caraModerna
                    readonly property string directorioFuentes: StandardPaths.writableLocation(StandardPaths.GenericDataLocation)
                        + "/plasma/plasmoids/com.github.prayag2.modernclock/contents/fonts/"
                    readonly property color colorReloj: raiz.enPanel ? raiz.texto : "white"
                    readonly property real escalaReloj: Math.max(0.1, Math.min(
                        Math.max(1, width - 8) / Math.max(1, medidaDia.advanceWidth, medidaFecha.advanceWidth, medidaHora.advanceWidth),
                        Math.max(1, height - (raiz.enPanel ? 12 : 50))
                            / (metricasDia.lineSpacing + 2 * metricasDatos.lineSpacing + 8)))
                    FontMetrics { id: metricasDia; font: medidaDia.font }
                    FontMetrics { id: metricasDatos; font: medidaFecha.font }
                    TextMetrics {
                        id: medidaDia
                        font.family: fuenteDia.status === FontLoader.Ready ? fuenteDia.name : Kirigami.Theme.defaultFont.family
                        font.pixelSize: 76
                        font.letterSpacing: 3
                        text: raiz.ahora.toLocaleDateString(Qt.locale("en_US"), "dddd").toUpperCase()
                    }
                    TextMetrics {
                        id: medidaFecha
                        font.family: fuenteDatos.status === FontLoader.Ready ? fuenteDatos.name : Kirigami.Theme.defaultFont.family
                        font.pixelSize: 16
                        font.letterSpacing: 2
                        text: raiz.ahora.toLocaleDateString(Qt.locale("en_US"), "dd MMM yyyy").toUpperCase()
                    }
                    TextMetrics {
                        id: medidaHora
                        font: medidaFecha.font
                        text: "–  " + Qt.formatTime(raiz.ahora, "hh:mm AP") + "  –"
                    }
                    FontLoader { id: fuenteDia; source: caraModerna.directorioFuentes + "Anurati.otf" }
                    FontLoader { id: fuenteDatos; source: caraModerna.directorioFuentes + "Poppins.ttf" }

                    Column {
                        anchors.centerIn: parent
                        width: parent.width
                        spacing: 2
                        Repeater {
                            model: [medidaDia, medidaFecha, medidaHora]
                            delegate: Text {
                                required property TextMetrics modelData
                                required property int index
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData.text
                                renderType: Text.QtRendering
                                renderTypeQuality: index === 0 ? Text.HighRenderTypeQuality : Text.DefaultRenderTypeQuality
                                color: caraModerna.colorReloj
                                style: index === 0 && !raiz.enPanel ? Text.Outline : Text.Normal
                                styleColor: "#66000000"
                                font.family: modelData.font.family
                                font.pixelSize: Math.max(1, Math.floor(modelData.font.pixelSize * caraModerna.escalaReloj))
                                font.letterSpacing: modelData.font.letterSpacing * caraModerna.escalaReloj
                            }
                        }
                    }
                }
            }
            RowLayout {
                id: cuerpoCalendario
                readonly property bool dividido: raiz.calendario && raiz.enPanel && raiz.avisosDisponibles
                readonly property int anchoColumna: Math.max(0, Math.floor((controles.width - 2 * spacing - 1) / 2))
                visible: raiz.reloj || raiz.calendario
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12

                Loader {
                    active: raiz.calendario && (raiz.enPanel ? raiz.avisosDisponibles : controles.segundaVista)
                    visible: active
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: cuerpoCalendario.dividido ? cuerpoCalendario.anchoColumna : 0
                    Layout.preferredWidth: cuerpoCalendario.dividido ? cuerpoCalendario.anchoColumna : 224
                    Layout.maximumWidth: cuerpoCalendario.dividido ? cuerpoCalendario.anchoColumna : Infinity
                    sourceComponent: BandejaCalendario {}
                }
                Rectangle {
                    visible: raiz.calendario && raiz.enPanel && raiz.avisosDisponibles
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    color: Qt.alpha(raiz.texto, 0.18)
                }
                Loader {
                    active: raiz.calendario && raiz.enPanel
                    visible: active
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: cuerpoCalendario.dividido ? cuerpoCalendario.anchoColumna : 0
                    Layout.preferredWidth: cuerpoCalendario.dividido ? cuerpoCalendario.anchoColumna : 350
                    Layout.maximumWidth: cuerpoCalendario.dividido ? cuerpoCalendario.anchoColumna : Infinity
                    sourceComponent: CalendarioPanel {}
                }
                GrupoCentrado {
                    visible: !raiz.calendario || (!raiz.enPanel && !controles.segundaVista)
                    Layout.fillWidth: true
                    Layout.preferredWidth: raiz.enPanel ? 224 : -1
                    spacing: raiz.reloj ? 2 : 5
                    Controls.Label {
                        visible: raiz.reloj
                        Layout.alignment: Qt.AlignHCenter
                        text: Qt.formatTime(raiz.ahora, "HH:mm")
                        color: raiz.texto
                        font.pixelSize: 36
                        verticalAlignment: Text.AlignVCenter
                    }
                    Controls.Label {
                        visible: raiz.reloj
                        Layout.alignment: Qt.AlignHCenter
                        text: raiz.inicialMayuscula(raiz.ahora.toLocaleDateString(Qt.locale(), "ddd"))
                            + " " + raiz.ahora.toLocaleDateString(Qt.locale(), "d") + " "
                            + raiz.inicialMayuscula(raiz.ahora.toLocaleDateString(Qt.locale(), "MMM"))
                        color: raiz.texto
                    }
                    RowLayout {
                        visible: raiz.calendario
                        Layout.fillWidth: true
                        BotonMes {
                            anterior: true
                            Accessible.name: "Mes anterior"
                            onClicked: raiz.mes = new Date(raiz.mes.getFullYear(), raiz.mes.getMonth() - 1, 1)
                        }
                        Controls.Label {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: raiz.inicialMayuscula(raiz.mes.toLocaleDateString(Qt.locale(), "MMMM yyyy"))
                            color: raiz.texto
                        }
                        BotonMes {
                            anterior: false
                            Accessible.name: "Mes siguiente"
                            onClicked: raiz.mes = new Date(raiz.mes.getFullYear(), raiz.mes.getMonth() + 1, 1)
                        }
                    }
                    GridLayout {
                        visible: raiz.calendario
                        columns: 7
                        uniformCellWidths: true
                        columnSpacing: 2
                        rowSpacing: 1
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Repeater {
                            model: 49
                            delegate: Rectangle {
                                id: celda
                                required property int index
                                readonly property var fecha: new Date(raiz.mes.getFullYear(), raiz.mes.getMonth(),
                                    index - 6 - ((raiz.mes.getDay() + 6) % 7))
                                readonly property bool hoy: index >= 7 && fecha.toDateString() === raiz.ahora.toDateString()
                                readonly property string feriado: index >= 7 && fecha.getMonth() === raiz.mes.getMonth()
                                    ? raiz.feriado(fecha) : ""
                                HoverHandler { id: cursorFeriado }
                                Controls.ToolTip.visible: cursorFeriado.hovered && !!feriado
                                Controls.ToolTip.text: feriado
                                Rectangle {
                                    visible: !!celda.feriado
                                    width: 10
                                    height: 2
                                    radius: 1
                                    color: celda.hoy ? "white" : raiz.acento
                                    anchors.bottom: parent.bottom
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.minimumHeight: 16
                                radius: 5
                                color: hoy ? Qt.darker(raiz.acento, 1.45) : "transparent"
                                Controls.Label {
                                    anchors.centerIn: parent
                                    font.pixelSize: 11
                                    color: celda.hoy ? "white" : raiz.texto
                                    text: celda.index < 7 ? new Date(2024, 0, celda.index + 1).toLocaleDateString(Qt.locale(), "ddd").charAt(0).toLocaleUpperCase()
                                        : celda.fecha.getMonth() === raiz.mes.getMonth() ? String(celda.fecha.getDate()) : ""
                                }
                            }
                        }
                    }
                }
            }
            Item {
                visible: raiz.rendimiento
                Layout.fillWidth: true
                Layout.fillHeight: true
                HoverHandler { id: cursorMedidores }
                Controls.ToolTip.visible: raiz.mini && cursorMedidores.hovered
                Controls.ToolTip.delay: 500
                Controls.ToolTip.text: raiz.detallesRendimiento
                RowLayout {
                    anchors.centerIn: parent
                    spacing: 10
                    Repeater {
                        model: [
                            {nombre: "CPU", valor: raiz.cpu},
                            {nombre: "RAM", valor: raiz.apariencia.ram ?? -1}
                        ]
                        delegate: ColumnLayout {
                            id: medidor
                            required property var modelData
                            spacing: 4
                            Anillo {
                                Layout.alignment: Qt.AlignHCenter
                                nivel: medidor.modelData.valor
                                tinta: raiz.texto
                                acento: raiz.acento
                            }
                            Controls.Label {
                                Layout.alignment: Qt.AlignHCenter
                                text: medidor.modelData.nombre
                                color: raiz.texto
                            }
                        }
                    }
                }
            }
            GrupoCentrado {
                visible: raiz.temporizador
                Controls.Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: raiz.controlTiempo.texto
                    color: raiz.texto
                    font.pixelSize: 30
                    minimumPixelSize: 14
                    fontSizeMode: Text.HorizontalFit
                    Controls.ToolTip.visible: avisoCursor.hovered && !raiz.modoCronometro && !!raiz.aviso
                    Controls.ToolTip.text: raiz.aviso
                    HoverHandler { id: avisoCursor }
                }
                RowLayout {
                    visible: !raiz.modoCronometro
                    Layout.fillWidth: true
                    Controls.ComboBox {
                        id: unidadTiempo
                        model: ["Minutos", "Horas", "Días", "Meses"]
                        leftPadding: unidadTiempo.mirrored ? 28 : 7
                        rightPadding: unidadTiempo.mirrored ? 7 : 28
                        contentItem: Controls.Label {
                            text: unidadTiempo.displayText
                            color: raiz.texto
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }
                        indicator: Flecha {
                            x: unidadTiempo.mirrored ? 8 : unidadTiempo.width - width - 8
                            y: (unidadTiempo.height - height) / 2
                            width: 14
                            height: 14
                            rotation: unidadTiempo.popup.visible ? -90 : 90
                            colorTrazo: raiz.texto
                            opacity: unidadTiempo.enabled ? 1 : 0.45
                        }
                        Accessible.name: "Unidad del temporizador"
                        currentIndex: cuenta.unidad
                        enabled: !cuenta.activo
                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        onActivated: {
                            cuenta.unidad = currentIndex
                            cuenta.reiniciar()
                            raiz.aviso = ""
                        }
                    }
                    Controls.SpinBox {
                        id: minutos
                        Accessible.name: "Duración del temporizador"
                        Layout.preferredWidth: 112
                        Layout.preferredHeight: 32
                        leftPadding: 32
                        rightPadding: 32
                        from: 1
                        to: 99
                        value: cuenta.cantidad
                        enabled: !cuenta.activo
                        editable: true
                        background: Rectangle {
                            radius: 7
                            color: Qt.alpha(raiz.texto, 0.06)
                            border.color: Qt.alpha(raiz.acento, minutos.activeFocus ? 1 : 0.55)
                        }
                        contentItem: TextInput {
                            text: minutos.displayText
                            color: raiz.texto
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            inputMethodHints: Qt.ImhDigitsOnly
                            validator: minutos.validator
                            selectByMouse: true
                        }
                        down.indicator: PasoMinutos {
                            x: 1
                            y: 1
                            height: minutos.height - 2
                            signo: "−"
                            enabled: minutos.enabled && minutos.value > minutos.from
                            opacity: minutos.down.pressed ? 0.65 : 1
                        }
                        up.indicator: PasoMinutos {
                            x: minutos.width - width - 1
                            y: 1
                            height: minutos.height - 2
                            signo: "+"
                            enabled: minutos.enabled && minutos.value < minutos.to
                            opacity: minutos.up.pressed ? 0.65 : 1
                        }
                        onValueModified: {
                            cuenta.cantidad = value
                            cuenta.reiniciar()
                            raiz.aviso = ""
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    BotonTemporizador {
                        principal: true
                        text: raiz.controlTiempo.activo ? "Pausar" : "Iniciar"
                        onClicked: {
                            if (raiz.controlTiempo.activo) {
                                raiz.controlTiempo.pausar()
                            } else {
                                if (!raiz.modoCronometro)
                                    raiz.aviso = ""
                                raiz.controlTiempo.iniciar()
                            }
                        }
                    }
                    BotonTemporizador {
                        text: "Reiniciar"
                        onClicked: {
                            raiz.controlTiempo.reiniciar()
                            if (!raiz.modoCronometro)
                                raiz.aviso = ""
                        }
                    }
                }
            }
            Item {
                visible: raiz.esFoto && !raiz.enPanel
                Layout.fillHeight: true
            }
            Loader {
                active: raiz.esFoto && raiz.enPanel
                visible: active
                Layout.fillWidth: true
                Layout.fillHeight: true
                sourceComponent: MarcoFoto {
                    preferencias: raiz.preferencias
                    tinta: raiz.texto
                    editable: false
                }
            }
            Loader {
                active: raiz.esBusqueda && (!raiz.enPanel || raiz.expanded)
                onActiveChanged: if (!active) raiz.altoSugerenciasBusqueda = 0
                visible: active
                Layout.fillWidth: true
                Layout.fillHeight: true
                sourceComponent: BusquedaGoogle {
                    tinta: raiz.texto
                    acento: raiz.acento
                    fondo: raiz.oscuro ? "#20252c" : "#f4f6fa"
                    enPanel: raiz.enPanel
                    onAltoSugerenciasPanelChanged: raiz.altoSugerenciasBusqueda = altoSugerenciasPanel
                }
            }
            Loader {
                id: controlesWidget
                active: raiz.controlesRapidos && !!musicaRapida.item && (!raiz.enPanel || raiz.expanded)
                visible: active
                Layout.fillWidth: true
                Layout.fillHeight: true
                sourceComponent: ControlesRapidos {
                    id: contenidoControles
                    function ajustarFilasPanel() {
                        if (panel)
                            raiz.filasControlesPanel = filas
                    }
                    Component.onCompleted: ajustarFilasPanel()
                    onFilasChanged: ajustarFilasPanel()
                    modelo: datosExtra
                    musica: musicaRapida.item as DatosWidgets
                    tinta: raiz.texto
                    acento: raiz.acento
                    panel: raiz.enPanel
                }
            }
            Loader {
                active: raiz.utilidadExtra && !raiz.controlesRapidos
                visible: active
                Layout.fillWidth: true
                Layout.fillHeight: true
                sourceComponent: TarjetaUtilidad {
                    modelo: datosExtra
                    tinta: raiz.texto
                    acento: raiz.acento
                    segundaVista: controles.segundaVista
                    enPanel: raiz.enPanel
                    proporcion: controles.height > 0 ? controles.width / controles.height : 1
                    onVolverVistaPrincipal: controles.segundaVista = false
                }
            }

            ColumnLayout {
                id: panelNotas
                visible: raiz.esNotas
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 2
                property bool mostrarLista: false
                property int paginaNotas: 0
                readonly property int porPagina: 2
                property bool actualizando: true
                property bool negritaPendiente: false
                property bool cursivaPendiente: false
                property int cursorFormato: -1
                property bool escribiendoConFormato: false
                readonly property bool formatoPendiente: editor.cursorPosition === cursorFormato
                    && editor.selectionStart === editor.selectionEnd
                readonly property bool negritaActiva: formatoPendiente ? negritaPendiente
                    : editor.cursorSelection?.font.bold ?? false
                readonly property bool cursivaActiva: formatoPendiente ? cursivaPendiente
                    : editor.cursorSelection?.font.italic ?? false

                function cargarNota() {
                    const nota = raiz.notas[raiz.notaActiva]
                    actualizando = true
                    if (nota.formato === "html") {
                        editor.text = nota.cuerpo
                    } else if (/(\*[^*\n]+\*|^\s*(?:- |\d+\. ))/m.test(nota.cuerpo)) {
                        conversor.text = nota.cuerpo.replace(/</g, "&lt;")
                        const convertido = conversor.getFormattedText(0, conversor.length)
                        editor.text = convertido
                    } else {
                        editor.text = nota.cuerpo.replace(/&/g, "&amp;").replace(/</g, "&lt;")
                            .replace(/>/g, "&gt;").replace(/\n/g, "<br>")
                    }
                    editor.cursorPosition = 0
                    cursorFormato = -1
                    actualizando = false
                }

                function contenidoPlano() {
                    return editor.getText(0, editor.length).replace(/[\u2028\u2029]/g, "\n")
                }

                function guardarContenido() {
                    if (actualizando)
                        return
                    raiz.guardarNota({
                        titulo: raiz.notas[raiz.notaActiva].titulo,
                        cuerpo: editor.getFormattedText(0, editor.length),
                        formato: "html",
                        resumen: contenidoPlano().trim().split("\n")[0]
                    })
                }

                function alternarFormato(tipo) {
                    editor.forceActiveFocus()
                    const seleccion = editor.cursorSelection
                    if (!seleccion)
                        return
                    if (editor.selectionStart === editor.selectionEnd) {
                        const negrita = negritaActiva
                        const cursiva = cursivaActiva
                        negritaPendiente = tipo === "negrita" ? !negrita : negrita
                        cursivaPendiente = tipo === "cursiva" ? !cursiva : cursiva
                        cursorFormato = editor.cursorPosition
                    } else if (tipo === "negrita") {
                        seleccion.font.bold = !seleccion.font.bold
                    } else {
                        seleccion.font.italic = !seleccion.font.italic
                    }
                }

                function escribirConFormato(texto) {
                    if (!formatoPendiente)
                        return false
                    const inicio = editor.cursorPosition
                    const seguro = texto.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
                    const peso = negritaPendiente ? "700" : "400"
                    const estilo = cursivaPendiente ? "italic" : "normal"
                    escribiendoConFormato = true
                    editor.insert(inicio, '<span style="white-space:pre-wrap;font-weight:' + peso
                        + ';font-style:' + estilo + ';">' + seguro + '</span>')
                    editor.cursorPosition = inicio + texto.length
                    cursorFormato = editor.cursorPosition
                    escribiendoConFormato = false
                    return true
                }

                function marcaDe(linea) {
                    return linea.match(/^(• |- )|^(\d+)\. /)
                }

                function inicioLinea(plano, posicion) {
                    return posicion ? plano.lastIndexOf("\n", posicion - 1) + 1 : 0
                }

                function aplicarLista(numerada) {
                    const plano = contenidoPlano()
                    const inicio = editor.selectionStart
                    const fin = editor.selectionEnd
                    const primera = inicioLinea(plano, inicio)
                    const lineas = plano.slice(primera, fin).split("\n")
                    if (lineas.length > 1 && !lineas[lineas.length - 1])
                        lineas.pop()
                    const quitar = lineas.every(linea => {
                        const marca = marcaDe(linea)
                        return marca && !!marca[2] === numerada
                    })
                    let posicion = primera
                    actualizando = true
                    for (let i = 0; i < lineas.length; ++i) {
                        const marca = quitar ? "" : numerada ? (i + 1) + ". " : "• "
                        const anterior = marcaDe(lineas[i])
                        if (anterior)
                            editor.remove(posicion, posicion + anterior[0].length)
                        if (marca)
                            editor.insert(posicion, marca)
                        posicion += lineas[i].length - (anterior ? anterior[0].length : 0) + marca.length + 1
                    }
                    actualizando = false
                    guardarContenido()
                    editor.forceActiveFocus()
                    editor.cursorPosition = Math.min(posicion - 1, editor.length)
                }

                function continuarLista() {
                    if (editor.selectionStart !== editor.selectionEnd)
                        return false
                    const plano = contenidoPlano()
                    const cursor = editor.cursorPosition
                    const desde = inicioLinea(plano, cursor)
                    const salto = plano.indexOf("\n", cursor)
                    const linea = plano.slice(desde, salto < 0 ? plano.length : salto)
                    const marca = marcaDe(linea)
                    if (!marca || cursor < desde + marca[0].length)
                        return false

                    actualizando = true
                    if (!linea.slice(marca[0].length).trim()) {
                        editor.remove(desde, desde + linea.length)
                        editor.cursorPosition = desde
                    } else {
                        const siguiente = marca[2] ? (Number(marca[2]) + 1) + ". " : marca[0]
                        editor.insert(cursor, "<br>" + siguiente)
                        editor.cursorPosition = cursor + siguiente.length + 1
                    }
                    actualizando = false
                    guardarContenido()
                    return true
                }

                Connections {
                    target: raiz
                    function onNotaActivaChanged() { panelNotas.cargarNota() }
                }

                TextEdit {
                    id: conversor
                    visible: false
                    textFormat: TextEdit.MarkdownText
                }
                Component.onCompleted: cargarNota()

                Controls.TextField {
                    id: tituloNota
                    visible: !panelNotas.mostrarLista
                    Layout.fillWidth: true
                    text: raiz.notas[raiz.notaActiva].titulo
                    placeholderText: "Título"
                    placeholderTextColor: Qt.alpha(raiz.texto, 0.55)
                    color: raiz.texto
                    font.pixelSize: 16
                    font.bold: true
                    padding: 4
                    selectByMouse: true
                    background: Item {}
                    onTextEdited: {
                        const nota = raiz.notas[raiz.notaActiva]
                        raiz.guardarNota(Object.assign({}, nota, {titulo: text}))
                    }
                }

                Controls.ScrollView {
                    visible: !panelNotas.mostrarLista
                    Controls.ScrollBar.vertical.policy: raiz.enPanel ? Controls.ScrollBar.AlwaysOff : Controls.ScrollBar.AsNeeded
                    Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Controls.TextArea {
                        id: editor
                        textFormat: TextEdit.RichText
                        persistentSelection: true
                        color: raiz.texto
                        placeholderTextColor: Qt.alpha(raiz.texto, 0.62)
                        placeholderText: "Escribe una nota…"
                        wrapMode: TextEdit.Wrap
                        padding: 4
                        selectByMouse: true
                        background: Item {}
                        onTextChanged: panelNotas.guardarContenido()
                        onCursorPositionChanged: {
                            if (!panelNotas.escribiendoConFormato)
                                panelNotas.cursorFormato = -1
                        }
                        Keys.onPressed: evento => {
                            if (evento.matches(StandardKey.Bold)) {
                                panelNotas.alternarFormato("negrita")
                                evento.accepted = true
                            } else if (evento.matches(StandardKey.Italic)) {
                                panelNotas.alternarFormato("cursiva")
                                evento.accepted = true
                            } else if ((evento.key === Qt.Key_Return || evento.key === Qt.Key_Enter)
                                    && (evento.modifiers === Qt.NoModifier || evento.modifiers === Qt.KeypadModifier)) {
                                evento.accepted = panelNotas.continuarLista()
                            } else if (evento.text && !/[\u0000-\u001F\u007F]/.test(evento.text)
                                    && !(evento.modifiers & (Qt.ControlModifier | Qt.MetaModifier | Qt.AltModifier))) {
                                evento.accepted = panelNotas.escribirConFormato(evento.text)
                            }
                        }
                    }
                }

                RowLayout {
                    visible: !panelNotas.mostrarLista
                    spacing: 2
                    BotonNota {
                        text: "Negrita"
                        icon.name: "format-text-bold"
                        focusPolicy: Qt.TabFocus
                        checkable: true
                        checked: panelNotas.negritaActiva
                        onClicked: panelNotas.alternarFormato("negrita")
                    }
                    BotonNota {
                        text: "Cursiva"
                        icon.name: "format-text-italic"
                        focusPolicy: Qt.TabFocus
                        checkable: true
                        checked: panelNotas.cursivaActiva
                        onClicked: panelNotas.alternarFormato("cursiva")
                    }
                    BotonNota {
                        text: "Lista con guiones"
                        icon.name: "format-list-unordered"
                        onClicked: panelNotas.aplicarLista(false)
                    }
                    BotonNota {
                        text: "Lista numerada"
                        icon.name: "format-list-ordered"
                        onClicked: panelNotas.aplicarLista(true)
                    }
                }

                ListView {
                    visible: panelNotas.mostrarLista
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    readonly property int inicioPagina: raiz.enPanel ? panelNotas.paginaNotas * panelNotas.porPagina : 0
                    model: raiz.enPanel ? raiz.notas.slice(inicioPagina, inicioPagina + panelNotas.porPagina) : raiz.notas
                    currentIndex: raiz.notaActiva - inicioPagina
                    interactive: !raiz.enPanel
                    Controls.ScrollBar.vertical: Controls.ScrollBar {
                        policy: raiz.enPanel ? Controls.ScrollBar.AlwaysOff : Controls.ScrollBar.AsNeeded
                    }
                    onVisibleChanged: if (visible) positionViewAtIndex(currentIndex, ListView.Contain)
                    delegate: Controls.ItemDelegate {
                        id: fila
                        readonly property int indiceNota: index + ListView.view.inicioPagina
                        required property int index
                        required property var modelData
                        width: ListView.view.width
                        height: raiz.enPanel ? 26 : implicitHeight
                        text: modelData.titulo.trim() || (modelData.formato === "html"
                            ? modelData.resumen : modelData.cuerpo.trim().split("\n")[0]) || "Nota sin texto"
                        highlighted: indiceNota === raiz.notaActiva
                        background: Rectangle {
                            radius: 5
                            color: fila.highlighted || fila.visualFocus ? Qt.alpha(raiz.acento, 0.2) : "transparent"
                        }
                        contentItem: Text {
                            text: fila.text
                            textFormat: Text.PlainText
                            color: raiz.texto
                            elide: Text.ElideRight
                        }
                        onClicked: {
                            raiz.preferencias["notaActiva"] = indiceNota
                            panelNotas.mostrarLista = false
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    BotonNota {
                        text: "Nueva nota"
                        icon.name: "list-add"
                        onClicked: {
                            const indice = raiz.notas.length
                            raiz.preferencias["notas"] = JSON.stringify(raiz.notas.concat([{titulo: "", cuerpo: ""}]))
                            raiz.preferencias["notaActiva"] = indice
                            panelNotas.mostrarLista = false
                            tituloNota.forceActiveFocus()
                        }
                    }
                    BotonNota {
                        text: panelNotas.mostrarLista ? "Volver a la nota" : "Lista de notas"
                        icon.name: "view-list-text"
                        onClicked: {
                            panelNotas.mostrarLista = !panelNotas.mostrarLista
                            panelNotas.paginaNotas = Math.floor(raiz.notaActiva / panelNotas.porPagina)
                        }
                    }
                    Item { Layout.fillWidth: true }
                    BotonNota {
                        text: "Nota anterior"
                        icon.name: "go-previous"
                        enabled: raiz.enPanel && panelNotas.mostrarLista ? panelNotas.paginaNotas > 0 : raiz.notaActiva > 0
                        onClicked: {
                            if (raiz.enPanel && panelNotas.mostrarLista) {
                                panelNotas.paginaNotas--
                                return
                            }
                            raiz.preferencias["notaActiva"] = raiz.notaActiva - 1
                            panelNotas.mostrarLista = false
                        }
                    }
                    Controls.Label {
                        text: raiz.enPanel && panelNotas.mostrarLista
                            ? (panelNotas.paginaNotas + 1) + " / " + Math.ceil(raiz.notas.length / panelNotas.porPagina)
                            : (raiz.notaActiva + 1) + " / " + raiz.notas.length
                        color: Qt.alpha(raiz.texto, 0.72)
                    }
                    BotonNota {
                        text: "Nota siguiente"
                        icon.name: "go-next"
                        enabled: raiz.enPanel && panelNotas.mostrarLista
                            ? (panelNotas.paginaNotas + 1) * panelNotas.porPagina < raiz.notas.length
                            : raiz.notaActiva + 1 < raiz.notas.length
                        onClicked: {
                            if (raiz.enPanel && panelNotas.mostrarLista) {
                                panelNotas.paginaNotas++
                                return
                            }
                            raiz.preferencias["notaActiva"] = raiz.notaActiva + 1
                            panelNotas.mostrarLista = false
                        }
                    }
                }
            }
        }
    }
}
