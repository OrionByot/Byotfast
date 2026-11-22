pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Dialogs
import QtQuick.Effects as Effects

Item {
    id: marco
    required property var preferencias
    required property color tinta
    required property bool editable
    property real radio: 8
    readonly property bool encuadrando: editable && imagen.status === Image.Ready
        && (cursorFoto.hovered || arrastreFoto.pressed)

    function elegirFoto() {
        elegir.open()
    }

    function limitar(valor) {
        return Math.max(-1, Math.min(1, valor))
    }

    function ajustarZoom(zoom) {
        preferencias["fotoZoom"] = Math.max(1, Math.min(6, zoom))
    }

    function desplazar(dx, dy) {
        if (imagen.rangoX > 0 && dx)
            preferencias["fotoX"] = limitar((preferencias["fotoX"] || 0) + dx / imagen.rangoX)
        if (imagen.rangoY > 0 && dy)
            preferencias["fotoY"] = limitar((preferencias["fotoY"] || 0) + dy / imagen.rangoY)
    }

    FileDialog {
        id: elegir
        title: "Elegir foto"
        nameFilters: ["Imágenes (*.jpg *.jpeg *.png *.webp *.avif *.bmp *.gif *.svg *.heic)", "Todos los archivos (*)"]
        onAccepted: {
            marco.preferencias["fotoZoom"] = 1
            marco.preferencias["fotoX"] = 0
            marco.preferencias["fotoY"] = 0
            marco.preferencias["fotoArchivo"] = String(selectedFile)
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(marco.tinta, 0.07)
        radius: marco.radio
        visible: imagen.status !== Image.Ready
    }

    Rectangle {
        id: mascaraFoto
        anchors.fill: parent
        radius: marco.radio
        antialiasing: true
        visible: false
        layer.enabled: imagen.status === Image.Ready
    }

    Item {
        anchors.fill: parent
        clip: true
        layer.enabled: imagen.status === Image.Ready
        layer.effect: Effects.MultiEffect {
            maskEnabled: true
            maskSource: mascaraFoto
        }
        Image {
            id: imagen
            source: marco.preferencias["fotoArchivo"] || ""
            asynchronous: true
            autoTransform: true
            sourceSize: Qt.size(2560, 2560)
            readonly property real zoomFoto: marco.preferencias["fotoZoom"] || 1
            readonly property real proporcion: implicitHeight > 0 ? implicitWidth / implicitHeight : 1
            readonly property real rangoX: Math.max(0, (width - parent.width) / 2)
            readonly property real rangoY: Math.max(0, (height - parent.height) / 2)
            width: Math.max(parent.width, parent.height * proporcion) * zoomFoto
            height: width / proporcion
            x: -rangoX + rangoX * (arrastreFoto.pressed ? arrastreFoto.posX : marco.preferencias["fotoX"] || 0)
            y: -rangoY + rangoY * (arrastreFoto.pressed ? arrastreFoto.posY : marco.preferencias["fotoY"] || 0)
            fillMode: Image.PreserveAspectFit
        }

        Item {
            anchors.fill: parent
            anchors.margins: 16
            anchors.topMargin: 44
            HoverHandler {
                id: cursorFoto
                enabled: marco.editable && imagen.status === Image.Ready
                acceptedModifiers: Qt.ControlModifier
                cursorShape: Qt.OpenHandCursor
            }
            MouseArea {
                id: arrastreFoto
                anchors.fill: parent
                enabled: cursorFoto.enabled
                acceptedButtons: Qt.MiddleButton
                preventStealing: true
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.ArrowCursor
                property point inicioCursor
                property real inicioX: 0
                property real inicioY: 0
                property real posX: 0
                property real posY: 0
                onPressed: evento => {
                    inicioCursor = Qt.point(evento.x, evento.y)
                    inicioX = marco.preferencias["fotoX"] || 0
                    inicioY = marco.preferencias["fotoY"] || 0
                    posX = inicioX
                    posY = inicioY
                }
                onPositionChanged: evento => {
                    if (!pressed)
                        return
                    posX = imagen.rangoX ? marco.limitar(inicioX + (evento.x - inicioCursor.x) / imagen.rangoX) : inicioX
                    posY = imagen.rangoY ? marco.limitar(inicioY + (evento.y - inicioCursor.y) / imagen.rangoY) : inicioY
                }
                scrollGestureEnabled: true
                onWheel: evento => {
                    const pixeles = evento.pixelDelta
                    const grados = evento.angleDelta
                    if (!(evento.modifiers & Qt.ControlModifier)) {
                        evento.accepted = false
                        return
                    }
                    const dx = pixeles.x || grados.x / 4
                    const dy = pixeles.y || grados.y / 4
                    if ((evento.modifiers & Qt.ShiftModifier) || Math.abs(dx) > Math.abs(dy)) {
                        marco.desplazar(dx, dy)
                    } else if (dy) {
                        const pasos = pixeles.y ? pixeles.y / 48 : grados.y / 120
                        marco.ajustarZoom(imagen.zoomFoto * Math.pow(1.12, pasos))
                    }
                    evento.accepted = !!(dx || dy)
                }
                onReleased: {
                    marco.preferencias["fotoX"] = posX
                    marco.preferencias["fotoY"] = posY
                }
            }
            PinchHandler {
                enabled: cursorFoto.enabled
                target: null
                acceptedDevices: PointerDevice.TouchPad
                minimumPointCount: 2
                maximumPointCount: 2
                property real zoomInicial: 1
                onActiveChanged: if (active) zoomInicial = imagen.zoomFoto
                onActiveScaleChanged: if (active) marco.ajustarZoom(zoomInicial * activeScale)
            }
        }
    }

    Controls.Button {
        anchors.centerIn: parent
        visible: imagen.status !== Image.Ready && imagen.status !== Image.Loading
        text: imagen.status === Image.Error ? "Elegir otra foto" : "Añadir foto"
        icon.name: "insert-image-symbolic"
        onClicked: marco.elegirFoto()
    }
    TapHandler {
        acceptedButtons: Qt.LeftButton
        acceptedModifiers: Qt.NoModifier
        enabled: imagen.status === Image.Ready
        onDoubleTapped: Qt.openUrlExternally(imagen.source)
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: menuFoto.popup()
    }
    Controls.Menu {
        id: menuFoto
        Controls.MenuItem {
            text: imagen.source.toString() ? "Elegir otra foto…" : "Elegir foto…"
            icon.name: "document-open-symbolic"
            onTriggered: marco.elegirFoto()
        }
    }
}
