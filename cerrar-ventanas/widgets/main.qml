pragma ComponentBehavior: Bound
import QtQuick
import org.kde.plasma.workspace.dbus as DBus
import QtQuick.Window
import QtQuick.Controls as Controls
import QtQuick.Layouts
import QtCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as PlasmaSupport
import org.kde.plasma.private.containmentlayoutmanager as DesktopLayout

PlasmoidItem {
    id: raiz

    readonly property bool esPerfil: Plasmoid.metaData.pluginId === "org.local.Byotfast.perfilactivo"
    readonly property bool panelVertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property bool enPanel: panelVertical || Plasmoid.formFactor === PlasmaCore.Types.Horizontal
    readonly property bool bloqueado: Plasmoid.immutable
    readonly property string titulo: esPerfil ? "Perfil" : "Limpieza"
    readonly property string icono: esPerfil ? "org.local.Byotfast.Perfil" : "org.local.Byotfast.Papelera"
    readonly property var preferencias: Plasmoid.configuration
    readonly property bool mini: !enPanel && !!preferencias["compacto"]
    readonly property int anchoMini: 164
    readonly property int altoMini: 38
    readonly property int anchoNormal: 248
    property real anchoExpandido: anchoNormal
    readonly property string carpeta: decodeURIComponent(
        StandardPaths.writableLocation(StandardPaths.GenericDataLocation).toString().replace(/^file:\/\//, "")
    ) + "/cerrar-ventanas/"
    readonly property string tema: apariencia.tema || estado.tema || "Sistema"
    readonly property bool vidrio: tema === "Liquid Glass"
    readonly property color acento: (apariencia.acento ?? estado.acento) || Kirigami.Theme.highlightColor
    readonly property bool oscuro: tema === "Oscuro" || (tema !== "Claro"
        && Kirigami.Theme.backgroundColor.r + Kirigami.Theme.backgroundColor.g + Kirigami.Theme.backgroundColor.b < 1.5)
    readonly property color fondo: vidrio ? (oscuro ? "#1b1b1b" : "#e5e5e5") : (oscuro ? "#1c222b" : "#edf2fa")
    readonly property color superficie: vidrio ? (oscuro ? "#343434" : "#ffffff") : (oscuro ? "#252c36" : "#f9fbff")
    readonly property color texto: enPanel ? Kirigami.Theme.textColor : oscuro ? "#f2f5fa" : "#192537"
    readonly property color borde: vidrio ? (oscuro ? "#85c8c8c8" : "#eaffffff")
        : oscuro ? "#444e5b" : "#c9d2df"
    readonly property color vidrioClaro: oscuro ? "#b3343434" : "#c4ffffff"
    readonly property color vidrioOscuro: oscuro ? "#cf1b1b1b" : "#cfe5e5e5"
    readonly property Item wallpaper: (soporte?.layout?.containmentItem as ContainmentItem)?.wallpaper ?? null
    readonly property bool fondoDifuso: vidrio && !!wallpaper && GraphicsInfo.api !== GraphicsInfo.Software
    readonly property color primario: Qt.darker(acento, 1.18)
    readonly property color textoPrimario: 0.2126 * primario.r + 0.7152 * primario.g + 0.0722 * primario.b > 0.57 ? "#102034" : "#ffffff"
    property var estado: ({})
    property string comandoEnCurso: ""
    property string limpiezaEnCurso: ""
    property string consultaPreferencias: ""
    property bool perfilNotificadoDuranteConsulta: false
    property var apariencia: ({})
    property bool temaRecibido: false
    property bool accionRecibida: false
    property bool refrescarDespues: false
    property string error: ""
    property bool cambiandoPerfil: false
    readonly property var perfiles: estado.perfiles || []
    readonly property int indice: perfiles.findIndex(p => p.id === estado.activo)
    readonly property string perfil: indice >= 0 ? perfiles[indice].nombre : "Perfil"
    readonly property string accionLimpieza: apariencia.accion || estado.accion || "revisar"
    readonly property int altura: fullRepresentationItem ? fullRepresentationItem.implicitHeight : (esPerfil ? 128 : 148)
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

    preferredRepresentation: enPanel ? compactRepresentation : fullRepresentation
    switchWidth: -1
    switchHeight: -1
    Layout.minimumWidth: enPanel ? 0 : mini ? anchoMini : 208
    Layout.minimumHeight: enPanel ? 0 : mini ? altoMini : altura
    Layout.preferredWidth: enPanel ? -1 : mini ? anchoMini : anchoExpandido
    Layout.preferredHeight: enPanel ? -1 : mini ? altoMini : altura
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    toolTipMainText: esPerfil ? "Perfil activo · " + perfil : "Byotfast · Limpieza"
    toolTipSubText: esPerfil ? "Este perfil se usa con el atajo de cierre" : "Consulta temporales y papelera"

    function argumento(valor) {
        return "'" + valor.replace(/'/g, "'\"'\"'") + "'"
    }

    function comando(archivo, argumentos) {
        return "BYOTFAST_WIDGET_REQUEST=" + Date.now() + "-" + Plasmoid.id
            + " /usr/bin/python3 " + argumento(carpeta + archivo) + " " + argumentos
    }

    function ejecutar(argumentos) {
        if (comandoEnCurso)
            return
        cambiandoPerfil = argumentos.indexOf("seleccionar") === 0
        comandoEnCurso = comando("widgets.py", argumentos)
        ejecutor.connectSource(comandoEnCurso)
    }

    function consultar() {
        ejecutar(esPerfil ? "perfil" : "limpieza")
    }

    function consultarPreferencias() {
        if (consultaPreferencias)
            return
        consultaPreferencias = comando("widgets.py", "preferencias")
        ejecutor.connectSource(consultaPreferencias)
    }

    function limpiarDesdeWidget() {
        if (limpiezaEnCurso || (accionLimpieza !== "directo" && accionLimpieza !== "revisar"))
            return
        limpiezaEnCurso = comando("ajustes-cerrar-ventanas.py", "--limpiar-widget " + accionLimpieza)
        acciones.connectSource(limpiezaEnCurso)
    }

    function prepararSoporte() {
        if (!enPanel && soporte) {
            soporte.editModeCondition = DesktopLayout.ItemContainer.Manual
            Qt.callLater(() => ajustarTamano(false))
        }
    }

    function alternarTamano() {
        if (enPanel)
            return
        if (!mini && soporte)
            anchoExpandido = Math.max(anchoNormal, soporte.width)
        preferencias["compacto"] = !mini
        Qt.callLater(() => ajustarTamano(true))
    }


    function ajustarTamano(exacto) {
        const item = soporte
        if (enPanel || !item?.layout)
            return
        const layout = item.layout
        const ancho = mini ? anchoMini : raiz.preferencias["anchoUsuario"] || (exacto ? anchoExpandido
            : item.width <= 300 ? anchoNormal : item.width)
        const alto = mini ? altoMini : raiz.preferencias["altoUsuario"] || (exacto || item.height <= 225 ? altura : Math.max(altura, item.height))
        if (Math.abs(item.width - ancho) < 1 && Math.abs(item.height - alto) < 1)
            return
        const colocado = layout.itemIsManaged(item)
        if (colocado)
            layout.releaseSpace(item)
        item.width = ancho
        item.height = alto
        if (colocado) {
            layout.positionItem(item)
            layout.save()
        }
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

        function dbusPerfilCambiado(carga) {
            if (!raiz.esPerfil)
                return
            const perfil = JSON.parse(carga)
            if (perfil && Array.isArray(perfil.perfiles)) {
                raiz.estado = Object.assign({}, raiz.estado, perfil)
                raiz.perfilNotificadoDuranteConsulta = !!raiz.comandoEnCurso
            } else if (raiz.comandoEnCurso) {
                raiz.refrescarDespues = true
            } else {
                raiz.consultar()
            }
        }

        function dbusAtajoPerfilCambiado(carga) {
            if (!raiz.esPerfil)
                return
            raiz.estado = Object.assign({}, raiz.estado, {atajo: JSON.parse(carga)})
            if (raiz.comandoEnCurso)
                raiz.refrescarDespues = true
        }

        function dbusLimpiezaCambiada(carga) {
            if (raiz.esPerfil)
                return
            raiz.accionRecibida = true
            raiz.apariencia = Object.assign({}, raiz.apariencia, {accion: JSON.parse(carga)})
            if (raiz.comandoEnCurso)
                raiz.refrescarDespues = true
            else
                raiz.consultar()
        }
    }

    PlasmaSupport.DataSource {
        id: ejecutor
        engine: "executable"
        connectedSources: []
        onNewData: (fuente, datos) => {
            if (fuente === raiz.consultaPreferencias && typeof datos.stdout === "string") {
                disconnectSource(fuente)
                raiz.consultaPreferencias = ""
                try {
                    const resultado = JSON.parse(datos.stdout)
                    const cambios = {}
                    if (!raiz.temaRecibido && resultado.tema) {
                        cambios.tema = resultado.tema
                        cambios.acento = resultado.acento
                    }
                    if (!raiz.accionRecibida && resultado.accion)
                        cambios.accion = resultado.accion
                    raiz.apariencia = Object.assign({}, raiz.apariencia, cambios)
                } catch (_) {
                    // Mantén la última apariencia válida si falla una consulta.
                }
                return
            }
            if (fuente !== raiz.comandoEnCurso || typeof datos.stdout !== "string")
                return
            disconnectSource(fuente)
            raiz.comandoEnCurso = ""
            const conservarPerfil = raiz.perfilNotificadoDuranteConsulta
            raiz.perfilNotificadoDuranteConsulta = false
            try {
                const respuesta = JSON.parse(datos.stdout)
                if (respuesta.error)
                    throw new Error(respuesta.error)
                if (conservarPerfil) {
                    respuesta.activo = raiz.estado.activo
                    respuesta.perfiles = raiz.estado.perfiles
                }
                if (JSON.stringify(respuesta) !== JSON.stringify(raiz.estado))
                    raiz.estado = respuesta
                raiz.error = ""
            } catch (_) {
                raiz.error = "No se pudieron leer los datos de Byotfast."
            }
            raiz.cambiandoPerfil = false
            if (raiz.refrescarDespues) {
                raiz.refrescarDespues = false
                Qt.callLater(raiz.consultar)
            }
        }
    }

    PlasmaSupport.DataSource {
        id: acciones
        engine: "executable"
        connectedSources: []
        onNewData: (fuente, datos) => {
            if (fuente !== raiz.limpiezaEnCurso || typeof datos.stdout !== "string")
                return
            disconnectSource(fuente)
            raiz.limpiezaEnCurso = ""
            if (raiz.comandoEnCurso)
                raiz.refrescarDespues = true
            else
                raiz.consultar()
        }
    }

    Timer {
        interval: 60000
        running: !raiz.esPerfil
        repeat: true
        onTriggered: raiz.consultar()
    }


    onSoporteChanged: prepararSoporte()
    onEnPanelChanged: prepararSoporte()
    Component.onCompleted: {
        prepararSoporte()
        consultar()
        consultarPreferencias()
    }

    compactRepresentation: AccesoPanel {
        acento: raiz.acento
        titulo: raiz.titulo
        icon.name: raiz.icono
        vertical: raiz.panelVertical
        desplegable: raiz.esPerfil
        abierto: raiz.expanded
        text: raiz.esPerfil ? raiz.perfil : raiz.estado.papelera || "…"
        onClicked: {
            raiz.expanded = !raiz.expanded
            if (raiz.expanded && !raiz.esPerfil)
                raiz.consultar()
        }
    }

    component IconoContenido: Item {
        id: marcoIcono
        required property string source
        required property real escala
        Layout.preferredWidth: 19
        Layout.preferredHeight: 19
        Kirigami.Icon {
            anchors.centerIn: parent
            width: marcoIcono.width * marcoIcono.escala
            height: marcoIcono.height * marcoIcono.escala
            scale: 1 / marcoIcono.escala
            source: marcoIcono.source
            color: raiz.texto
            isMask: true
        }
    }

    onExpandedChanged: if (enPanel && expanded) consultar()

    fullRepresentation: Rectangle {
        id: tarjeta
        readonly property var ventanaTarjeta: Window.window
        readonly property size tamanoPanel: raiz.esPerfil ? Qt.size(224,132) : Qt.size(244,166)
        Layout.maximumWidth: raiz.enPanel ? tamanoPanel.width : Infinity
        Layout.maximumHeight: raiz.enPanel ? tamanoPanel.height : Infinity
        clip: raiz.enPanel
        Layout.minimumWidth: raiz.enPanel ? tamanoPanel.width : raiz.mini ? raiz.anchoMini : 208
        Layout.preferredWidth: raiz.enPanel ? tamanoPanel.width : raiz.mini ? raiz.anchoMini : raiz.anchoNormal
        implicitHeight: raiz.mini ? raiz.altoMini : interior.implicitHeight + 24
        Layout.minimumHeight: raiz.enPanel ? tamanoPanel.height : implicitHeight
        Layout.preferredHeight: Layout.minimumHeight
        color: raiz.enPanel ? "transparent" : raiz.fondo
        gradient: raiz.enPanel ? null : degradado
        property Gradient degradado: Gradient {
            GradientStop { position: 0; color: raiz.fondoDifuso ? raiz.vidrioClaro : raiz.superficie }
            GradientStop { position: 1; color: raiz.fondoDifuso ? raiz.vidrioOscuro : raiz.fondo }
        }
        radius: raiz.mini ? 9 : 14
        border.width: raiz.enPanel ? 0 : 1
        border.color: raiz.borde
        FondoDifuso { active: !raiz.enPanel && raiz.fondoDifuso && !mover.contenedor; fondo: raiz.wallpaper; radio: tarjeta.radius }
        transform: Translate {
            x: mover.contenedor ? mover.destino.x - mover.contenedor.x : 0
            y: mover.contenedor ? mover.destino.y - mover.contenedor.y : 0
        }
        MouseArea {
            id: filtroMenu
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            onPressed: evento => {
                const titulo = raiz.mini ? tituloMini : interior.tituloMenu
                const punto = titulo.mapFromItem(filtroMenu, evento.x, evento.y)
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
            onTamanoElegido: (ancho, alto) => {
                raiz.preferencias["anchoUsuario"] = ancho
                raiz.preferencias["altoUsuario"] = alto
            }
            soporte: !raiz.enPanel && !raiz.bloqueado ? raiz.soporte : null
        }
        RowLayout {
            visible: raiz.mini
            anchors.fill: parent
            anchors.leftMargin: 9
            anchors.rightMargin: 5
            spacing: 6
            Controls.AbstractButton {
                id: abrirAcciones
                Layout.fillWidth: true
                Layout.fillHeight: true
                padding: 0
                Accessible.name: raiz.esPerfil ? "Abrir selector de perfil" : "Abrir controles de limpieza"
                hoverEnabled: true
                background: Rectangle {
                    radius: 6
                    color: abrirAcciones.visualFocus ? raiz.superficie : "transparent"
                }
                contentItem: RowLayout {
                    spacing: 5
                    Kirigami.Icon {
                        source: raiz.icono
                        color: raiz.acento
                        isMask: true
                        Layout.preferredWidth: 18
                        Layout.preferredHeight: 18
                    }
                    Controls.Label {
                        id: tituloMini
                        text: raiz.esPerfil ? raiz.perfil : raiz.titulo
                        color: raiz.texto
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
                onClicked: {
                    if (accionesMini.visible) {
                        accionesMini.close()
                    } else {
                        accionesMini.open()
                        if (!raiz.esPerfil)
                            raiz.consultar()
                    }
                }
            }
            BotonTamano {
                acento: raiz.acento
                restaurar: true
                onClicked: raiz.alternarTamano()
            }
        }
        component ControlesTarjeta: ColumnLayout {
            id: controles
            property alias tituloMenu: tituloMenu
            property alias encabezado: filaEncabezado
            property bool botonTamanoVisible: false
            spacing: 6
            Item {
                id: marcoEncabezado
                Layout.fillWidth: true
                Layout.preferredHeight: filaEncabezado.implicitHeight / controles.scale
                RowLayout {
                    id: filaEncabezado
                    width: raiz.enPanel ? implicitWidth : marcoEncabezado.width * controles.scale
                    x: raiz.enPanel ? (marcoEncabezado.width - width) / 2 : 0
                    scale: 1 / controles.scale
                    transformOrigin: Item.TopLeft
                    spacing: 8
                    Kirigami.Icon {
                        source: raiz.icono
                        color: raiz.acento
                        isMask: true
                        Layout.preferredWidth: 22
                        Layout.preferredHeight: 22
                    }
                    Controls.Label {
                        id: tituloMenu
                        Layout.fillWidth: !raiz.enPanel
                        text: raiz.titulo
                        color: raiz.texto
                        font.bold: true
                    }
                    BotonTamano {
                        visible: controles.botonTamanoVisible
                        acento: raiz.acento
                        restaurar: false
                        onClicked: raiz.alternarTamano()
                    }
                }
            }
            GrupoCentrado {
                spacing: controles.spacing
                Controls.ComboBox {
                    id: selectorPerfil
                    visible: raiz.esPerfil
                    Layout.fillWidth: true
                    Layout.minimumHeight: 34
                    Layout.preferredHeight: 34
                    model: raiz.perfiles
                    textRole: "nombre"
                    currentIndex: raiz.indice
                    onModelChanged: Qt.callLater(sincronizar)
                    function sincronizar() {
                        if (currentIndex !== raiz.indice)
                            currentIndex = raiz.indice
                    }
                    Connections {
                        target: raiz
                        function onIndiceChanged() { selectorPerfil.sincronizar() }
                    }
                    enabled: !raiz.cambiandoPerfil && raiz.perfiles.length > 0
                    background: Rectangle {
                        color: raiz.superficie
                        radius: 8
                        border.width: selectorPerfil.popup.visible || selectorPerfil.activeFocus ? 2 : 1
                        border.color: selectorPerfil.popup.visible || selectorPerfil.activeFocus ? raiz.acento : raiz.borde
                    }
                    contentItem: Controls.Label {
                        text: selectorPerfil.displayText
                        color: raiz.texto
                        font.pixelSize: 17
                        leftPadding: 8
                        rightPadding: 27
                        verticalAlignment: Text.AlignVCenter
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                    }
                    indicator: Flecha {
                        x: selectorPerfil.width - width - 13
                        y: (selectorPerfil.height - height) / 2
                        width: 14
                        height: 14
                        rotation: selectorPerfil.popup.visible ? -90 : 90
                        colorTrazo: raiz.texto
                    }
                    delegate: Controls.ItemDelegate {
                        id: opcionPerfil
                        required property int index
                        required property var modelData
                        width: selectorPerfil.popup.availableWidth
                        height: 34
                        contentItem: Controls.Label {
                            text: opcionPerfil.modelData.nombre
                            color: opcionPerfil.index === raiz.indice ? raiz.textoPrimario : raiz.texto
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                        }
                        highlighted: selectorPerfil.highlightedIndex === index
                        background: Rectangle {
                            radius: 5
                            color: opcionPerfil.index === raiz.indice ? raiz.primario
                                : opcionPerfil.highlighted ? raiz.borde : "transparent"
                        }
                    }
                    popup: Controls.Popup {
                        y: selectorPerfil.height + 5
                        width: selectorPerfil.width
                        padding: 4
                        margins: 8
                        implicitHeight: Math.min(200, selectorPerfil.count * 34 + topPadding + bottomPadding)
                        contentItem: ListView {
                            id: menuPerfiles
                            clip: true
                            model: selectorPerfil.popup.visible ? selectorPerfil.delegateModel : null
                            currentIndex: selectorPerfil.highlightedIndex
                        }
                        background: Rectangle {
                            radius: 8
                            color: raiz.fondo
                            border.color: raiz.borde
                        }
                    }
                    onActivated: function(indiceElegido) {
                        const clave = raiz.perfiles[indiceElegido].id
                        if (/^(predeterminado|[0-9a-f]{32})$/.test(clave)) {
                            raiz.perfilPendiente = clave
                            selectorPendiente.restart()
                        }
                    }
                }
                Flow {
                    id: teclasPerfil
                    Layout.alignment: Qt.AlignHCenter
                    Layout.maximumWidth: controles.width
                    Layout.preferredWidth: {
                        let ancho = 0
                        for (let i = 0; i < teclasPerfil.children.length; ++i) {
                            const elemento = teclasPerfil.children[i]
                            if (elemento.width > 0)
                                ancho += elemento.width + spacing
                        }
                        return Math.max(0, ancho - spacing)
                    }
                    spacing: 4
                    visible: raiz.esPerfil && !!raiz.estado.atajo
                    Repeater {
                        model: raiz.estado.atajo ? raiz.estado.atajo.split("+") : []
                        Rectangle {
                            required property string modelData
                            width: tecla.implicitWidth + 12
                            height: tecla.implicitHeight + 6
                            radius: 5
                            color: raiz.fondo
                            border.color: raiz.borde
                            Controls.Label {
                                id: tecla
                                text: parent.modelData
                                color: raiz.texto
                                anchors.centerIn: parent
                                font.pixelSize: 12
                            }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: !raiz.esPerfil
                    IconoContenido { escala: controles.scale; source: "text-x-generic" }
                    Controls.Label { text: "Temporales"; color: raiz.texto; font.pixelSize: 14; Layout.fillWidth: true }
                    Controls.Label { text: raiz.estado.temporales || "…"; color: raiz.texto; font.pixelSize: 14; font.weight: Font.DemiBold }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    visible: !raiz.esPerfil
                    color: raiz.borde
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: !raiz.esPerfil
                    IconoContenido { escala: controles.scale; source: "org.local.Byotfast.Papelera" }
                    Controls.Label { text: "Papelera"; color: raiz.texto; font.pixelSize: 14; Layout.fillWidth: true }
                    Controls.Label { text: raiz.estado.papelera || "…"; color: raiz.texto; font.pixelSize: 14; font.weight: Font.DemiBold }
                }
                Controls.Button {
                    id: botonLimpieza
                    visible: !raiz.esPerfil && raiz.accionLimpieza !== "solo_atajo"
                    text: raiz.accionLimpieza === "directo" ? "Limpiar" : "Revisar limpieza"
                    Layout.fillWidth: true
                    Layout.minimumHeight: 32
                    Layout.preferredHeight: 32
                    enabled: !raiz.limpiezaEnCurso
                    contentItem: Controls.Label {
                        text: botonLimpieza.text
                        color: raiz.textoPrimario
                        font.bold: true
                        font.pixelSize: 15
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: 7
                        color: botonLimpieza.down ? Qt.darker(raiz.primario, 1.18)
                            : botonLimpieza.hovered ? Qt.lighter(raiz.primario, 1.10) : raiz.primario
                        border.color: raiz.acento
                    }
                    onClicked: raiz.limpiarDesdeWidget()
                }
                Controls.Label {
                    visible: raiz.error !== ""
                    Layout.fillWidth: true
                    text: raiz.error
                    color: raiz.texto
                    wrapMode: Text.WordWrap
                }
            }
        }
        ControlesTarjeta {
            id: interior
            visible: !raiz.mini
            x: 12
            y: 12
            width: (tarjeta.width - 24) / scale
            height: (tarjeta.height - 24) / scale
            transformOrigin: Item.TopLeft
            scale: raiz.enPanel ? 1 : Math.max(1, Math.min((tarjeta.width - 24) / 184, (tarjeta.height - 24) / (raiz.esPerfil ? 104 : 136)))
            botonTamanoVisible: !raiz.enPanel
        }

        Controls.Popup {
            id: accionesMini
            parent: tarjeta
            x: 0
            y: tarjeta.height + 5
            width: raiz.anchoNormal
            padding: 12
            margins: 8
            modal: false
            focus: true
            closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutsideParent
            onAboutToShow: {
                const ventana = tarjeta.ventanaTarjeta
                const debajo = tarjeta.mapToItem(null, 0, tarjeta.height + 5).y
                y = ventana && debajo + implicitHeight + 8 > ventana.height
                    ? -implicitHeight - 5 : tarjeta.height + 5
            }
            background: Rectangle {
                id: fondoPopup
                radius: 12
                color: raiz.fondo
                gradient: Gradient {
                    GradientStop { position: 0; color: raiz.fondoDifuso ? raiz.vidrioClaro : raiz.superficie }
                    GradientStop { position: 1; color: raiz.fondoDifuso ? raiz.vidrioOscuro : raiz.fondo }
                }
                border.color: raiz.borde
                FondoDifuso { active: raiz.fondoDifuso; fondo: raiz.wallpaper; radio: fondoPopup.radius }
            }
            contentItem: ControlesTarjeta {}
        }
        Connections {
            target: raiz
            function onMiniChanged() {
                if (!raiz.mini)
                    accionesMini.close()
            }
        }
    }

    property string perfilPendiente: ""
    Timer {
        id: selectorPendiente
        interval: 150
        repeat: true
        onTriggered: {
            if (!raiz.comandoEnCurso) {
                stop()
                raiz.ejecutar("seleccionar " + raiz.perfilPendiente)
            }
        }
    }
}
