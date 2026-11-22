pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import QtQuick.Effects as Effects

RowLayout {
    id: mini
    required property DatosWidgets modelo
    required property bool vertical
    required property color acento
    required property bool abierto
    signal alternar()
    readonly property var pista: modelo.musicaVisible
    property real grosorPanel: 28
    readonly property real altoControl: Math.min(32, Math.max(1, grosorPanel))
    readonly property real diametro: Math.min(24, Math.max(1, altoControl - 4))
    readonly property bool unaLinea: altoControl < 32
    readonly property string tituloCancion: pista.titulo || ""
    readonly property string artista: pista.artista || ""
    readonly property string album: pista.album || ""
    readonly property var detalles: [...new Set([artista, album].filter(Boolean))]
    property int turnoDetalle: 0
    readonly property string detalle: detalles[turnoDetalle] || detalles[0] || ""
    onDetallesChanged: turnoDetalle = 0
    onTituloCancionChanged: turnoDetalle = 0
    Timer {
        interval: 4000
        repeat: true
        running: mini.visible && !mini.vertical && mini.altoControl >= 15 && mini.detalles.length > 1
        onTriggered: mini.turnoDetalle = (mini.turnoDetalle + 1) % mini.detalles.length
    }
    spacing: 2
    Layout.minimumWidth: implicitWidth
    Layout.minimumHeight: vertical ? implicitHeight : 0

    component Separador: Rectangle {
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredWidth: 1
        Layout.preferredHeight: Math.max(1, Math.round(mini.altoControl * 0.55))
        Layout.leftMargin: 3
        Layout.rightMargin: 3
        color: Qt.alpha(mini.acento, 0.38)
    }

    Controls.ToolButton {
        id: abrir
        padding: 2
        Layout.alignment: Qt.AlignVCenter
        Layout.minimumHeight: 0
        Layout.preferredHeight: mini.altoControl
        Layout.maximumHeight: mini.altoControl
        Accessible.name: mini.abierto ? "Cerrar Música" : "Abrir Música"
        Controls.ToolTip.visible: hovered
        Controls.ToolTip.text: [mini.tituloCancion || "Música", ...mini.detalles].join("\n")
        onClicked: mini.alternar()
        contentItem: RowLayout {
            spacing: 6
            Rectangle {
                id: marco
                Layout.preferredWidth: mini.diametro
                Layout.preferredHeight: mini.diametro
                radius: width / 2
                antialiasing: true
                color: Qt.alpha(mini.acento, 0.25)
                Controls.Label { anchors.centerIn: parent; text: "♫"; color: mini.acento }
                Image {
                    id: portada
                    anchors.fill: parent
                    source: mini.pista.portada || ""
                    asynchronous: true
                    sourceSize: Qt.size(64, 64)
                    fillMode: Image.PreserveAspectCrop
                    visible: status === Image.Ready
                    layer.enabled: visible
                    layer.effect: Effects.MultiEffect {
                        maskEnabled: true
                        maskSource: mascara
                    }
                }
                Rectangle {
                    id: mascara
                    anchors.fill: parent
                    radius: marco.radius
                    antialiasing: true
                    visible: false
                    layer.enabled: portada.visible
                }
            }
            GridLayout {
                visible: !mini.vertical && mini.altoControl >= 15
                columns: mini.unaLinea ? 3 : 1
                columnSpacing: 3
                rowSpacing: 0
                Controls.Label {
                    text: mini.tituloCancion || "Música"
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: mini.unaLinea ? Math.min(110, implicitWidth) : 110
                    Layout.maximumWidth: 110
                    font.pixelSize: 12
                    font.bold: true
                }
                Separador {
                    visible: mini.unaLinea && mini.detalles.length > 0
                }
                Controls.Label {
                    visible: mini.detalles.length > 0
                    text: mini.detalle
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    Layout.preferredWidth: mini.unaLinea ? 96 : 110
                    font.pixelSize: 11
                    opacity: 0.88
                }
            }
        }
    }
    Separador { visible: !mini.vertical }

    Repeater {
        model: mini.vertical ? [] : ["Anterior", "Reproducir", "Siguiente"]
        delegate: Controls.ToolButton {
            id: controlPanel
            required property string modelData
            padding: 2
            Layout.alignment: Qt.AlignVCenter
            Layout.minimumHeight: 0
            Layout.preferredHeight: mini.altoControl
            Layout.maximumHeight: mini.altoControl
            Layout.preferredWidth: Math.min(23, mini.altoControl)
            Accessible.name: modelData === "Reproducir" && mini.modelo.estado.sonando ? "Pausar" : modelData
            contentItem: Item {
                IconoMedia {
                    anchors.centerIn: parent
                    width: Math.min(14, mini.diametro)
                    height: width
                    accion: controlPanel.modelData
                    tinta: controlPanel.palette.buttonText
                    opacity: controlPanel.enabled ? 1 : 0.4
                    sonando: !!mini.modelo.estado.sonando
                }
            }
            enabled: modelData === "Anterior" ? !!mini.modelo.estado.puedeAnterior
                : modelData === "Siguiente" ? !!mini.modelo.estado.puedeSiguiente
                : mini.modelo.estado.destino ? !!mini.modelo.estado.puedeReproducir : !!mini.pista.aplicacion
            onClicked: mini.modelo.controlarMusica(modelData)
        }
    }
}
